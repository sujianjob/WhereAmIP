import Foundation

/// ISO 3166-1 alpha-2 国家/地区代码转国旗 Emoji 与中文名称工具
public enum CountryFlagHelper {
    /// Unicode Regional Indicator Symbol 'A' 的起始码点 (U+1F1E6)
    private static let regionalIndicatorBase: UInt32 = 0x1F1E6
    private static let uppercaseABase: UInt32 = 0x0041 // 'A'

    /// 将两位国家代码（如 "US", "CN", "JP"）转换为对应国旗 Emoji（如 🇺🇸, 🇨🇳, 🇯🇵）
    /// - Parameter countryCode: 两位 ISO 3166-1 alpha-2 代码
    /// - Returns: 国旗 Emoji 字符串，若代码非法则返回 🌐
    public static func flag(for countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else {
            return "🌐"
        }

        // Tor 节点或未知保留码特殊处理
        if code == "XX" || code == "ZZ" || code == "T1" {
            return "🌐"
        }

        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            // 仅允许 'A' (0x41) 到 'Z' (0x5A)
            guard scalar.value >= 0x41 && scalar.value <= 0x5A else {
                return "🌐"
            }
            let indicatorValue = regionalIndicatorBase + (scalar.value - uppercaseABase)
            guard let regionalScalar = UnicodeScalar(indicatorValue) else {
                return "🌐"
            }
            scalars.append(regionalScalar)
        }
        return String(scalars)
    }

    /// 获取国家/地区的中文名称
    /// - Parameters:
    ///   - countryCode: 两位 ISO 3166-1 alpha-2 代码
    ///   - fallback: 当系统 Locale 无法解析时的回退名称
    /// - Returns: 中文国家/地区名称
    public static func localizedName(for countryCode: String, fallback: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else {
            return fallback.isEmpty ? "未知地区" : fallback
        }

        let zhLocale = Locale(identifier: "zh-Hans")
        if let localized = zhLocale.localizedString(forRegionCode: code), !localized.isEmpty {
            return localized
        }
        return fallback.isEmpty ? code : fallback
    }
}
