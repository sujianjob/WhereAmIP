import Foundation

/// 状态栏显示样式
public enum DisplayMode: String, CaseIterable, Sendable {
    /// 仅显示国旗 Emoji（如：🇺🇸）
    case flagOnly = "flag_only"
    /// 国旗 + 两位国家代码（如：🇺🇸 US）
    case flagAndCode = "flag_and_code"
    /// 国旗 + 本地化国家名（如：🇺🇸 美国）
    case flagAndName = "flag_and_name"
    /// 国旗 + 公网 IP（如：🇺🇸 1.2.3.4）
    case flagAndIP = "flag_and_ip"

    public var title: String {
        switch self {
        case .flagOnly:
            return "仅显示国旗 (🇺🇸)"
        case .flagAndCode:
            return "国旗 + 代码 (🇺🇸 US)"
        case .flagAndName:
            return "国旗 + 国家名 (🇺🇸 美国)"
        case .flagAndIP:
            return "国旗 + IP (🇺🇸 1.2.3.4)"
        }
    }

    public func format(info: IPInfo) -> String {
        switch self {
        case .flagOnly:
            return info.flagEmoji
        case .flagAndCode:
            return "\(info.flagEmoji) \(info.countryCode)"
        case .flagAndName:
            return "\(info.flagEmoji) \(info.localizedCountryName)"
        case .flagAndIP:
            return "\(info.flagEmoji) \(info.ip)"
        }
    }
}

/// 自动刷新频率预设（第二层低频智能轮询）
public enum RefreshPreset: String, CaseIterable, Sendable {
    /// 灵敏模式：2 分钟
    case fast = "fast_2m"
    /// 平衡模式：5 分钟（默认推荐）
    case balanced = "balanced_5m"
    /// 极省电模式：15 分钟
    case powerSaving = "power_saving_15m"

    public var title: String {
        switch self {
        case .fast:
            return "🚀 灵敏模式 (2 分钟 + 事件触发)"
        case .balanced:
            return "⚖️ 平衡模式 (5 分钟 + 事件触发)"
        case .powerSaving:
            return "🍃 极省电模式 (15 分钟 + 事件触发)"
        }
    }

    /// 接通电源时的基准轮询间隔（秒）
    public var baseInterval: TimeInterval {
        switch self {
        case .fast:
            return 120
        case .balanced:
            return 300
        case .powerSaving:
            return 900
        }
    }

    /// 使用电池供电时的自适应轮询间隔（秒）
    public var batteryInterval: TimeInterval {
        switch self {
        case .fast:
            return 240 // 4 分钟
        case .balanced:
            return 600 // 10 分钟
        case .powerSaving:
            return 1200 // 20 分钟
        }
    }
}

/// 应用偏好设置管理
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let displayModeKey = "WhereAmIP.displayMode"
    private let refreshPresetKey = "WhereAmIP.refreshPreset"
    private let notifyOnIPChangeKey = "WhereAmIP.notifyOnIPChange"

    public var onChange: (() -> Void)?

    public var displayMode: DisplayMode {
        get {
            guard let raw = defaults.string(forKey: displayModeKey),
                  let mode = DisplayMode(rawValue: raw) else {
                return .flagAndCode
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: displayModeKey)
            onChange?()
        }
    }

    public var refreshPreset: RefreshPreset {
        get {
            guard let raw = defaults.string(forKey: refreshPresetKey),
                  let preset = RefreshPreset(rawValue: raw) else {
                return .balanced
            }
            return preset
        }
        set {
            defaults.set(newValue.rawValue, forKey: refreshPresetKey)
            onChange?()
        }
    }

    /// 当出口 IP 发生变化时是否弹出系统通知（默认开启 true）
    public var notifyOnIPChange: Bool {
        get {
            if defaults.object(forKey: notifyOnIPChangeKey) == nil {
                return true
            }
            return defaults.bool(forKey: notifyOnIPChangeKey)
        }
        set {
            defaults.set(newValue, forKey: notifyOnIPChangeKey)
            onChange?()
        }
    }

    private init() {}
}
