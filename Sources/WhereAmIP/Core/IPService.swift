import Foundation

/// IP 探测错误类型
public enum IPServiceError: Error, LocalizedError {
    case allProvidersFailed([String])
    case invalidResponse
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .allProvidersFailed(let details):
            return "所有探测源均不可用: \(details.joined(separator: "; "))"
        case .invalidResponse:
            return "服务器返回无效响应"
        case .decodingFailed:
            return "响应数据解析失败"
        }
    }
}

/// 高可用多源公网 IP 与归属地探测服务
public actor IPService {
    public static let shared = IPService()

    /// 单次源请求超时时间（秒）
    private let requestTimeout: TimeInterval = 4.0

    public init() {}

    /// 按优先级依次尝试多个探测源，获取当前出口 IP 归属地信息
    public func fetchCurrentIPInfo() async throws -> IPInfo {
        let providers: [(name: String, fetcher: @Sendable () async throws -> IPInfo)] = [
            ("ipwho.is", { try await self.fetchFromIPWhoIs() }),
            ("ip.sb", { try await self.fetchFromIPSb() }),
            ("ipinfo.io", { try await self.fetchFromIPInfo() }),
            ("ip-api.com", { try await self.fetchFromIPAPI() }),
            ("Cloudflare Trace", { try await self.fetchFromCloudflareTrace() })
        ]

        var failureReasons: [String] = []

        for provider in providers {
            do {
                let info = try await provider.fetcher()
                guard !info.ip.isEmpty, info.countryCode.count == 2 else {
                    throw IPServiceError.decodingFailed
                }
                return info
            } catch {
                failureReasons.append("\(provider.name): \(error.localizedDescription)")
                continue
            }
        }

        throw IPServiceError.allProvidersFailed(failureReasons)
    }

    // MARK: - 独立无缓存请求会话（避免切换节点后复用旧 Socket 连接池）

    private func makeFreshSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout + 1.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "WhereAmIP/1.0 (macOS; Native MenuBar Utility)",
            "Accept": "application/json, text/plain;q=0.8"
        ]
        return URLSession(configuration: config)
    }

    private func performGET(url: URL) async throws -> Data {
        let session = makeFreshSession()
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw IPServiceError.invalidResponse
        }
        return data
    }

    // MARK: - 源 1: ipwho.is (HTTPS, 丰富 ASN/ISP 信息)

    private struct IPWhoIsResponse: Decodable {
        let ip: String
        let success: Bool?
        let country: String?
        let country_code: String?
        let region: String?
        let city: String?
        let connection: Connection?

        struct Connection: Decodable {
            let asn: Int?
            let org: String?
            let isp: String?
        }
    }

    private func fetchFromIPWhoIs() async throws -> IPInfo {
        let url = URL(string: "https://ipwho.is/")!
        let data = try await performGET(url: url)
        let decoded = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
        if decoded.success == false {
            throw IPServiceError.invalidResponse
        }
        guard let code = decoded.country_code, !code.isEmpty else {
            throw IPServiceError.decodingFailed
        }
        let asnString = decoded.connection?.asn.map { "AS\($0)" }
        let ispString = decoded.connection?.isp ?? decoded.connection?.org
        return IPInfo(
            ip: decoded.ip,
            countryCode: code,
            countryName: decoded.country ?? code,
            region: decoded.region,
            city: decoded.city,
            isp: ispString,
            asn: asnString,
            source: "ipwho.is"
        )
    }

    // MARK: - 源 2: api.ip.sb (HTTPS, 极速全球 Anycast)

    private struct IPSbResponse: Decodable {
        let ip: String
        let country_code: String?
        let country: String?
        let region: String?
        let city: String?
        let isp: String?
        let organization: String?
        let asn: Int?
    }

    private func fetchFromIPSb() async throws -> IPInfo {
        let url = URL(string: "https://api.ip.sb/geoip")!
        let data = try await performGET(url: url)
        let decoded = try JSONDecoder().decode(IPSbResponse.self, from: data)
        guard let code = decoded.country_code, !code.isEmpty else {
            throw IPServiceError.decodingFailed
        }
        return IPInfo(
            ip: decoded.ip,
            countryCode: code,
            countryName: decoded.country ?? code,
            region: decoded.region,
            city: decoded.city,
            isp: decoded.isp ?? decoded.organization,
            asn: decoded.asn.map { "AS\($0)" },
            source: "ip.sb"
        )
    }

    // MARK: - 源 3: ipinfo.io (HTTPS, 经典权威源)

    private struct IPInfoResponse: Decodable {
        let ip: String
        let country: String?
        let region: String?
        let city: String?
        let org: String?
    }

    private func fetchFromIPInfo() async throws -> IPInfo {
        let url = URL(string: "https://ipinfo.io/json")!
        let data = try await performGET(url: url)
        let decoded = try JSONDecoder().decode(IPInfoResponse.self, from: data)
        guard let code = decoded.country, !code.isEmpty else {
            throw IPServiceError.decodingFailed
        }

        // ipinfo 的 org 格式通常为 "AS13335 Cloudflare, Inc."
        var asn: String? = nil
        var isp: String? = decoded.org
        if let org = decoded.org, org.hasPrefix("AS") {
            let parts = org.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                asn = String(parts[0])
                isp = String(parts[1])
            }
        }

        return IPInfo(
            ip: decoded.ip,
            countryCode: code,
            countryName: code,
            region: decoded.region,
            city: decoded.city,
            isp: isp,
            asn: asn,
            source: "ipinfo.io"
        )
    }

    // MARK: - 源 4: ip-api.com (高可用备用)

    private struct IPAPIResponse: Decodable {
        let status: String?
        let query: String
        let country: String?
        let countryCode: String?
        let regionName: String?
        let city: String?
        let isp: String?
        let `as`: String?
    }

    private func fetchFromIPAPI() async throws -> IPInfo {
        let url = URL(string: "http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,isp,as,query")!
        let data = try await performGET(url: url)
        let decoded = try JSONDecoder().decode(IPAPIResponse.self, from: data)
        guard decoded.status == "success", let code = decoded.countryCode, !code.isEmpty else {
            throw IPServiceError.invalidResponse
        }

        var asn: String? = nil
        if let asField = decoded.as, let firstToken = asField.split(separator: " ").first {
            asn = String(firstToken)
        }

        return IPInfo(
            ip: decoded.query,
            countryCode: code,
            countryName: decoded.country ?? code,
            region: decoded.regionName,
            city: decoded.city,
            isp: decoded.isp,
            asn: asn,
            source: "ip-api.com"
        )
    }

    // MARK: - 源 5: Cloudflare Trace (终极保底，几乎永不限流)

    private func fetchFromCloudflareTrace() async throws -> IPInfo {
        let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!
        let data = try await performGET(url: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw IPServiceError.decodingFailed
        }

        var dict: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                dict[String(parts[0])] = String(parts[1])
            }
        }

        guard let ip = dict["ip"], !ip.isEmpty,
              let loc = dict["loc"], !loc.isEmpty else {
            throw IPServiceError.decodingFailed
        }

        return IPInfo(
            ip: ip,
            countryCode: loc,
            countryName: loc,
            region: nil,
            city: nil,
            isp: dict["colo"].map { "Cloudflare POP (\($0))" },
            asn: nil,
            source: "Cloudflare"
        )
    }
}
