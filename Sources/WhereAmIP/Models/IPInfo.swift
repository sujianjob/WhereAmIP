import Foundation

/// 公网 IP 与归属地核心数据模型
public struct IPInfo: Codable, Equatable, Sendable {
    /// 公网 IP 地址 (IPv4 / IPv6)
    public let ip: String
    /// ISO 3166-1 alpha-2 两位国家/地区代码 (如 US, CN, JP, HK, SG)
    public let countryCode: String
    /// 接口返回的原始国家/地区名称
    public let countryName: String
    /// 省份/州/区域
    public let region: String?
    /// 城市名称
    public let city: String?
    /// 运营商 (ISP) 名称
    public let isp: String?
    /// 自治系统号 (ASN)
    public let asn: String?
    /// 数据探测源名称 (如 ipwho.is, ipinfo.io, cloudflare)
    public let source: String
    /// 数据获取时间戳
    public let fetchedAt: Date

    public init(
        ip: String,
        countryCode: String,
        countryName: String,
        region: String? = nil,
        city: String? = nil,
        isp: String? = nil,
        asn: String? = nil,
        source: String,
        fetchedAt: Date = Date()
    ) {
        self.ip = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.countryName = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.city = city?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.isp = isp?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.asn = asn?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.source = source
        self.fetchedAt = fetchedAt
    }

    /// 对应国家/地区的国旗 Emoji
    public var flagEmoji: String {
        CountryFlagHelper.flag(for: countryCode)
    }

    /// 本地化中文国家/地区名称（优先使用系统 Locale 中文名，回退至接口返回名）
    public var localizedCountryName: String {
        CountryFlagHelper.localizedName(for: countryCode, fallback: countryName)
    }

    /// 组合位置描述，如 "California · San Jose"
    public var locationDetail: String? {
        let parts = [region, city].compactMap { $0 }.filter { !$0.isEmpty }
        // 去重（比如新加坡或香港，region 和 city 可能相同）
        var uniqueParts: [String] = []
        for part in parts {
            if !uniqueParts.contains(part) {
                uniqueParts.append(part)
            }
        }
        return uniqueParts.isEmpty ? nil : uniqueParts.joined(separator: " · ")
    }

    /// 组合运营商与 ASN 描述
    public var ispDetail: String? {
        switch (isp, asn) {
        case let (isp?, asn?):
            if isp.contains(asn) {
                return isp
            }
            return "\(isp) (\(asn))"
        case let (isp?, nil):
            return isp
        case let (nil, asn?):
            return asn
        case (nil, nil):
            return nil
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
