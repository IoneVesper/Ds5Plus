import SwiftUI
import Combine
import AppKit
import QuartzCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var devices: [DualSenseDeviceInfo] = []
    @Published var selectedDeviceID: String? {
        didSet {
            guard selectedDeviceID != oldValue else { return }
            batteryStatus = ControllerBatteryStatus()
            if let selectedDeviceID {
                hidService.refreshBatteryStatus(deviceID: selectedDeviceID)
            }
        }
    }
    @Published var displays: [CaptureDisplay] = []
    @Published var selectedDisplayID: CGDirectDisplayID?

    @Published var audioPreset: AudioReactivePreset = .balanced
    @Published var customAudioPresets: [UserAudioPreset] = []
    @Published var selectedCustomPresetID: UUID?
    @Published var audioDrive: Double = 2.2
    @Published var audioFloor: Double = 0.015
    @Published var audioCeiling: Double = 0.14
    @Published var audioSuppressMusic = true
    @Published var audioSample = AudioReactiveSample()
    @Published var lightbarColorPreset: LightbarColorPreset = .blue
    @Published var isCustomLightbarColorSelected = false
    @Published var customLightbarHue: Double = 0.61
    @Published var customLightbarSaturation: Double = 0.75
    @Published var customLightbarBrightness: Double = 0.98
    @Published var logFileSizeOption: LogFileSizeOption = .mb50
    @Published var batteryStatus = ControllerBatteryStatus()

    @Published var isRunning = false
    @Published var statusLine = "等待蓝牙 DualSense"
    @Published var stats = DriverStats()
    @Published private(set) var logFileURL = AppViewModel.prepareLogFile()
    @Published private(set) var logFileSizeBytes: Int64 = 0

    private let hidService = DualSenseHIDService()
    private let audioEngine = SystemAudioHapticsEngine()
    private let userDefaults = UserDefaults.standard

    private var previousMovementSignal: Float = 0
    private var previousImpactSignal: Float = 0
    private var suppressionMemory: Float = 0
    private var sustainLeftState: Float = 0
    private var sustainRightState: Float = 0
    private var tickEnvelope: Float = 0
    private var pulseEnvelope: Float = 0
    private var burstEnvelope: Float = 0
    private var lastTickTriggerTime: CFTimeInterval = 0
    private var lastPulseTriggerTime: CFTimeInterval = 0
    private var lastBurstTriggerTime: CFTimeInterval = 0

    private enum DefaultsKeys {
        static let customAudioPresets = "Ds5plus.customAudioPresets"
        static let lightbarColor = "Ds5plus.lightbarColor"
        static let customLightbarSelected = "Ds5plus.customLightbarSelected"
        static let customLightbarHue = "Ds5plus.customLightbarHue"
        static let customLightbarSaturation = "Ds5plus.customLightbarSaturation"
        static let customLightbarBrightness = "Ds5plus.customLightbarBrightness"
        static let logFileSizeMB = "Ds5plus.logFileSizeMB"
    }

    init() {
        loadPersistedSettings()

        hidService.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async {
                guard let self else { return }
                let previousSelectedDeviceID = self.selectedDeviceID
                self.devices = devices

                if let selectedDeviceID = self.selectedDeviceID,
                   devices.contains(where: { $0.id == selectedDeviceID }) {
                    return
                }

                self.selectedDeviceID = devices.first?.id
                self.batteryStatus = ControllerBatteryStatus()
                self.statusLine = devices.isEmpty ? "未发现蓝牙 DualSense" : "已连接蓝牙 DualSense"

                if self.isRunning,
                   let previousSelectedDeviceID,
                   !devices.contains(where: { $0.id == previousSelectedDeviceID }) {
                    self.audioEngine.stop()
                    self.hidService.stopEffect()
                    self.resetHapticMixer()
                    self.isRunning = false
                    self.statusLine = "DualSense 已断开"
                    self.appendLog("当前运行中的 DualSense 已断开，已自动停止输出。")
                }
            }
        }

        hidService.onLog = { [weak self] line in
            DispatchQueue.main.async {
                self?.appendLog(line)
            }
        }

        hidService.onStatsChanged = { [weak self] stats in
            DispatchQueue.main.async {
                self?.stats = stats
            }
        }

        hidService.onBatteryChanged = { [weak self] deviceID, status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.selectedDeviceID == deviceID else { return }
                guard self.batteryStatus != status else { return }
                self.batteryStatus = status
            }
        }

        audioEngine.onLog = { [weak self] line in
            DispatchQueue.main.async {
                self?.appendLog(line)
            }
        }

        audioEngine.onSample = { [weak self] sample in
            DispatchQueue.main.async {
                guard let self else { return }
                self.audioSample = sample
                guard self.isRunning else { return }
                let motors = self.mapAudioSampleToMotors(sample)
                let color = self.mapAudioSampleToLightbar(sample)
                self.hidService.sendRealtimeHaptics(leftMotor: motors.left, rightMotor: motors.right, lightbar: color)
            }
        }

        audioEngine.onCaptureStateChanged = { [weak self] isCapturing, reason in
            DispatchQueue.main.async {
                guard let self else { return }
                guard !isCapturing, self.isRunning else { return }
                self.hidService.stopEffect()
                self.resetHapticMixer()
                self.isRunning = false
                self.statusLine = "音频驱动已停止"
                if let reason, !reason.isEmpty {
                    self.appendLog("系统音频捕获已停止：\(reason)")
                }
            }
        }

        applyAudioPreset(audioPreset, shouldLog: false)
        refreshLogFileMetadata()
        trimLogFileIfNeeded()
        appendLog("应用已启动。")
        Task {
            await refreshAll(silent: true)
        }
    }

    var selectedDevice: DualSenseDeviceInfo? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var canToggleRun: Bool {
        selectedDeviceID != nil && selectedDisplayID != nil
    }

    var selectedCustomPreset: UserAudioPreset? {
        guard let selectedCustomPresetID else { return nil }
        return customAudioPresets.first(where: { $0.id == selectedCustomPresetID })
    }

    var currentPresetTitle: String {
        selectedCustomPreset?.name ?? audioPreset.title
    }

    var captureEnabled: Bool {
        selectedDisplayID != nil
    }

    var captureStatusText: String {
        captureEnabled ? "On" : "Off"
    }

    var runStatusText: String {
        if isRunning {
            return stats.lastResult == "ok" ? "正常".localized : "异常".localized
        }
        return "未启动".localized
    }

    var runStatusTint: Color {
        if isRunning {
            return stats.lastResult == "ok" ? Color(red: 0.20, green: 0.72, blue: 0.44) : Color(red: 0.89, green: 0.31, blue: 0.27)
        }
        return Color(red: 0.56, green: 0.60, blue: 0.70)
    }

    var connectionStatusText: String {
        devices.isEmpty ? "未连接".localized : "已连接".localized
    }

    var connectionStatusTint: Color {
        devices.isEmpty ? Color(red: 0.66, green: 0.70, blue: 0.78) : Color(red: 0.27, green: 0.67, blue: 0.97)
    }

    var runButtonSymbolName: String {
        isRunning ? "stop.fill" : "play.fill"
    }

    var runButtonTint: Color {
        isRunning ? Color(red: 0.89, green: 0.32, blue: 0.27) : Color(red: 0.24, green: 0.50, blue: 0.96)
    }

    var logDirectoryURL: URL {
        logFileURL.deletingLastPathComponent()
    }

    var currentLogFileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: logFileSizeBytes)
    }

    var lightbarSelectionSummary: String {
        String(format: "灯条偏色：%@".localized, isCustomLightbarColorSelected ? "自定义".localized : lightbarColorPreset.title)
    }

    var lightbarDisplayTitle: String {
        isCustomLightbarColorSelected ? "自定义".localized : lightbarColorPreset.title
    }

    var lightbarPreviewColor: Color {
        let accent = currentLightbarAccentRGB()
        return Color(red: accent.0, green: accent.1, blue: accent.2)
    }

    var batteryPercentageText: String {
        if let percentage = batteryStatus.percentage {
            return "\(percentage)%"
        }
        return "--"
    }

    var batteryStateText: String {
        switch batteryStatus.chargingState {
        case .discharging:
            return "放电中".localized
        case .charging:
            return "充电中".localized
        case .full:
            return "已充满".localized
        case .notCharging:
            return "未充电".localized
        case .unknown:
            return "状态未知".localized
        }
    }

    var batteryTint: Color {
        if let percentage = batteryStatus.percentage, percentage <= 20 {
            return Color(red: 0.90, green: 0.28, blue: 0.26)
        }

        switch batteryStatus.chargingState {
        case .charging, .full:
            return Color(red: 0.21, green: 0.70, blue: 0.39)
        case .discharging:
            return Color(red: 0.91, green: 0.67, blue: 0.16)
        case .notCharging, .unknown:
            return Color(red: 0.30, green: 0.35, blue: 0.45)
        }
    }

    func refreshAll(silent: Bool = false) async {
        hidService.refreshDevicesSnapshot()
        if !silent {
            appendLog("已刷新蓝牙设备。")
        }
        await refreshDisplays(silent: silent)
    }

    func refreshDisplays(silent: Bool = false) async {
        do {
            let displays = try await audioEngine.refreshDisplays()
            self.displays = displays

            if let selectedDisplayID,
               displays.contains(where: { $0.id == selectedDisplayID }) {
                if !silent {
                    appendLog("已刷新系统音频捕获源。")
                }
                return
            }

            self.selectedDisplayID = displays.first?.id
            if !silent {
                appendLog(displays.isEmpty ? "当前没有可用的系统音频捕获源。" : "已刷新系统音频捕获源。")
            }
        } catch {
            appendLog("读取系统音频捕获显示器失败：\(error.localizedDescription)")
        }
    }

    func toggleRunState() {
        if isRunning {
            stopEffect()
        } else {
            startAudioReactive()
        }
    }

    func startAudioReactive() {
        guard let selectedDeviceID else {
            appendLog("请先连接一个蓝牙 DualSense。")
            statusLine = "未发现手柄"
            return
        }
        guard let selectedDisplayID else {
            appendLog("当前没有可用的系统音频捕获源。")
            statusLine = "捕获源不可用"
            return
        }

        resetHapticMixer()
        guard hidService.startRealtimeControl(deviceID: selectedDeviceID) else {
            statusLine = "启动失败"
            isRunning = false
            return
        }

        Task {
            do {
                try await audioEngine.start(displayID: selectedDisplayID)
                await MainActor.run {
                    self.isRunning = true
                    self.statusLine = "音频驱动运行中"
                    self.appendLog("音频驱动已开始。")
                }
            } catch {
                await MainActor.run {
                    self.audioEngine.stop()
                    self.hidService.stopEffect()
                    self.resetHapticMixer()
                    self.isRunning = false
                    self.statusLine = "启动失败"
                    self.appendLog("启动音频驱动模式失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func stopEffect() {
        audioEngine.stop()
        hidService.stopEffect()
        resetHapticMixer()
        statusLine = "音频驱动已停止"
        isRunning = false
        appendLog("音频驱动已停止。")
    }

    func applyAudioPreset(_ preset: AudioReactivePreset, shouldLog: Bool = true) {
        selectedCustomPresetID = nil
        audioPreset = preset
        let tuning = preset.tuning
        audioDrive = tuning.drive
        audioFloor = tuning.floor
        audioCeiling = tuning.ceiling
        resetHapticMixer()
        if shouldLog {
            appendLog("已切换音频预设：\(preset.title)")
        }
    }

    func applyCustomAudioPreset(_ preset: UserAudioPreset, shouldLog: Bool = true) {
        selectedCustomPresetID = preset.id
        audioPreset = preset.basePreset
        audioDrive = preset.drive
        audioFloor = preset.floor
        audioCeiling = preset.ceiling
        audioSuppressMusic = preset.suppressMusic
        resetHapticMixer()
        if shouldLog {
            appendLog("已切换自定义预设：\(preset.name)")
        }
    }

    func restoreCurrentPresetDefaults() {
        if let customPreset = selectedCustomPreset {
            audioPreset = customPreset.basePreset
            audioDrive = customPreset.drive
            audioFloor = customPreset.floor
            audioCeiling = customPreset.ceiling
            audioSuppressMusic = customPreset.suppressMusic
            appendLog("已恢复 \(customPreset.name) 默认参数")
        } else {
            let tuning = audioPreset.tuning
            audioDrive = tuning.drive
            audioFloor = tuning.floor
            audioCeiling = tuning.ceiling
            appendLog("已恢复 \(audioPreset.title) 默认参数")
        }
        resetHapticMixer()
    }

    func saveCustomAudioPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = uniqueCustomPresetName(from: trimmed.isEmpty ? "自定义预设" : trimmed)
        let preset = UserAudioPreset(
            name: resolvedName,
            basePresetRawValue: audioPreset.rawValue,
            drive: audioDrive,
            floor: audioFloor,
            ceiling: audioCeiling,
            suppressMusic: audioSuppressMusic
        )

        customAudioPresets.append(preset)
        persistCustomAudioPresets()
        applyCustomAudioPreset(preset, shouldLog: false)
        appendLog("已保存自定义预设：\(resolvedName)")
    }

    func selectLightbarColor(_ preset: LightbarColorPreset) {
        lightbarColorPreset = preset
        isCustomLightbarColorSelected = false
        userDefaults.set(preset.rawValue, forKey: DefaultsKeys.lightbarColor)
        userDefaults.set(false, forKey: DefaultsKeys.customLightbarSelected)
        if let selectedDeviceID {
            hidService.previewLightbar(deviceID: selectedDeviceID, color: currentLightbarPreviewColor())
        }
    }

    func updateCustomLightbar(hue: Double? = nil, saturation: Double? = nil, brightness: Double? = nil, preview: Bool = true) {
        if let hue {
            customLightbarHue = min(max(hue, 0), 1)
        }
        if let saturation {
            customLightbarSaturation = min(max(saturation, 0), 1)
        }
        if let brightness {
            customLightbarBrightness = min(max(brightness, 0), 1)
        }

        isCustomLightbarColorSelected = true
        persistCustomLightbarSettings()

        if preview, let selectedDeviceID {
            hidService.previewLightbar(deviceID: selectedDeviceID, color: currentLightbarPreviewColor())
        }
    }

    func updateLogFileSizeOption(_ option: LogFileSizeOption) {
        guard logFileSizeOption != option else { return }
        logFileSizeOption = option
        userDefaults.set(option.rawValue, forKey: DefaultsKeys.logFileSizeMB)
        trimLogFileIfNeeded()
        appendLog("已将日志最大大小设置为 \(option.title)")
    }

    func refreshLogFileMetadata() {
        let values = try? logFileURL.resourceValues(forKeys: [.fileSizeKey])
        logFileSizeBytes = Int64(values?.fileSize ?? 0)
    }

    func revealLogsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(logDirectoryURL)
    }

    func copyLogPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logFileURL.path, forType: .string)
    }

    func clearLogs() {
        try? Data().write(to: logFileURL, options: .atomic)
        refreshLogFileMetadata()
    }

    private func loadPersistedSettings() {
        if let data = userDefaults.data(forKey: DefaultsKeys.customAudioPresets),
           let presets = try? JSONDecoder().decode([UserAudioPreset].self, from: data) {
            customAudioPresets = presets
        }

        if let rawLightbarColor = userDefaults.string(forKey: DefaultsKeys.lightbarColor),
           let preset = LightbarColorPreset(rawValue: rawLightbarColor) {
            lightbarColorPreset = preset
        }

        if userDefaults.object(forKey: DefaultsKeys.customLightbarHue) != nil {
            customLightbarHue = min(max(userDefaults.double(forKey: DefaultsKeys.customLightbarHue), 0), 1)
        }
        if userDefaults.object(forKey: DefaultsKeys.customLightbarSaturation) != nil {
            customLightbarSaturation = min(max(userDefaults.double(forKey: DefaultsKeys.customLightbarSaturation), 0), 1)
        }
        if userDefaults.object(forKey: DefaultsKeys.customLightbarBrightness) != nil {
            customLightbarBrightness = min(max(userDefaults.double(forKey: DefaultsKeys.customLightbarBrightness), 0), 1)
        }
        if userDefaults.object(forKey: DefaultsKeys.customLightbarSelected) != nil {
            isCustomLightbarColorSelected = userDefaults.bool(forKey: DefaultsKeys.customLightbarSelected)
        }

        if let storedValue = userDefaults.object(forKey: DefaultsKeys.logFileSizeMB) as? Int,
           let option = LogFileSizeOption(rawValue: storedValue) {
            logFileSizeOption = option
        } else {
            logFileSizeOption = .mb50
        }
    }

    private func mapAudioSampleToMotors(_ sample: AudioReactiveSample) -> (left: UInt8, right: UInt8) {
        let floor = Float(audioFloor)
        let ceiling = max(Float(audioCeiling), floor + 0.001)
        let gain = Float(audioDrive)
        let profile = audioPreset.profile
        let detection = audioPreset.detectionProfile
        let now = CACurrentMediaTime()

        func normalize(_ value: Float) -> Float {
            min(max((value - floor) / (ceiling - floor), 0), 1)
        }

        func shape(_ value: Float) -> Float {
            let clamped = min(max(value * gain, 0), 1)
            return pow(clamped, profile.responseCurve)
        }

        let low = normalize(sample.lowFrequency)
        let mid = normalize(sample.midFrequency)
        let body = normalize(sample.rms)
        let transient = normalize(sample.transient)
        let attack = normalize(sample.attack)
        let effect = normalize(sample.effect)
        let movementPulse = normalize(sample.movementPulse)
        let music = normalize(sample.music)
        let background = normalize(sample.background)

        let foreground = max(effect * 1.12, max(transient * 1.02, max(attack * 1.18, movementPulse * 0.86)))
        let rawMusicDominance =
            (music * detection.musicSuppressionStrength) +
            (background * detection.sustainSuppressionStrength) +
            (low * detection.lowBandMusicPenalty) +
            (mid * detection.midBandMusicPenalty)

        let rawSuppression = audioSuppressMusic ? min(max(rawMusicDominance - (foreground * 0.56), 0), 1) : 0
        suppressionMemory = max(rawSuppression, suppressionMemory * detection.musicDecay)
        let suppression = audioSuppressMusic ? suppressionMemory : 0

        let lowForeground = max(low - (suppression * detection.lowBandMusicPenalty * 0.32), 0)
        let bodyForeground = max(body - (suppression * detection.midBandMusicPenalty * 0.18), 0)
        let midForeground = max(mid - (suppression * detection.midBandMusicPenalty * 0.26), 0)

        let impactPresence = max(effect, max(transient, max(attack * 1.08, movementPulse * 0.88)))
        let movementBias = min(max((impactPresence * 1.28) + (movementPulse * 0.76) + (bodyForeground * 0.06), 0.10), 0.84)
        let controlledLow = lowForeground * movementBias
        let sustainGate = max(effect, max(transient, max(attack * 1.04, max(movementPulse * 1.02, controlledLow * 0.24))))

        let eventSuppression = min(max(1 - (suppression * 0.24), 0.44), 1)
        let sustainSuppression = min(
            max(
                (1 - (suppression * detection.sustainSuppressionStrength)) + (movementPulse * detection.movementRecoveryGain),
                0
            ),
            1
        )

        let leftContinuous =
            (controlledLow * (profile.leftLow * 0.30 + 0.02)) +
            (bodyForeground * (profile.leftBody * 0.06)) +
            (midForeground * 0.04) +
            (transient * (profile.leftTransient * 0.18 + 0.02)) +
            (attack * 0.06) +
            (movementPulse * 0.18) +
            (effect * 0.20)

        let rightContinuous =
            (controlledLow * (profile.rightLow * 0.08)) +
            (bodyForeground * (profile.rightBody * 0.05)) +
            (midForeground * 0.02) +
            (transient * (profile.rightTransient * 0.22 + 0.04)) +
            (attack * 0.24) +
            (movementPulse * 0.08) +
            (effect * 0.22)

        let sustainLeftTarget = min(
            shape(leftContinuous) * (0.14 + profile.leftLow * 0.08) * detection.sustainLeftBias,
            detection.sustainLeftCap
        ) * sustainSuppression

        let sustainRightTarget = min(
            shape(rightContinuous) * (0.10 + profile.rightTransient * 0.06) * detection.sustainRightBias,
            detection.sustainRightCap
        ) * sustainSuppression

        sustainLeftState = max(sustainLeftTarget, sustainLeftState * 0.64)
        sustainRightState = max(sustainRightTarget, sustainRightState * 0.60)

        tickEnvelope *= 0.54
        pulseEnvelope *= 0.76
        burstEnvelope *= 0.86

        let movementSignal = max(movementPulse * 1.06, controlledLow * 0.36)
        let impactSignal = max(effect * 1.08, max(transient * 1.02, attack * 1.20))
        let movementOnset = max(movementSignal - (previousMovementSignal * 0.82), 0)
        let impactOnset = max(impactSignal - (previousImpactSignal * 0.72), 0)
        previousMovementSignal = movementSignal
        previousImpactSignal = impactSignal

        if sustainGate > detection.backgroundGate,
           movementSignal > detection.movementTriggerThreshold,
           movementOnset > (detection.movementTriggerThreshold * 0.42),
           now - lastTickTriggerTime >= detection.movementCooldown {
            let tickStrength = min(
                0.10 + (movementOnset * 1.05) + (movementSignal * 0.18),
                detection.tickStrengthCap
            ) * eventSuppression
            tickEnvelope = max(tickEnvelope, tickStrength)
            lastTickTriggerTime = now
        }

        if impactSignal > detection.impactTriggerThreshold,
           impactOnset > (detection.impactTriggerThreshold * 0.45),
           now - lastPulseTriggerTime >= max(detection.movementCooldown * 1.1, 0.10) {
            let pulseStrength = min(
                0.18 + (impactOnset * 1.12) + (attack * 0.08),
                detection.pulseStrengthCap
            ) * eventSuppression
            pulseEnvelope = max(pulseEnvelope, pulseStrength)
            lastPulseTriggerTime = now
        }

        if impactSignal > detection.burstTriggerThreshold,
           impactOnset > (detection.burstTriggerThreshold * 0.36),
           now - lastBurstTriggerTime >= max(detection.movementCooldown * 1.5, 0.14) {
            let burstStrength = min(
                0.24 + (impactSignal * 0.48) + (impactOnset * 1.28),
                detection.burstStrengthCap
            ) * eventSuppression
            burstEnvelope = max(burstEnvelope, burstStrength)
            lastBurstTriggerTime = now
        }

        let leftValue = min(
            sustainLeftState +
            (tickEnvelope * (detection.tickLeftMix + profile.leftLow * 0.05 + profile.leftTransient * 0.02)) +
            (pulseEnvelope * (detection.pulseLeftMix + profile.leftTransient * 0.03)) +
            (burstEnvelope * (detection.burstLeftMix + profile.leftTransient * 0.05)),
            1
        )

        let rightValue = min(
            sustainRightState +
            (tickEnvelope * (detection.tickRightMix + profile.rightTransient * 0.02)) +
            (pulseEnvelope * (detection.pulseRightMix + profile.rightTransient * 0.05 + profile.rightBody * 0.02)) +
            (burstEnvelope * (detection.burstRightMix + profile.rightTransient * 0.08 + profile.rightBody * 0.03)),
            1
        )

        if sustainGate < detection.backgroundGate, tickEnvelope < 0.015, pulseEnvelope < 0.015, burstEnvelope < 0.015 {
            sustainLeftState *= 0.80
            sustainRightState *= 0.76
        }

        let leftMotor = UInt8(clamping: Int((leftValue * 255).rounded()))
        let rightMotor = UInt8(clamping: Int((rightValue * 255).rounded()))

        if leftMotor < 8 && rightMotor < 8 {
            return (0, 0)
        }
        return (leftMotor, rightMotor)
    }

    private func resetHapticMixer() {
        previousMovementSignal = 0
        previousImpactSignal = 0
        suppressionMemory = 0
        sustainLeftState = 0
        sustainRightState = 0
        tickEnvelope = 0
        pulseEnvelope = 0
        burstEnvelope = 0
        lastTickTriggerTime = 0
        lastPulseTriggerTime = 0
        lastBurstTriggerTime = 0
    }

    private func mapAudioSampleToLightbar(_ sample: AudioReactiveSample) -> (UInt8, UInt8, UInt8) {
        let accent = currentLightbarAccentRGB()
        let activitySource = max(sample.effect * 1.18, max(sample.transient * 1.22, sample.attack * 1.34))
        let activity = min(max(activitySource * Float(audioDrive) * 1.8, 0), 1)
        let brightness = 0.34 + (Double(activity) * 0.66)
        let red = min(max(accent.0 * brightness, 0), 1)
        let green = min(max(accent.1 * brightness, 0), 1)
        let blue = min(max(accent.2 * brightness, 0), 1)
        return (
            UInt8(clamping: Int((red * 255).rounded())),
            UInt8(clamping: Int((green * 255).rounded())),
            UInt8(clamping: Int((blue * 255).rounded()))
        )
    }

    private func currentLightbarPreviewColor() -> (UInt8, UInt8, UInt8) {
        let accent = currentLightbarAccentRGB()
        return (
            UInt8(clamping: Int((accent.0 * 255).rounded())),
            UInt8(clamping: Int((accent.1 * 255).rounded())),
            UInt8(clamping: Int((accent.2 * 255).rounded()))
        )
    }

    private func currentLightbarAccentRGB() -> (Double, Double, Double) {
        if isCustomLightbarColorSelected {
            let color = NSColor(
                calibratedHue: CGFloat(customLightbarHue),
                saturation: CGFloat(customLightbarSaturation),
                brightness: CGFloat(customLightbarBrightness),
                alpha: 1
            ).usingColorSpace(.deviceRGB) ?? .systemBlue

            return (
                Double(color.redComponent),
                Double(color.greenComponent),
                Double(color.blueComponent)
            )
        }

        return lightbarColorPreset.rgb
    }

    private func persistCustomLightbarSettings() {
        userDefaults.set(isCustomLightbarColorSelected, forKey: DefaultsKeys.customLightbarSelected)
        userDefaults.set(customLightbarHue, forKey: DefaultsKeys.customLightbarHue)
        userDefaults.set(customLightbarSaturation, forKey: DefaultsKeys.customLightbarSaturation)
        userDefaults.set(customLightbarBrightness, forKey: DefaultsKeys.customLightbarBrightness)
    }

    private func persistCustomAudioPresets() {
        guard let data = try? JSONEncoder().encode(customAudioPresets) else { return }
        userDefaults.set(data, forKey: DefaultsKeys.customAudioPresets)
    }

    private func uniqueCustomPresetName(from baseName: String) -> String {
        let existingNames = Set(customAudioPresets.map(\.name))
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func appendLog(_ line: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let entry = "[\(timestamp)] \(line)\n"

        guard let data = entry.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
                logFileSizeBytes += Int64(data.count)
            } catch {
                try? handle.close()
                refreshLogFileMetadata()
            }
        } else {
            try? data.write(to: logFileURL, options: .atomic)
            refreshLogFileMetadata()
        }

        trimLogFileIfNeeded()
    }

    private func trimLogFileIfNeeded() {
        let limit = logFileSizeOption.bytes
        guard logFileSizeBytes > Int64(limit) else { return }
        guard let data = try? Data(contentsOf: logFileURL) else {
            refreshLogFileMetadata()
            return
        }
        guard data.count > limit else {
            logFileSizeBytes = Int64(data.count)
            return
        }
        let retainCount = Int(Double(limit) * 0.40)
        let trimmed = data.suffix(max(retainCount, min(limit, 512 * 1024)))
        try? Data(trimmed).write(to: logFileURL, options: .atomic)
        logFileSizeBytes = Int64(trimmed.count)
    }

    private static func prepareLogFile() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = baseDirectory.appendingPathComponent("Ds5plus/Logs", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("runtime.log")
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: Data())
        }
        return fileURL
    }
}
