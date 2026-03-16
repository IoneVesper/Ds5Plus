import Foundation

struct DualSenseDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let serialNumber: String?
    let transport: String
    let productID: Int

    var displayName: String {
        if let serialNumber, !serialNumber.isEmpty {
            return "\(name) · \(transport) · \(serialNumber)"
        }
        return "\(name) · \(transport)"
    }
}

enum HapticMode: String, CaseIterable, Identifiable {
    case constant
    case pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .constant: return "持续"
        case .pulse: return "脉冲"
        }
    }

    var detail: String {
        switch self {
        case .constant:
            return "持续发送兼容振动输出报告，适合验证蓝牙下能否稳定直驱 DS5。"
        case .pulse:
            return "按照频率周期性开关振动，更容易观察无线 HID 直驱是否生效。"
        }
    }
}

struct HapticConfiguration: Sendable {
    var mode: HapticMode = .constant
    var leftMotor: UInt8 = 160
    var rightMotor: UInt8 = 80
    var pulseFrequency: Double = 6
}

struct DriverStats: Sendable {
    var sentReports: Int = 0
    var lastSequence: Int = 0
    var lastLeftMotor: Int = 0
    var lastRightMotor: Int = 0
    var lastResult: String = "idle"
}
