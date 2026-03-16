import SwiftUI
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var devices: [DualSenseDeviceInfo] = []
    @Published var selectedDeviceID: String?
    @Published var mode: HapticMode = .constant
    @Published var leftMotor: Double = 180
    @Published var rightMotor: Double = 90
    @Published var pulseFrequency: Double = 6
    @Published var isRunning = false
    @Published var statusLine = "等待蓝牙 DualSense"
    @Published var stats = DriverStats()
    @Published var logs: [String] = []

    private let hidService = DualSenseHIDService()

    init() {
        hidService.onDevicesChanged = { [weak self] devices in
            DispatchQueue.main.async {
                guard let self else { return }
                self.devices = devices
                if let selectedDeviceID = self.selectedDeviceID,
                   devices.contains(where: { $0.id == selectedDeviceID }) {
                    return
                }
                self.selectedDeviceID = devices.first?.id
                self.statusLine = devices.isEmpty ? "未发现蓝牙 DualSense" : "已发现 \(devices.count) 个蓝牙 DualSense"
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
    }

    var canStart: Bool {
        selectedDeviceID != nil
    }

    var selectedDevice: DualSenseDeviceInfo? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    func refreshDevices() {
        hidService.refreshDevicesSnapshot()
        appendLog("已手动刷新蓝牙 DualSense 列表。")
    }

    func startEffect() {
        guard let selectedDeviceID else {
            appendLog("请先连接并选择一个蓝牙 DualSense。")
            return
        }
        hidService.startEffect(deviceID: selectedDeviceID, configuration: currentConfiguration)
        statusLine = "无线 HID 直驱运行中"
        isRunning = true
    }

    func stopEffect() {
        hidService.stopEffect()
        statusLine = "已停止"
        isRunning = false
    }

    func pulseOnce() {
        guard let selectedDeviceID else {
            appendLog("请先连接并选择一个蓝牙 DualSense。")
            return
        }
        hidService.pulse(deviceID: selectedDeviceID, configuration: currentConfiguration)
        statusLine = "已发送单次测试脉冲"
        isRunning = false
    }

    func liveUpdateIfNeeded() {
        guard isRunning else { return }
        hidService.updateEffect(configuration: currentConfiguration)
    }

    private var currentConfiguration: HapticConfiguration {
        HapticConfiguration(
            mode: mode,
            leftMotor: UInt8(clamping: Int(leftMotor.rounded())),
            rightMotor: UInt8(clamping: Int(rightMotor.rounded())),
            pulseFrequency: pulseFrequency
        )
    }

    private func appendLog(_ line: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(timestamp)] \(line)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }
}
