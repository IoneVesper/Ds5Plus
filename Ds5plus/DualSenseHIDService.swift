import Foundation
import IOKit.hid
import QuartzCore

final class DualSenseHIDService {
    private static let sonyVendorID = 0x054C
    private static let dualSenseProductIDs: Set<Int> = [0x0CE6, 0x0DF2]
    private static let firmwareInfoReportID: CFIndex = 0x20
    private static let firmwareInfoReportSize = 64
    private static let featureVersionVibrationV2 = UInt16(0x0215) // 2.21
    private static let bluetoothInputReportID: UInt8 = 0x31
    private static let bluetoothInputReportSize = 78
    private static let bluetoothStatusOffset = 54

    private let manager: IOHIDManager
    private let outputQueue = DispatchQueue(label: "Ds5plus.hid.output.queue", qos: .userInteractive)
    private var knownDevices: [String: IOHIDDevice] = [:]
    private var deviceInfos: [String: DualSenseDeviceInfo] = [:]
    private var deviceStates: [String: DeviceState] = [:]
    private var inputReportBuffers: [String: InputReportBuffer] = [:]
    private var openedDeviceIDs: Set<String> = []
    private var timer: DispatchSourceTimer?
    private var pulseStopWorkItem: DispatchWorkItem?
    private var currentDeviceID: String?
    private var currentConfiguration = HapticConfiguration()
    private var sequenceNumber: UInt8 = 0
    private var stats = DriverStats()
    private var lastPublishedBatteryStatus: [String: ControllerBatteryStatus] = [:]
    private var lastBatteryProcessTime: [String: CFTimeInterval] = [:]

    var onDevicesChanged: @Sendable ([DualSenseDeviceInfo]) -> Void = { _ in }
    var onLog: @Sendable (String) -> Void = { _ in }
    var onStatsChanged: @Sendable (DriverStats) -> Void = { _ in }
    var onBatteryChanged: @Sendable (String, ControllerBatteryStatus) -> Void = { _, _ in }

    init(startMonitoring: Bool = true) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))

        guard startMonitoring else { return }

        let matches: [[String: Any]] = Self.dualSenseProductIDs.map { productID in
            [
                kIOHIDVendorIDKey: Self.sonyVendorID,
                kIOHIDProductIDKey: productID,
                kIOHIDTransportKey: "Bluetooth"
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if status == kIOReturnSuccess {
            log("HID 管理器已启动，等待蓝牙 DualSense 接入。")
        } else {
            log("HID 管理器启动失败: \(status)")
        }
        refreshDevicesSnapshot()
    }

    deinit {
        stopEffect()
        outputQueue.sync {}
        for deviceID in openedDeviceIDs {
            if let device = knownDevices[deviceID] {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        openedDeviceIDs.removeAll()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func refreshDevicesSnapshot() {
        guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
            publishDevices()
            return
        }

        let count = CFSetGetCount(deviceSet)
        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { values.deallocate() }
        CFSetGetValues(deviceSet, values)

        var refreshed: [String: IOHIDDevice] = [:]
        var infos: [String: DualSenseDeviceInfo] = [:]

        for index in 0 ..< count {
            guard let value = values[index] else { continue }
            let device = unsafeBitCast(value, to: IOHIDDevice.self)
            guard let info = deviceInfo(for: device) else { continue }
            refreshed[info.id] = device
            infos[info.id] = info
        }

        let removedDeviceIDs = Set(knownDevices.keys).subtracting(refreshed.keys)
        for deviceID in removedDeviceIDs {
            let wasCurrentDevice = currentDeviceID == deviceID
            cleanupDevice(deviceID: deviceID, device: knownDevices[deviceID])
            if wasCurrentDevice {
                stopEffect()
            }
        }

        knownDevices = refreshed
        deviceInfos = infos
        publishDevices()
    }

    @discardableResult
    func startEffect(deviceID: String, configuration: HapticConfiguration) -> Bool {
        guard prepareDevice(deviceID: deviceID) else { return false }

        currentDeviceID = deviceID
        currentConfiguration = configuration
        pulseStopWorkItem?.cancel()
        pulseStopWorkItem = nil
        startTimerIfNeeded()
        log("已开始无线 HID 直驱: \(deviceInfos[deviceID]?.displayName ?? deviceID)")
        return true
    }

    @discardableResult
    func startRealtimeControl(deviceID: String) -> Bool {
        stopEffect()
        guard prepareDevice(deviceID: deviceID) else { return false }
        currentDeviceID = deviceID
        log("已开始音频驱动模式: \(deviceInfos[deviceID]?.displayName ?? deviceID)")
        return true
    }

    func sendRealtimeHaptics(leftMotor: UInt8, rightMotor: UInt8, lightbar: (UInt8, UInt8, UInt8) = (0, 96, 255)) {
        guard let currentDeviceID, let device = knownDevices[currentDeviceID] else { return }
        sendReport(to: device, deviceID: currentDeviceID, leftMotor: leftMotor, rightMotor: rightMotor, lightbar: lightbar)
    }

    func previewLightbar(deviceID: String, color: (UInt8, UInt8, UInt8)) {
        guard prepareDevice(deviceID: deviceID), let device = knownDevices[deviceID] else { return }
        sendReport(to: device, deviceID: deviceID, leftMotor: 0, rightMotor: 0, lightbar: (0, 0, 0), resetLightbar: true)
        for step in 0 ..< 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + (.milliseconds(step * 20))) { [weak self] in
                guard let self else { return }
                self.sendReport(to: device, deviceID: deviceID, leftMotor: 0, rightMotor: 0, lightbar: color)
            }
        }
    }

    func refreshBatteryStatus(deviceID: String) {
        guard prepareDevice(deviceID: deviceID), let device = knownDevices[deviceID] else { return }

        if pollBatteryStatusFromInputReport(device: device, forcePublish: true) {
            return
        }

        if let batteryLevel = intProperty(device, key: "BatteryPercent") ?? intProperty(device, key: "BatteryLevel"),
           let info = deviceInfo(for: device) {
            let percentage = min(max(batteryLevel, 0), 100)
            let state = percentage >= 100 ? BatteryChargingState.full : .unknown
            publishBatteryStatus(
                ControllerBatteryStatus(percentage: percentage, chargingState: state),
                for: info.id,
                force: true
            )
        }
    }

    static func batteryStatus(fromBluetoothStatusByte status: UInt8) -> ControllerBatteryStatus {
        let batteryRaw = Int(status & 0x0F)
        let chargingBits = Int((status >> 4) & 0x0F)

        let percentage: Int?
        if batteryRaw <= 9 {
            percentage = min(max((batteryRaw + 1) * 10, 10), 100)
        } else if batteryRaw == 10 {
            percentage = 100
        } else {
            percentage = nil
        }

        let chargingState: BatteryChargingState
        switch chargingBits {
        case 0x0:
            chargingState = .discharging
        case 0x1:
            chargingState = .charging
        case 0x2:
            chargingState = .full
        case 0xA, 0xB:
            chargingState = .notCharging
        default:
            chargingState = .unknown
        }

        return ControllerBatteryStatus(percentage: percentage, chargingState: chargingState)
    }

    func updateEffect(configuration: HapticConfiguration) {
        currentConfiguration = configuration
    }

    private func prepareDevice(deviceID: String) -> Bool {
        guard let device = knownDevices[deviceID] else {
            log("未找到目标 DualSense 设备。")
            return false
        }

        if !openedDeviceIDs.contains(deviceID) {
            let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            switch openStatus {
            case kIOReturnSuccess:
                openedDeviceIDs.insert(deviceID)
            case kIOReturnExclusiveAccess:
                log("打开 DualSense 失败：设备正被其他应用独占。请关闭可能占用手柄的游戏、Steam 输入或其他驱动后重试。")
                return false
            default:
                log("打开 DualSense 失败: \(openStatus)")
                return false
            }
        }

        registerInputReportCallbackIfNeeded(deviceID: deviceID, device: device)

        if deviceStates[deviceID] == nil {
            deviceStates[deviceID] = probeState(for: device, productID: deviceInfos[deviceID]?.productID)
        }

        return true
    }

    func stopEffect() {
        timer?.cancel()
        timer = nil
        pulseStopWorkItem?.cancel()
        pulseStopWorkItem = nil

        if let currentDeviceID, let device = knownDevices[currentDeviceID] {
            sendReport(to: device, deviceID: currentDeviceID, leftMotor: 0, rightMotor: 0, lightbar: (0, 0, 0))
        }
        currentDeviceID = nil
        log("已发送停止报告。")
    }

    func pulse(deviceID: String, configuration: HapticConfiguration, duration: TimeInterval = 0.35) {
        stopEffect()
        guard prepareDevice(deviceID: deviceID), let device = knownDevices[deviceID] else { return }

        currentDeviceID = deviceID
        currentConfiguration = configuration
        sendReport(to: device, deviceID: deviceID, leftMotor: configuration.leftMotor, rightMotor: configuration.rightMotor, lightbar: (0, 64, 255))

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let currentDeviceID = self.currentDeviceID, let activeDevice = self.knownDevices[currentDeviceID] else { return }
            self.sendReport(to: activeDevice, deviceID: currentDeviceID, leftMotor: 0, rightMotor: 0, lightbar: (0, 0, 0))
            self.currentDeviceID = nil
            self.log("单次脉冲完成。")
        }
        pulseStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func startTimerIfNeeded() {
        if timer != nil { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard let currentDeviceID, let device = knownDevices[currentDeviceID] else { return }

        let leftMotor: UInt8
        let rightMotor: UInt8
        switch currentConfiguration.mode {
        case .constant:
            leftMotor = currentConfiguration.leftMotor
            rightMotor = currentConfiguration.rightMotor
        case .pulse:
            let period = 1.0 / max(currentConfiguration.pulseFrequency, 0.5)
            let phase = fmod(CACurrentMediaTime(), period)
            let enabled = phase < (period * 0.5)
            leftMotor = enabled ? currentConfiguration.leftMotor : 0
            rightMotor = enabled ? currentConfiguration.rightMotor : 0
        }

        sendReport(to: device, deviceID: currentDeviceID, leftMotor: leftMotor, rightMotor: rightMotor, lightbar: (0, 64, 255))
    }

    private func sendReport(to device: IOHIDDevice, deviceID: String, leftMotor: UInt8, rightMotor: UInt8, lightbar: (UInt8, UInt8, UInt8), resetLightbar: Bool = false) {
        let state = deviceStates[deviceID] ?? DeviceState(useVibrationV2: true, updateVersion: nil, firmwareVersion: nil, hardwareVersion: nil)
        sequenceNumber = (sequenceNumber + 1) & 0x0F
        let sequence = sequenceNumber

        let report = DualSenseBluetoothOutputReport(
            sequence: sequence,
            leftMotor: leftMotor,
            rightMotor: rightMotor,
            useVibrationV2: state.useVibrationV2,
            lightbar: lightbar,
            resetLightbar: resetLightbar
        ).bytes

        outputQueue.async {
            let result = report.withUnsafeBytes { rawBuffer -> IOReturn in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return kIOReturnBadArgument
                }
                return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), baseAddress, report.count)
            }

            DispatchQueue.main.async { [weak self] in
                self?.recordReportResult(result, sequence: sequence, leftMotor: leftMotor, rightMotor: rightMotor)
            }
        }
    }

    private func recordReportResult(_ result: IOReturn, sequence: UInt8, leftMotor: UInt8, rightMotor: UInt8) {
        stats.sentReports += 1
        stats.lastSequence = Int(sequence)
        stats.lastLeftMotor = Int(leftMotor)
        stats.lastRightMotor = Int(rightMotor)
        stats.lastResult = result == kIOReturnSuccess ? "ok" : "\(result)"
        onStatsChanged(stats)

        if result != kIOReturnSuccess {
            log("发送 HID 输出报告失败: \(result)")
        }
    }

    private func probeState(for device: IOHIDDevice, productID: Int?) -> DeviceState {
        var report = [UInt8](repeating: 0, count: Self.firmwareInfoReportSize)
        report[0] = UInt8(Self.firmwareInfoReportID)
        var reportLength = CFIndex(report.count)
        let status = report.withUnsafeMutableBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, Self.firmwareInfoReportID, baseAddress, &reportLength)
        }

        guard status == kIOReturnSuccess, Int(reportLength) >= 46 else {
            log("读取固件信息失败，默认尝试 vibration v2: \(status)")
            return DeviceState(useVibrationV2: true, updateVersion: nil, firmwareVersion: nil, hardwareVersion: nil)
        }

        let hardwareVersion = littleEndianUInt32(report, offset: 24)
        let firmwareVersion = littleEndianUInt32(report, offset: 28)
        let updateVersion = littleEndianUInt16(report, offset: 44)

        let useVibrationV2: Bool
        if productID == 0x0DF2 {
            useVibrationV2 = true
        } else {
            useVibrationV2 = updateVersion >= Self.featureVersionVibrationV2
        }

        log("DualSense 固件信息：hw=0x\(String(hardwareVersion, radix: 16, uppercase: true)) fw=0x\(String(firmwareVersion, radix: 16, uppercase: true)) update=\(formatFeatureVersion(updateVersion)) vibration=\(useVibrationV2 ? "v2" : "legacy")")

        return DeviceState(
            useVibrationV2: useVibrationV2,
            updateVersion: updateVersion,
            firmwareVersion: firmwareVersion,
            hardwareVersion: hardwareVersion
        )
    }

    private func formatFeatureVersion(_ value: UInt16) -> String {
        let major = Int((value & 0xFF00) >> 8)
        let minor = Int(value & 0x00FF)
        return "\(major).\(minor)"
    }

    private func littleEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func littleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
    }

    private func deviceInfo(for device: IOHIDDevice) -> DualSenseDeviceInfo? {
        let vendorID = intProperty(device, key: kIOHIDVendorIDKey)
        let productID = intProperty(device, key: kIOHIDProductIDKey)
        let transport = stringProperty(device, key: kIOHIDTransportKey)

        guard vendorID == Self.sonyVendorID,
              let productID,
              Self.dualSenseProductIDs.contains(productID),
              transport?.caseInsensitiveCompare("Bluetooth") == .orderedSame else {
            return nil
        }

        let name = stringProperty(device, key: kIOHIDProductKey) ?? "DualSense"
        let serial = stringProperty(device, key: kIOHIDSerialNumberKey)
        let id = serial ?? "\(name)-\(transport ?? "Bluetooth")-\(productID)-\(Unmanaged.passUnretained(device).toOpaque())"

        return DualSenseDeviceInfo(
            id: id,
            name: name,
            serialNumber: serial,
            transport: transport ?? "Bluetooth",
            productID: productID
        )
    }

    private func publishDevices() {
        let devices = deviceInfos.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        onDevicesChanged(devices)
    }

    private func cleanupDevice(deviceID: String, device: IOHIDDevice?) {
        if openedDeviceIDs.remove(deviceID) != nil, let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        deviceStates.removeValue(forKey: deviceID)
        inputReportBuffers.removeValue(forKey: deviceID)
        lastPublishedBatteryStatus.removeValue(forKey: deviceID)
        lastBatteryProcessTime.removeValue(forKey: deviceID)
        if currentDeviceID == deviceID {
            currentDeviceID = nil
        }
    }

    private func log(_ line: String) {
        onLog(line)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private func registerInputReportCallbackIfNeeded(deviceID: String, device: IOHIDDevice) {
        guard inputReportBuffers[deviceID] == nil else { return }
        let buffer = InputReportBuffer(length: Self.bluetoothInputReportSize)
        inputReportBuffers[deviceID] = buffer
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer.pointer,
            buffer.length,
            Self.inputReportCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func pollBatteryStatusFromInputReport(device: IOHIDDevice) -> Bool {
        pollBatteryStatusFromInputReport(device: device, forcePublish: false)
    }

    private func pollBatteryStatusFromInputReport(device: IOHIDDevice, forcePublish: Bool) -> Bool {
        let reportID = Self.bluetoothInputReportID
        var buffer = [UInt8](repeating: 0, count: Self.bluetoothInputReportSize)
        var reportLength = buffer.count
        let result = buffer.withUnsafeMutableBufferPointer { bufferPointer in
            IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeInput,
                CFIndex(reportID),
                bufferPointer.baseAddress!,
                &reportLength
            )
        }

        guard result == kIOReturnSuccess else { return false }
        buffer[0] = reportID
        buffer.withUnsafeBufferPointer { pointer in
            updateBatteryStatus(from: pointer.baseAddress!, length: reportLength, device: device, forcePublish: forcePublish)
        }
        return true
    }

    private func updateBatteryStatus(from report: UnsafePointer<UInt8>, length: CFIndex, device: IOHIDDevice, forcePublish: Bool = false) {
        guard length >= Self.bluetoothStatusOffset + 1 else { return }
        guard report[0] == Self.bluetoothInputReportID else { return }
        guard let info = deviceInfo(for: device) else { return }
        let now = CACurrentMediaTime()
        if !forcePublish, let lastProcessTime = lastBatteryProcessTime[info.id], now - lastProcessTime < 1.0 {
            return
        }
        lastBatteryProcessTime[info.id] = now

        let batteryStatus = Self.batteryStatus(fromBluetoothStatusByte: report[Self.bluetoothStatusOffset])
        publishBatteryStatus(batteryStatus, for: info.id, force: forcePublish)
    }

    private func publishBatteryStatus(_ batteryStatus: ControllerBatteryStatus, for deviceID: String, force: Bool) {
        if !force, lastPublishedBatteryStatus[deviceID] == batteryStatus {
            return
        }
        lastPublishedBatteryStatus[deviceID] = batteryStatus
        onBatteryChanged(deviceID, batteryStatus)
    }

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let service = Unmanaged<DualSenseHIDService>.fromOpaque(context).takeUnretainedValue()
        guard let info = service.deviceInfo(for: device) else { return }
        service.knownDevices[info.id] = device
        service.deviceInfos[info.id] = info
        service.publishDevices()
        service.log("发现 DualSense 蓝牙设备: \(info.displayName)")
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let service = Unmanaged<DualSenseHIDService>.fromOpaque(context).takeUnretainedValue()
        guard let info = service.deviceInfo(for: device) else { return }
        let wasCurrentDevice = service.currentDeviceID == info.id
        service.cleanupDevice(deviceID: info.id, device: device)
        service.knownDevices.removeValue(forKey: info.id)
        service.deviceInfos.removeValue(forKey: info.id)
        if wasCurrentDevice {
            service.stopEffect()
        }
        service.publishDevices()
        service.log("DualSense 已断开: \(info.displayName)")
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, _, sender, reportType, reportID, report, reportLength in
        guard let context, let sender else { return }
        guard reportType == kIOHIDReportTypeInput, reportID == DualSenseHIDService.bluetoothInputReportID else { return }
        let service = Unmanaged<DualSenseHIDService>.fromOpaque(context).takeUnretainedValue()
        let device = unsafeBitCast(sender, to: IOHIDDevice.self)
        service.updateBatteryStatus(from: report, length: reportLength, device: device)
    }
}

private struct DeviceState {
    let useVibrationV2: Bool
    let updateVersion: UInt16?
    let firmwareVersion: UInt32?
    let hardwareVersion: UInt32?
}

private final class InputReportBuffer {
    let pointer: UnsafeMutablePointer<UInt8>
    let length: CFIndex

    init(length: Int) {
        self.length = CFIndex(length)
        self.pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        self.pointer.initialize(repeating: 0, count: length)
    }

    deinit {
        pointer.deallocate()
    }
}

struct DualSenseBluetoothOutputReport {
    static let reportID: UInt8 = 0x31
    static let tag: UInt8 = 0x10
    static let outputCRCSeedByte: UInt8 = 0xA2
    static let size = 78

    static let validFlag0CompatibleVibration: UInt8 = 1 << 0
    static let validFlag0HapticsSelect: UInt8 = 1 << 1

    static let validFlag1LightbarControlEnable: UInt8 = 1 << 2
    static let validFlag1ReleaseLEDBit: UInt8 = 1 << 3
    static let validFlag1PlayerIndicatorControlEnable: UInt8 = 1 << 4
    static let validFlag1HapticLowPassFilterControlEnable: UInt8 = 1 << 5
    static let validFlag1VibrationAttenuationEnable: UInt8 = 1 << 6

    static let validFlag2LightbarSetupControlEnable: UInt8 = 1 << 1
    static let validFlag2CompatibleVibration2: UInt8 = 1 << 2

    static let hapticsFlagLowPassFilter: UInt8 = 1 << 0

    static let playerLEDInner: UInt8 = 0b00100
    static let lightbarSetupDisable: UInt8 = 1 << 0
    static let lightbarSetupEnable: UInt8 = 1 << 1

    let bytes: [UInt8]

    init(sequence: UInt8, leftMotor: UInt8, rightMotor: UInt8, useVibrationV2: Bool, lightbar: (UInt8, UInt8, UInt8), resetLightbar: Bool) {
        var bytes = [UInt8](repeating: 0, count: Self.size)
        bytes[0] = Self.reportID
        bytes[1] = (sequence & 0x0F) << 4
        bytes[2] = Self.tag

        // common.valid_flag0 / valid_flag1
        bytes[3] = Self.validFlag0HapticsSelect
        bytes[4] = Self.validFlag1LightbarControlEnable |
                   Self.validFlag1PlayerIndicatorControlEnable |
                   Self.validFlag1HapticLowPassFilterControlEnable |
                   Self.validFlag1VibrationAttenuationEnable
        if resetLightbar {
            bytes[4] |= Self.validFlag1ReleaseLEDBit
        }

        if useVibrationV2 {
            bytes[41] = Self.validFlag2LightbarSetupControlEnable | Self.validFlag2CompatibleVibration2
        } else {
            bytes[3] |= Self.validFlag0CompatibleVibration
            bytes[41] = Self.validFlag2LightbarSetupControlEnable
        }

        // common.motor_right / motor_left
        bytes[5] = rightMotor
        bytes[6] = leftMotor

        // common.reduce_motor_power: 0 = max strength
        bytes[39] = 0
        // common.audio_flags2
        bytes[40] = 0
        // common.haptics_flags
        bytes[42] = Self.hapticsFlagLowPassFilter
        // common.reserved3
        bytes[43] = 0
        // common.lightbar_setup / led_brightness / player_leds
        bytes[44] = resetLightbar ? Self.lightbarSetupDisable : Self.lightbarSetupEnable
        bytes[45] = 0
        bytes[46] = Self.playerLEDInner
        // common.lightbar_red / green / blue
        bytes[47] = lightbar.0
        bytes[48] = lightbar.1
        bytes[49] = lightbar.2

        let crc = Self.crc32(seedByte: Self.outputCRCSeedByte, report: bytes[0 ..< Self.size - 4])
        bytes[Self.size - 4] = UInt8(truncatingIfNeeded: crc)
        bytes[Self.size - 3] = UInt8(truncatingIfNeeded: crc >> 8)
        bytes[Self.size - 2] = UInt8(truncatingIfNeeded: crc >> 16)
        bytes[Self.size - 1] = UInt8(truncatingIfNeeded: crc >> 24)
        self.bytes = bytes
    }

    private static func crc32(seedByte: UInt8, report: ArraySlice<UInt8>) -> UInt32 {
        var crc = updateCRC32(0xFFFFFFFF, byte: seedByte)
        for byte in report {
            crc = updateCRC32(crc, byte: byte)
        }
        return ~crc
    }

    private static func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
        var crc = current ^ UInt32(byte)
        for _ in 0 ..< 8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}
