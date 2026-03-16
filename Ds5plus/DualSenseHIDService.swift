import Foundation
import IOKit.hid
import QuartzCore

final class DualSenseHIDService {
    private static let sonyVendorID = 0x054C
    private static let dualSenseProductIDs: Set<Int> = [0x0CE6, 0x0DF2]
    private static let firmwareInfoReportID: CFIndex = 0x20
    private static let firmwareInfoReportSize = 64
    private static let featureVersionVibrationV2 = UInt16(0x0215) // 2.21

    private let manager: IOHIDManager
    private var knownDevices: [String: IOHIDDevice] = [:]
    private var deviceInfos: [String: DualSenseDeviceInfo] = [:]
    private var deviceStates: [String: DeviceState] = [:]
    private var timer: DispatchSourceTimer?
    private var pulseStopWorkItem: DispatchWorkItem?
    private var currentDeviceID: String?
    private var currentConfiguration = HapticConfiguration()
    private var sequenceNumber: UInt8 = 0
    private var stats = DriverStats()

    var onDevicesChanged: @Sendable ([DualSenseDeviceInfo]) -> Void = { _ in }
    var onLog: @Sendable (String) -> Void = { _ in }
    var onStatsChanged: @Sendable (DriverStats) -> Void = { _ in }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))

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
        for device in knownDevices.values {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
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

        knownDevices = refreshed
        deviceInfos = infos
        publishDevices()
    }

    func startEffect(deviceID: String, configuration: HapticConfiguration) {
        guard let device = knownDevices[deviceID] else {
            log("未找到目标 DualSense 设备。")
            return
        }

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess || openStatus == kIOReturnExclusiveAccess else {
            log("打开 DualSense 失败: \(openStatus)")
            return
        }

        if deviceStates[deviceID] == nil {
            deviceStates[deviceID] = probeState(for: device, productID: deviceInfos[deviceID]?.productID)
        }

        currentDeviceID = deviceID
        currentConfiguration = configuration
        pulseStopWorkItem?.cancel()
        pulseStopWorkItem = nil
        startTimerIfNeeded()
        log("已开始无线 HID 直驱: \(deviceInfos[deviceID]?.displayName ?? deviceID)")
    }

    func updateEffect(configuration: HapticConfiguration) {
        currentConfiguration = configuration
    }

    func stopEffect() {
        timer?.cancel()
        timer = nil
        pulseStopWorkItem?.cancel()
        pulseStopWorkItem = nil

        if let currentDeviceID, let device = knownDevices[currentDeviceID] {
            _ = sendReport(to: device, deviceID: currentDeviceID, leftMotor: 0, rightMotor: 0, lightbar: (0, 0, 0))
        }
        currentDeviceID = nil
        log("已发送停止报告。")
    }

    func pulse(deviceID: String, configuration: HapticConfiguration, duration: TimeInterval = 0.35) {
        stopEffect()
        guard let device = knownDevices[deviceID] else {
            log("未找到目标 DualSense 设备。")
            return
        }
        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess || openStatus == kIOReturnExclusiveAccess else {
            log("打开 DualSense 失败: \(openStatus)")
            return
        }

        if deviceStates[deviceID] == nil {
            deviceStates[deviceID] = probeState(for: device, productID: deviceInfos[deviceID]?.productID)
        }

        currentDeviceID = deviceID
        currentConfiguration = configuration
        _ = sendReport(to: device, deviceID: deviceID, leftMotor: configuration.leftMotor, rightMotor: configuration.rightMotor, lightbar: (0, 64, 255))

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let currentDeviceID = self.currentDeviceID, let activeDevice = self.knownDevices[currentDeviceID] else { return }
            _ = self.sendReport(to: activeDevice, deviceID: currentDeviceID, leftMotor: 0, rightMotor: 0, lightbar: (0, 0, 0))
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

        _ = sendReport(to: device, deviceID: currentDeviceID, leftMotor: leftMotor, rightMotor: rightMotor, lightbar: (0, 64, 255))
    }

    @discardableResult
    private func sendReport(to device: IOHIDDevice, deviceID: String, leftMotor: UInt8, rightMotor: UInt8, lightbar: (UInt8, UInt8, UInt8)) -> IOReturn {
        let state = deviceStates[deviceID] ?? DeviceState(useVibrationV2: true, updateVersion: nil, firmwareVersion: nil, hardwareVersion: nil)
        sequenceNumber = (sequenceNumber + 1) & 0x0F

        let report = DualSenseBluetoothOutputReport(
            sequence: sequenceNumber,
            leftMotor: leftMotor,
            rightMotor: rightMotor,
            useVibrationV2: state.useVibrationV2,
            lightbar: lightbar
        ).bytes

        let result = report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), baseAddress, report.count)
        }

        stats.sentReports += 1
        stats.lastSequence = Int(sequenceNumber)
        stats.lastLeftMotor = Int(leftMotor)
        stats.lastRightMotor = Int(rightMotor)
        stats.lastResult = result == kIOReturnSuccess ? "ok" : "\(result)"
        onStatsChanged(stats)

        if result != kIOReturnSuccess {
            log("发送 HID 输出报告失败: \(result)")
        }
        return result
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

    private func log(_ line: String) {
        onLog(line)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
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
        service.knownDevices.removeValue(forKey: info.id)
        service.deviceInfos.removeValue(forKey: info.id)
        service.deviceStates.removeValue(forKey: info.id)
        if service.currentDeviceID == info.id {
            service.stopEffect()
        }
        service.publishDevices()
        service.log("DualSense 已断开: \(info.displayName)")
    }
}

private struct DeviceState {
    let useVibrationV2: Bool
    let updateVersion: UInt16?
    let firmwareVersion: UInt32?
    let hardwareVersion: UInt32?
}

private struct DualSenseBluetoothOutputReport {
    static let reportID: UInt8 = 0x31
    static let tag: UInt8 = 0x10
    static let outputCRCSeedByte: UInt8 = 0xA2
    static let size = 78

    static let validFlag0CompatibleVibration: UInt8 = 1 << 0
    static let validFlag0HapticsSelect: UInt8 = 1 << 1

    static let validFlag1LightbarControlEnable: UInt8 = 1 << 2
    static let validFlag1PlayerIndicatorControlEnable: UInt8 = 1 << 4
    static let validFlag1HapticLowPassFilterControlEnable: UInt8 = 1 << 5
    static let validFlag1VibrationAttenuationEnable: UInt8 = 1 << 6

    static let validFlag2LightbarSetupControlEnable: UInt8 = 1 << 1
    static let validFlag2CompatibleVibration2: UInt8 = 1 << 2

    static let hapticsFlagLowPassFilter: UInt8 = 1 << 0

    static let playerLEDInner: UInt8 = 0b00100
    static let lightbarSetupLightOn: UInt8 = 1 << 0

    let bytes: [UInt8]

    init(sequence: UInt8, leftMotor: UInt8, rightMotor: UInt8, useVibrationV2: Bool, lightbar: (UInt8, UInt8, UInt8)) {
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
        bytes[44] = Self.lightbarSetupLightOn
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
