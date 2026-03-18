import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var menuTitle: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "Ds5plus.language")
        }
    }

    private init() {
        if let rawValue = UserDefaults.standard.string(forKey: "Ds5plus.language"),
           let language = AppLanguage(rawValue: rawValue) {
            self.language = language
        } else {
            self.language = .chinese
        }
    }
}

private let englishTranslations: [String: String] = [
    "刷新蓝牙设备和音频捕获源": "Refresh Bluetooth devices and audio capture sources",
    "停止音频驱动": "Stop audio driver",
    "开始音频驱动": "Start audio driver",
    "打开设置与日志": "Open settings and logs",
    "连接": "Connection",
    "捕获": "Capture",
    "运行": "Status",
    "蓝牙 DualSense": "Bluetooth DualSense",
    "选择蓝牙 DualSense": "Select Bluetooth DualSense",
    "请先在 macOS 蓝牙设置中连接 DualSense。": "Please connect DualSense in macOS Bluetooth settings first.",
    "捕获显示器": "Capture Display",
    "手柄电量": "Battery",
    "灯条偏色": "Lightbar Tint",
    "灯条颜色": "Lightbar Color",
    "运行时动态偏色": "Dynamic tint while running",
    "可直接选预设颜色；点右上角“···”可自定义色相、饱和度与亮度。": "Choose a preset color directly, or click “···” in the top-right to customize hue, saturation, and brightness.",
    "音频驱动": "Audio Driver",
    "音频预设": "Audio Preset",
    "将当前参数保存为自定义预设": "Save current parameters as a custom preset",
    "恢复默认": "Restore Default",
    "内置预设": "Built-in Presets",
    "自定义预设": "Custom Presets",
    "驱动增益": "Drive Gain",
    "提高后整体震动更强、更容易触发；降低后更克制，适合避免持续轰鸣。": "Higher values make vibration stronger and easier to trigger; lower values keep it more controlled and reduce constant rumble.",
    "噪声门限": "Noise Gate",
    "提高后会过滤更多细小背景声与底噪；降低后更容易保留脚步、轻环境音。": "Higher values filter more low-level ambience and noise; lower values preserve footsteps and subtle environmental sounds.",
    "满刻度": "Full Scale",
    "降低后更容易达到强震；提高后动态更宽，适合避免普通场景过强。": "Lower values reach strong vibration more easily; higher values widen the dynamic range and keep normal scenes from feeling too strong.",
    "游戏模式": "Game Mode",
    "优先保留音效、环境音、攻击与步态脉冲，同时压低背景音乐。": "Prioritize SFX, ambience, attacks, and movement pulses while suppressing background music.",
    "自定义灯条颜色": "Custom lightbar color",
    "自定义灯条": "Custom Lightbar",
    "调整后会立即预览，并切换为自定义颜色。": "Changes are previewed instantly and switch the lightbar to a custom color.",
    "色相": "Hue",
    "饱和度": "Saturation",
    "亮度": "Brightness",
    "新建自定义预设": "New Custom Preset",
    "会保存当前选中的基础预设、三个调节项，以及“游戏模式”开关状态。": "This saves the current base preset, the three sliders, and the Game Mode switch state.",
    "预设名称": "Preset Name",
    "例如：夜间轻震 / 动作游戏": "For example: Night Light / Action Game",
    "取消": "Cancel",
    "保存": "Save",
    "设置": "Settings",
    "完成": "Done",
    "日志文件": "Log File",
    "当前大小": "Current Size",
    "最大大小": "Max Size",
    "日志最大大小": "Max Log Size",
    "刷新日志": "Refresh Logs",
    "在 Finder 中显示": "Reveal in Finder",
    "打开日志文件夹": "Open Logs Folder",
    "复制路径": "Copy Path",
    "本地日志预览": "Local Log Preview",
    "暂无日志。": "No logs yet.",
    "关闭": "Close",
    "关于 Ds5Plus…": "About Ds5Plus…",
    "关于 Ds5Plus": "About Ds5Plus",
    "语言": "Language",
    "日志": "Logs",
    "打开设置": "Open Settings",
    "打开日志文件夹（菜单）": "Open Logs Folder",
    "在 Finder 中显示日志": "Reveal Logs in Finder",
    "复制日志路径": "Copy Log Path",
    "清空日志": "Clear Logs",
    "版本 %@": "Version %@",
    "无线蓝牙 DualSense 音频驱动工具": "Wireless Bluetooth DualSense audio driver utility",
    "项目信息": "Project Info",
    "开发者": "Developer",
    "构建版本": "Build",
    "项目地址": "Project URL",
    "未设置": "Not Set",
    "均衡": "Balanced",
    "丝之歌": "Silksong",
    "脚步": "Footsteps",
    "战斗": "Combat",
    "电影": "Cinematic",
    "低频增强": "Bass Boost",
    "冲击增强": "Impact Boost",
    "左右电机分工更均衡，适合先验证整体联动是否正常。": "A more balanced split between left and right motors, good for verifying overall response.",
    "针对丝之歌背景乐抑制左侧残震，优先保留移动、攻击和受击事件。": "Suppresses leftover left-side rumble from Silksong BGM while preserving movement, attacks, and hit events.",
    "针对 TUNIC 的持续氛围音乐做强抑制，只保留挥砍、受击和交互脉冲。": "Strongly suppresses TUNIC ambience music and keeps sword swings, hits, and interaction pulses.",
    "更强调步态脉冲和轻量环境反馈，适合移动探索类游戏。": "Emphasizes movement pulses and light ambience, ideal for exploration-focused games.",
    "偏向攻击、受击和武器挥动，适合近战动作游戏。": "Focused on attacks, impacts, and weapon swings, ideal for melee action games.",
    "保留环境氛围和关键事件，适合剧情和沉浸体验。": "Keeps ambience and key events for narrative and immersive experiences.",
    "左电机更偏向低频包络，适合音乐和低频明显的内容。": "Shifts the left motor toward low-frequency envelopes, great for music and bass-heavy content.",
    "右电机更强调瞬态和节奏点，适合鼓点、射击、动作反馈。": "Makes the right motor emphasize transients and rhythmic impacts, ideal for drums, shooting, and action feedback.",
    "红": "Red",
    "橙": "Orange",
    "黄": "Yellow",
    "绿": "Green",
    "青": "Cyan",
    "蓝": "Blue",
    "紫": "Purple",
    "粉": "Pink",
    "已连接": "Connected",
    "未连接": "Disconnected",
    "正常": "Normal",
    "异常": "Error",
    "未启动": "Stopped",
    "放电中": "Discharging",
    "充电中": "Charging",
    "已充满": "Full",
    "未充电": "Not Charging",
    "状态未知": "Unknown",
    "自定义": "Custom",
    "灯条偏色：%@": "Lightbar Tint: %@",
    "刷新蓝牙设备": "Refresh Bluetooth Devices",
    "当前参数": "Current Parameters"
]

extension String {
    var localized: String {
        guard LanguageManager.shared.language == .english else { return self }
        return englishTranslations[self] ?? self
    }
}
