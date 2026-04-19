import Foundation
import CoreGraphics

nonisolated struct DualSenseDeviceInfo: Identifiable, Hashable, Sendable {
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

nonisolated struct CaptureDisplay: Identifiable, Hashable, Sendable {
    let id: CGDirectDisplayID
    let width: Int
    let height: Int

    var displayName: String {
        "Display \(id) · \(width)x\(height)"
    }
}

nonisolated enum BatteryChargingState: Sendable, Equatable {
    case discharging
    case charging
    case full
    case notCharging
    case unknown
}

nonisolated struct ControllerBatteryStatus: Sendable, Equatable {
    var percentage: Int?
    var chargingState: BatteryChargingState = .unknown
}

nonisolated enum ControlMode: String, CaseIterable, Identifiable {
    case manual
    case audioReactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "手动测试"
        case .audioReactive: return "音频驱动"
        }
    }

    var detail: String {
        switch self {
        case .manual:
            return "手动发送持续/脉冲震动，验证蓝牙 HID 驱动是否正常。"
        case .audioReactive:
            return "抓取 macOS 系统音频，提取实时包络和低频强度并映射到 DualSense 震动。"
        }
    }
}

nonisolated enum HapticMode: String, CaseIterable, Identifiable {
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

nonisolated struct HapticConfiguration: Sendable {
    var mode: HapticMode = .constant
    var leftMotor: UInt8 = 160
    var rightMotor: UInt8 = 80
    var pulseFrequency: Double = 6
}

nonisolated struct AudioReactiveSample: Sendable {
    var rms: Float = 0
    var peak: Float = 0
    var lowFrequency: Float = 0
    var midFrequency: Float = 0
    var transient: Float = 0
    var attack: Float = 0
    var effect: Float = 0
    var movementPulse: Float = 0
    var music: Float = 0
    var background: Float = 0
    var framesProcessed: Int = 0
}

nonisolated struct AudioReactiveTuning: Sendable {
    var drive: Double
    var floor: Double
    var ceiling: Double
}

nonisolated struct AudioReactiveProfile: Sendable {
    var leftLow: Float
    var leftBody: Float
    var leftTransient: Float
    var rightLow: Float
    var rightBody: Float
    var rightTransient: Float
    var responseCurve: Float
}

nonisolated struct AudioReactiveDetectionProfile: Sendable {
    var musicSuppressionStrength: Float
    var sustainSuppressionStrength: Float
    var movementTriggerThreshold: Float
    var movementCooldown: TimeInterval
    var impactTriggerThreshold: Float
    var burstTriggerThreshold: Float
    var lowBandMusicPenalty: Float
    var midBandMusicPenalty: Float
    var musicDecay: Float
    var movementRecoveryGain: Float
    var backgroundGate: Float
    var sustainLeftCap: Float
    var sustainRightCap: Float
    var sustainLeftBias: Float
    var sustainRightBias: Float
    var tickStrengthCap: Float
    var pulseStrengthCap: Float
    var burstStrengthCap: Float
    var tickLeftMix: Float
    var tickRightMix: Float
    var pulseLeftMix: Float
    var pulseRightMix: Float
    var burstLeftMix: Float
    var burstRightMix: Float
}

nonisolated struct UserAudioPreset: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var basePresetRawValue: String
    var drive: Double
    var floor: Double
    var ceiling: Double
    var suppressMusic: Bool

    init(
        id: UUID = UUID(),
        name: String,
        basePresetRawValue: String,
        drive: Double,
        floor: Double,
        ceiling: Double,
        suppressMusic: Bool
    ) {
        self.id = id
        self.name = name
        self.basePresetRawValue = basePresetRawValue
        self.drive = drive
        self.floor = floor
        self.ceiling = ceiling
        self.suppressMusic = suppressMusic
    }

    var basePreset: AudioReactivePreset {
        AudioReactivePreset(rawValue: basePresetRawValue) ?? .balanced
    }
}

enum AudioReactivePreset: String, CaseIterable, Identifiable {
    case balanced
    case silksong
    case tunic
    case footsteps
    case combat
    case cinematic
    case bassBoost
    case impact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "均衡".localized
        case .silksong: return "丝之歌".localized
        case .tunic: return "TUNIC"
        case .footsteps: return "脚步".localized
        case .combat: return "战斗".localized
        case .cinematic: return "电影".localized
        case .bassBoost: return "低频增强".localized
        case .impact: return "冲击增强".localized
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            return "左右电机分工更均衡，适合先验证整体联动是否正常。".localized
        case .silksong:
            return "针对丝之歌背景乐抑制左侧残震，优先保留移动、攻击和受击事件。".localized
        case .tunic:
            return "针对 TUNIC 的持续氛围音乐做强抑制，只保留挥砍、受击和交互脉冲。".localized
        case .footsteps:
            return "更强调步态脉冲和轻量环境反馈，适合移动探索类游戏。".localized
        case .combat:
            return "偏向攻击、受击和武器挥动，适合近战动作游戏。".localized
        case .cinematic:
            return "保留环境氛围和关键事件，适合剧情和沉浸体验。".localized
        case .bassBoost:
            return "左电机更偏向低频包络，适合音乐和低频明显的内容。".localized
        case .impact:
            return "右电机更强调瞬态和节奏点，适合鼓点、射击、动作反馈。".localized
        }
    }

    var tuning: AudioReactiveTuning {
        switch self {
        case .balanced:
            return AudioReactiveTuning(drive: 2.2, floor: 0.015, ceiling: 0.14)
        case .silksong:
            return AudioReactiveTuning(drive: 1.85, floor: 0.022, ceiling: 0.17)
        case .tunic:
            return AudioReactiveTuning(drive: 1.70, floor: 0.024, ceiling: 0.18)
        case .footsteps:
            return AudioReactiveTuning(drive: 1.9, floor: 0.010, ceiling: 0.11)
        case .combat:
            return AudioReactiveTuning(drive: 2.5, floor: 0.014, ceiling: 0.10)
        case .cinematic:
            return AudioReactiveTuning(drive: 2.1, floor: 0.012, ceiling: 0.13)
        case .bassBoost:
            return AudioReactiveTuning(drive: 2.6, floor: 0.010, ceiling: 0.12)
        case .impact:
            return AudioReactiveTuning(drive: 2.8, floor: 0.018, ceiling: 0.11)
        }
    }

    var profile: AudioReactiveProfile {
        switch self {
        case .balanced:
            return AudioReactiveProfile(
                leftLow: 0.74,
                leftBody: 0.22,
                leftTransient: 0.04,
                rightLow: 0.08,
                rightBody: 0.54,
                rightTransient: 0.38,
                responseCurve: 0.92
            )
        case .silksong:
            return AudioReactiveProfile(
                leftLow: 0.42,
                leftBody: 0.12,
                leftTransient: 0.10,
                rightLow: 0.05,
                rightBody: 0.28,
                rightTransient: 0.82,
                responseCurve: 0.88
            )
        case .tunic:
            return AudioReactiveProfile(
                leftLow: 0.34,
                leftBody: 0.10,
                leftTransient: 0.14,
                rightLow: 0.04,
                rightBody: 0.20,
                rightTransient: 0.86,
                responseCurve: 0.82
            )
        case .footsteps:
            return AudioReactiveProfile(
                leftLow: 0.92,
                leftBody: 0.12,
                leftTransient: 0.06,
                rightLow: 0.18,
                rightBody: 0.26,
                rightTransient: 0.28,
                responseCurve: 0.96
            )
        case .combat:
            return AudioReactiveProfile(
                leftLow: 0.48,
                leftBody: 0.22,
                leftTransient: 0.30,
                rightLow: 0.04,
                rightBody: 0.20,
                rightTransient: 0.76,
                responseCurve: 0.76
            )
        case .cinematic:
            return AudioReactiveProfile(
                leftLow: 0.68,
                leftBody: 0.26,
                leftTransient: 0.10,
                rightLow: 0.12,
                rightBody: 0.44,
                rightTransient: 0.44,
                responseCurve: 0.90
            )
        case .bassBoost:
            return AudioReactiveProfile(
                leftLow: 0.88,
                leftBody: 0.10,
                leftTransient: 0.02,
                rightLow: 0.28,
                rightBody: 0.50,
                rightTransient: 0.22,
                responseCurve: 0.86
            )
        case .impact:
            return AudioReactiveProfile(
                leftLow: 0.52,
                leftBody: 0.28,
                leftTransient: 0.20,
                rightLow: 0.05,
                rightBody: 0.30,
                rightTransient: 0.65,
                responseCurve: 0.78
            )
        }
    }

    var detectionProfile: AudioReactiveDetectionProfile {
        switch self {
        case .balanced:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.06,
                sustainSuppressionStrength: 0.94,
                movementTriggerThreshold: 0.08,
                movementCooldown: 0.07,
                impactTriggerThreshold: 0.11,
                burstTriggerThreshold: 0.22,
                lowBandMusicPenalty: 0.26,
                midBandMusicPenalty: 0.18,
                musicDecay: 0.86,
                movementRecoveryGain: 0.42,
                backgroundGate: 0.035,
                sustainLeftCap: 0.20,
                sustainRightCap: 0.16,
                sustainLeftBias: 1.0,
                sustainRightBias: 1.0,
                tickStrengthCap: 0.52,
                pulseStrengthCap: 0.66,
                burstStrengthCap: 0.92,
                tickLeftMix: 0.18,
                tickRightMix: 0.05,
                pulseLeftMix: 0.09,
                pulseRightMix: 0.24,
                burstLeftMix: 0.14,
                burstRightMix: 0.34
            )
        case .silksong:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.38,
                sustainSuppressionStrength: 1.16,
                movementTriggerThreshold: 0.10,
                movementCooldown: 0.09,
                impactTriggerThreshold: 0.10,
                burstTriggerThreshold: 0.20,
                lowBandMusicPenalty: 0.44,
                midBandMusicPenalty: 0.34,
                musicDecay: 0.80,
                movementRecoveryGain: 0.36,
                backgroundGate: 0.055,
                sustainLeftCap: 0.11,
                sustainRightCap: 0.08,
                sustainLeftBias: 0.62,
                sustainRightBias: 0.48,
                tickStrengthCap: 0.34,
                pulseStrengthCap: 0.68,
                burstStrengthCap: 0.90,
                tickLeftMix: 0.18,
                tickRightMix: 0.04,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.34,
                burstLeftMix: 0.10,
                burstRightMix: 0.46
            )
        case .tunic:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.52,
                sustainSuppressionStrength: 1.24,
                movementTriggerThreshold: 0.12,
                movementCooldown: 0.12,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.18,
                lowBandMusicPenalty: 0.52,
                midBandMusicPenalty: 0.40,
                musicDecay: 0.92,
                movementRecoveryGain: 0.28,
                backgroundGate: 0.06,
                sustainLeftCap: 0.09,
                sustainRightCap: 0.06,
                sustainLeftBias: 0.52,
                sustainRightBias: 0.42,
                tickStrengthCap: 0.24,
                pulseStrengthCap: 0.72,
                burstStrengthCap: 0.94,
                tickLeftMix: 0.10,
                tickRightMix: 0.03,
                pulseLeftMix: 0.06,
                pulseRightMix: 0.38,
                burstLeftMix: 0.12,
                burstRightMix: 0.52
            )
        case .footsteps:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 0.92,
                sustainSuppressionStrength: 0.84,
                movementTriggerThreshold: 0.06,
                movementCooldown: 0.06,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.26,
                lowBandMusicPenalty: 0.18,
                midBandMusicPenalty: 0.12,
                musicDecay: 0.84,
                movementRecoveryGain: 0.48,
                backgroundGate: 0.022,
                sustainLeftCap: 0.24,
                sustainRightCap: 0.16,
                sustainLeftBias: 1.08,
                sustainRightBias: 0.88,
                tickStrengthCap: 0.58,
                pulseStrengthCap: 0.60,
                burstStrengthCap: 0.82,
                tickLeftMix: 0.22,
                tickRightMix: 0.07,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.20,
                burstLeftMix: 0.12,
                burstRightMix: 0.28
            )
        case .combat:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.08,
                sustainSuppressionStrength: 0.90,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.08,
                impactTriggerThreshold: 0.08,
                burstTriggerThreshold: 0.16,
                lowBandMusicPenalty: 0.24,
                midBandMusicPenalty: 0.16,
                musicDecay: 0.84,
                movementRecoveryGain: 0.30,
                backgroundGate: 0.03,
                sustainLeftCap: 0.16,
                sustainRightCap: 0.12,
                sustainLeftBias: 0.88,
                sustainRightBias: 0.92,
                tickStrengthCap: 0.38,
                pulseStrengthCap: 0.72,
                burstStrengthCap: 0.96,
                tickLeftMix: 0.14,
                tickRightMix: 0.05,
                pulseLeftMix: 0.10,
                pulseRightMix: 0.32,
                burstLeftMix: 0.14,
                burstRightMix: 0.48
            )
        case .cinematic:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.14,
                sustainSuppressionStrength: 0.98,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.10,
                impactTriggerThreshold: 0.11,
                burstTriggerThreshold: 0.22,
                lowBandMusicPenalty: 0.30,
                midBandMusicPenalty: 0.22,
                musicDecay: 0.90,
                movementRecoveryGain: 0.34,
                backgroundGate: 0.04,
                sustainLeftCap: 0.17,
                sustainRightCap: 0.13,
                sustainLeftBias: 0.90,
                sustainRightBias: 0.84,
                tickStrengthCap: 0.30,
                pulseStrengthCap: 0.58,
                burstStrengthCap: 0.76,
                tickLeftMix: 0.16,
                tickRightMix: 0.05,
                pulseLeftMix: 0.08,
                pulseRightMix: 0.18,
                burstLeftMix: 0.12,
                burstRightMix: 0.22
            )
        case .bassBoost:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 0.86,
                sustainSuppressionStrength: 0.70,
                movementTriggerThreshold: 0.07,
                movementCooldown: 0.07,
                impactTriggerThreshold: 0.12,
                burstTriggerThreshold: 0.24,
                lowBandMusicPenalty: 0.10,
                midBandMusicPenalty: 0.08,
                musicDecay: 0.88,
                movementRecoveryGain: 0.52,
                backgroundGate: 0.02,
                sustainLeftCap: 0.28,
                sustainRightCap: 0.22,
                sustainLeftBias: 1.12,
                sustainRightBias: 0.96,
                tickStrengthCap: 0.48,
                pulseStrengthCap: 0.62,
                burstStrengthCap: 0.82,
                tickLeftMix: 0.20,
                tickRightMix: 0.06,
                pulseLeftMix: 0.12,
                pulseRightMix: 0.18,
                burstLeftMix: 0.16,
                burstRightMix: 0.26
            )
        case .impact:
            return AudioReactiveDetectionProfile(
                musicSuppressionStrength: 1.04,
                sustainSuppressionStrength: 0.88,
                movementTriggerThreshold: 0.09,
                movementCooldown: 0.08,
                impactTriggerThreshold: 0.08,
                burstTriggerThreshold: 0.14,
                lowBandMusicPenalty: 0.20,
                midBandMusicPenalty: 0.12,
                musicDecay: 0.82,
                movementRecoveryGain: 0.24,
                backgroundGate: 0.03,
                sustainLeftCap: 0.15,
                sustainRightCap: 0.12,
                sustainLeftBias: 0.78,
                sustainRightBias: 0.88,
                tickStrengthCap: 0.34,
                pulseStrengthCap: 0.76,
                burstStrengthCap: 0.98,
                tickLeftMix: 0.12,
                tickRightMix: 0.05,
                pulseLeftMix: 0.09,
                pulseRightMix: 0.30,
                burstLeftMix: 0.15,
                burstRightMix: 0.44
            )
        }
    }
}

enum LightbarColorPreset: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: return "红".localized
        case .orange: return "橙".localized
        case .yellow: return "黄".localized
        case .green: return "绿".localized
        case .cyan: return "青".localized
        case .blue: return "蓝".localized
        case .purple: return "紫".localized
        case .pink: return "粉".localized
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .red: return (0.95, 0.29, 0.27)
        case .orange: return (0.97, 0.56, 0.19)
        case .yellow: return (0.95, 0.79, 0.21)
        case .green: return (0.27, 0.78, 0.38)
        case .cyan: return (0.22, 0.76, 0.87)
        case .blue: return (0.24, 0.48, 0.98)
        case .purple: return (0.58, 0.40, 0.95)
        case .pink: return (0.93, 0.39, 0.72)
        }
    }
}

nonisolated enum LogFileSizeOption: Int, CaseIterable, Identifiable {
    case mb20 = 20
    case mb50 = 50
    case mb100 = 100

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)MB"
    }

    var bytes: Int {
        rawValue * 1_024 * 1_024
    }
}

nonisolated struct DriverStats: Sendable {
    var sentReports: Int = 0
    var lastSequence: Int = 0
    var lastLeftMotor: Int = 0
    var lastRightMotor: Int = 0
    var lastResult: String = "idle"
}
