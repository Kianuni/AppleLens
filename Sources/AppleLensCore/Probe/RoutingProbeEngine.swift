import CFNetwork
import Darwin
import Foundation
import Network
import os
import Security

public struct CustomProxyConfig: Hashable, Codable, Sendable {
    public enum ProxyScheme: String, CaseIterable, Codable, Sendable {
        case http = "HTTP"
        case socks5 = "SOCKS5"
    }

    public let scheme: ProxyScheme
    public let host: String
    public let port: UInt16

    public init(scheme: ProxyScheme = .http, host: String, port: UInt16) {
        self.scheme = scheme
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
    }

    public var displayString: String {
        let prefix = scheme == .http ? "http" : "socks5"
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return "\(prefix)://\(formattedHost):\(port)"
    }

    public static func parse(_ raw: String, defaultScheme: ProxyScheme = .http) -> CustomProxyConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var resolvedScheme = defaultScheme
        var remainder = trimmed

        if let schemeRange = remainder.range(of: "://") {
            let rawScheme = remainder[..<schemeRange.lowerBound].lowercased()
            switch rawScheme {
            case "http", "https":
                resolvedScheme = .http
            case "socks5":
                resolvedScheme = .socks5
            default:
                return nil
            }
            remainder = String(remainder[schemeRange.upperBound...])
        }

        while remainder.hasSuffix("/") {
            remainder.removeLast()
        }
        guard !remainder.isEmpty else { return nil }

        let hostPart: String
        let portPart: String

        if remainder.hasPrefix("[") {
            guard let closeBracket = remainder.firstIndex(of: "]") else { return nil }
            let inside = String(remainder[remainder.index(after: remainder.startIndex)..<closeBracket])
            let afterBracket = remainder[remainder.index(after: closeBracket)...]
            guard afterBracket.hasPrefix(":") else { return nil }
            hostPart = inside
            portPart = String(afterBracket.dropFirst())
        } else {
            guard let colon = remainder.lastIndex(of: ":") else { return nil }
            hostPart = String(remainder[..<colon])
            portPart = String(remainder[remainder.index(after: colon)...])
            if hostPart.contains(":") { return nil }
        }

        guard !hostPart.isEmpty,
              hostPart.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !hostPart.contains("/"),
              !hostPart.contains("?"),
              !hostPart.contains("#"),
              !hostPart.contains("@"),
              !portPart.isEmpty,
              portPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = UInt16(portPart),
              port >= 1 else {
            return nil
        }

        return CustomProxyConfig(scheme: resolvedScheme, host: hostPart, port: port)
    }
}

public struct CertificateChainAudit: Sendable, Equatable {
    public let leafSubject: String?
    public let rootSubject: String?
    public let issuerSummary: String?
    public let isMitMDetected: Bool
    public let mitmReason: String?

    public init(
        leafSubject: String?,
        rootSubject: String?,
        issuerSummary: String?,
        isMitMDetected: Bool,
        mitmReason: String?
    ) {
        self.leafSubject = leafSubject
        self.rootSubject = rootSubject
        self.issuerSummary = issuerSummary
        self.isMitMDetected = isMitMDetected
        self.mitmReason = mitmReason
    }
}

public enum ProbeVerdictLevel: String, Codable, Sendable {
    case pass
    case warn
    case error
}

public struct ExitRegionLaneResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let titleZh: String
    public let titleEn: String
    public let reachable: Bool
    public let latencyMs: Int
    public let countryCode: String
    public let coloCode: String
    public let ipAddress: String
    public let probedHost: String
    public let verdictLevel: ProbeVerdictLevel
    public let verdictZh: String
    public let verdictEn: String

    public init(
        id: String,
        titleZh: String,
        titleEn: String,
        reachable: Bool,
        latencyMs: Int,
        countryCode: String,
        coloCode: String,
        ipAddress: String,
        probedHost: String,
        verdictLevel: ProbeVerdictLevel,
        verdictZh: String,
        verdictEn: String
    ) {
        self.id = id
        self.titleZh = titleZh
        self.titleEn = titleEn
        self.reachable = reachable
        self.latencyMs = latencyMs
        self.countryCode = countryCode
        self.coloCode = coloCode
        self.ipAddress = ipAddress
        self.probedHost = probedHost
        self.verdictLevel = verdictLevel
        self.verdictZh = verdictZh
        self.verdictEn = verdictEn
    }

    public func title(lang: AppLanguage) -> String { tr(titleZh, titleEn, lang: lang) }
    public func verdict(lang: AppLanguage) -> String { tr(verdictZh, verdictEn, lang: lang) }
}

public struct EndpointTLSProbeResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String // host
    public let host: String
    public let roleZh: String
    public let roleEn: String
    public let expectDirect: Bool
    public let pinningSensitive: Bool
    public let reachable: Bool
    public let httpStatus: Int?
    public let latencyMs: Int
    public let leafSubject: String?
    public let issuerSummary: String?
    public let rootSubject: String?
    public let isMitMDetected: Bool
    public let mitmReason: String?
    public let errorDescription: String?

    public init(
        id: String,
        host: String,
        roleZh: String,
        roleEn: String,
        expectDirect: Bool,
        pinningSensitive: Bool,
        reachable: Bool,
        httpStatus: Int?,
        latencyMs: Int,
        leafSubject: String?,
        issuerSummary: String?,
        rootSubject: String?,
        isMitMDetected: Bool,
        mitmReason: String?,
        errorDescription: String?
    ) {
        self.id = id
        self.host = host
        self.roleZh = roleZh
        self.roleEn = roleEn
        self.expectDirect = expectDirect
        self.pinningSensitive = pinningSensitive
        self.reachable = reachable
        self.httpStatus = httpStatus
        self.latencyMs = latencyMs
        self.leafSubject = leafSubject
        self.issuerSummary = issuerSummary
        self.rootSubject = rootSubject
        self.isMitMDetected = isMitMDetected
        self.mitmReason = mitmReason
        self.errorDescription = errorDescription
    }

    public func role(lang: AppLanguage) -> String { tr(roleZh, roleEn, lang: lang) }
}

public struct SiriDNSAuditResult: Hashable, Codable, Sendable {
    public let guzzoniResolvedIPs: [String]
    public let siriResolvedIPs: [String]
    public let isGuzzoniFakeIP: Bool
    public let isSiriFakeIP: Bool
    public let systemProxyEnabled: Bool
    public let exceptionsIncludeGuzzoni: Bool
    public let guzzoniCanonicalName: String?

    public init(
        guzzoniResolvedIPs: [String],
        siriResolvedIPs: [String],
        isGuzzoniFakeIP: Bool,
        isSiriFakeIP: Bool,
        systemProxyEnabled: Bool,
        exceptionsIncludeGuzzoni: Bool,
        guzzoniCanonicalName: String? = nil
    ) {
        self.guzzoniResolvedIPs = guzzoniResolvedIPs
        self.siriResolvedIPs = siriResolvedIPs
        self.isGuzzoniFakeIP = isGuzzoniFakeIP
        self.isSiriFakeIP = isSiriFakeIP
        self.systemProxyEnabled = systemProxyEnabled
        self.exceptionsIncludeGuzzoni = exceptionsIncludeGuzzoni
        self.guzzoniCanonicalName = guzzoniCanonicalName
    }

    public var isHealthy: Bool {
        if isGuzzoniFakeIP || isSiriFakeIP { return false }
        if systemProxyEnabled && !exceptionsIncludeGuzzoni { return false }
        return true
    }
}

public struct QUICProbeResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let host: String
    public let port: UInt16
    public let succeeded: Bool
    public let latencyMs: Int
    public let detailZh: String
    public let detailEn: String

    public init(
        id: String,
        host: String,
        port: UInt16,
        succeeded: Bool,
        latencyMs: Int,
        detailZh: String,
        detailEn: String
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.succeeded = succeeded
        self.latencyMs = latencyMs
        self.detailZh = detailZh
        self.detailEn = detailEn
    }

    public func detail(lang: AppLanguage) -> String { tr(detailZh, detailEn, lang: lang) }
}

public struct FullProbeReport: Sendable {
    public let ranAt: Date
    public let exitLanes: [ExitRegionLaneResult]
    public let siriAudit: SiriDNSAuditResult
    public let endpointProbes: [EndpointTLSProbeResult]
    public let quicProbes: [QUICProbeResult]

    public init(
        ranAt: Date,
        exitLanes: [ExitRegionLaneResult],
        siriAudit: SiriDNSAuditResult,
        endpointProbes: [EndpointTLSProbeResult],
        quicProbes: [QUICProbeResult]
    ) {
        self.ranAt = ranAt
        self.exitLanes = exitLanes
        self.siriAudit = siriAudit
        self.endpointProbes = endpointProbes
        self.quicProbes = quicProbes
    }

    public var mitmDetectedCount: Int {
        endpointProbes.filter(\.isMitMDetected).count
    }

    public var quicAllPassed: Bool {
        !quicProbes.isEmpty && quicProbes.allSatisfy(\.succeeded)
    }

    public var isDirectLaneCN: Bool {
        exitLanes.first(where: { $0.id == "direct" })?.countryCode == "CN"
    }

    public var isGuzzoniCleanTLS: Bool {
        endpointProbes.first(where: { $0.host == "guzzoni.apple.com" })
            .map { $0.reachable && !$0.isMitMDetected } ?? false
    }

    /// Under Surge Enhanced Mode (VIF), `guzzoni.apple.com` CNAMEs (`*.v.aaplimg.com`) may return local Fake-IP
    /// even while DIRECT routing and system proxy bypass keep Siri working cleanly inside Mainland China.
    public var isSiriVIFDirectHealthy: Bool {
        siriAudit.isGuzzoniFakeIP
            && isDirectLaneCN
            && isGuzzoniCleanTLS
            && (!siriAudit.systemProxyEnabled || siriAudit.exceptionsIncludeGuzzoni)
    }

    public var isSiriEffectivelyHealthy: Bool {
        siriAudit.isHealthy || isSiriVIFDirectHealthy
    }

    public var pccTCPFallbackHealthy: Bool {
        let hosts = ["mask-api.icloud.com", "apple-relay.cloudflare.com", "apple-relay.fastly-edge.com"]
        let matched = hosts.compactMap { h in endpointProbes.first(where: { $0.host == h }) }
        return matched.count == hosts.count && matched.allSatisfy { $0.reachable && !$0.isMitMDetected }
    }

    /// True when UDP 443 QUIC is intentionally blocked (e.g., Snell + UDP REJECT),
    /// yet all PCC relays succeed cleanly over HTTPS TCP fallback.
    public var isQUICUsingTCPFallback: Bool {
        !quicAllPassed && pccTCPFallbackHealthy
    }
}

public enum RoutingProbeFormatter {
    private static let countryNames: [String: (flag: String, zh: String, en: String)] = [
        "CN": ("🇨🇳", "中国大陆", "Mainland China"),
        "HK": ("🇭🇰", "中国香港", "Hong Kong"),
        "TW": ("🇹🇼", "中国台湾", "Taiwan"),
        "MO": ("🇲🇴", "中国澳门", "Macau"),
        "US": ("🇺🇸", "美国", "United States"),
        "JP": ("🇯🇵", "日本", "Japan"),
        "SG": ("🇸🇬", "新加坡", "Singapore"),
        "KR": ("🇰🇷", "韩国", "South Korea"),
        "GB": ("🇬🇧", "英国", "United Kingdom"),
        "DE": ("🇩🇪", "德国", "Germany"),
        "FR": ("🇫🇷", "法国", "France"),
        "NL": ("🇳🇱", "荷兰", "Netherlands"),
        "CA": ("🇨🇦", "加拿大", "Canada"),
        "AU": ("🇦🇺", "澳大利亚", "Australia"),
        "IN": ("🇮🇳", "印度", "India"),
        "MY": ("🇲🇾", "马来西亚", "Malaysia"),
        "TH": ("🇹🇭", "泰国", "Thailand"),
        "RU": ("🇷🇺", "俄罗斯", "Russia")
    ]

    private static let coloCities: [String: (zh: String, en: String)] = [
        "LAX": ("洛杉矶", "Los Angeles"),
        "SJC": ("圣何塞", "San Jose"),
        "SFO": ("旧金山", "San Francisco"),
        "SEA": ("西雅图", "Seattle"),
        "PDX": ("波特兰", "Portland"),
        "DEN": ("丹佛", "Denver"),
        "DFW": ("达拉斯", "Dallas"),
        "IAH": ("休斯顿", "Houston"),
        "ORD": ("芝加哥", "Chicago"),
        "IAD": ("阿什本", "Ashburn"),
        "EWR": ("纽瓦克", "Newark"),
        "JFK": ("纽约", "New York"),
        "ATL": ("亚特兰大", "Atlanta"),
        "MIA": ("迈阿密", "Miami"),
        "PHX": ("凤凰城", "Phoenix"),
        "SLC": ("盐湖城", "Salt Lake City"),
        "BOS": ("波士顿", "Boston"),
        "HKG": ("香港", "Hong Kong"),
        "TPE": ("台北", "Taipei"),
        "KHH": ("高雄", "Kaohsiung"),
        "NRT": ("东京成田", "Tokyo"),
        "HND": ("东京羽田", "Tokyo"),
        "KIX": ("大阪", "Osaka"),
        "ICN": ("首尔", "Seoul"),
        "SIN": ("新加坡", "Singapore"),
        "LHR": ("伦敦", "London"),
        "FRA": ("法兰克福", "Frankfurt"),
        "AMS": ("阿姆斯特丹", "Amsterdam"),
        "CDG": ("巴黎", "Paris"),
        "YYZ": ("多伦多", "Toronto"),
        "YVR": ("温哥华", "Vancouver"),
        "SYD": ("悉尼", "Sydney"),
        "SHA": ("上海", "Shanghai"),
        "PVG": ("上海", "Shanghai"),
        "PEK": ("北京", "Beijing"),
        "CAN": ("广州", "Guangzhou"),
        "SZX": ("深圳", "Shenzhen")
    ]

    public static func formatRegionLabel(countryCode: String, coloCode: String, lang: AppLanguage) -> String {
        let cc = countryCode.uppercased()
        let colo = coloCode.uppercased()
        guard !cc.isEmpty else {
            return tr("未知区域", "Unknown Region", lang: lang)
        }
        let flag = countryNames[cc]?.flag ?? unicodeFlag(cc)
        let country = countryNames[cc].map { lang == .en ? $0.en : $0.zh } ?? cc
        if let city = coloCities[colo] {
            let cityName = lang == .en ? city.en : city.zh
            return "\(flag) \(country) · \(cityName) (\(colo))"
        }
        return colo.isEmpty ? "\(flag) \(country)" : "\(flag) \(country) (\(colo))"
    }

    public static func maskIP(_ ip: String, revealFull: Bool) -> String {
        guard !ip.isEmpty else { return "—" }
        if revealFull { return ip }
        if ip.contains(":") {
            let parts = ip.split(separator: ":")
            if parts.count >= 2 { return "\(parts[0]):\(parts[1]):*:*" }
            return ip
        }
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).*.*"
        }
        return ip
    }

    private static func unicodeFlag(_ cc: String) -> String {
        guard cc.count == 2 else { return "" }
        let base: UInt32 = 127397
        var s = ""
        for v in cc.uppercased().unicodeScalars {
            if let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s
    }
}

public final class RoutingProbeEngine: Sendable {
    private static let mitmKeywords: [String] = [
        "surge", "proxyman", "charles", "mitmproxy", "clash", "mihomo",
        "loon", "shadowrocket", "quantumult", "stash", "fiddler", "reqable",
        "portswigger", "burp", "adguard", "whistle", "sniffer"
    ]

    private static let legitimateAppleOrWebPKICAs: [String] = [
        "apple", "digicert", "cloudflare", "globalsign", "entrust",
        "geotrust", "baltimore", "isrg", "let's encrypt", "usertrust",
        "sectigo", "google trust services", "gts root", "amazon",
        "comodo", "ssl.com", "thawte", "verisign"
    ]

    public init() {}

    public func runFullProbe(customProxy: CustomProxyConfig? = nil) async -> FullProbeReport {
        async let lanesTask = probeAllExitLanes(customProxy: customProxy)
        async let siriTask = Task.detached { Self.auditSiriDNSAndProxy() }.value
        async let endpointsTask = probeAllEndpointsWithTLS(customProxy: customProxy)
        async let quicTask = probeQUICConnectivity()

        let (lanes, siri, endpoints, quics) = await (lanesTask, siriTask, endpointsTask, quicTask)
        return FullProbeReport(
            ranAt: Date(),
            exitLanes: lanes,
            siriAudit: siri,
            endpointProbes: endpoints,
            quicProbes: quics
        )
    }

    private static func proxyDictionary(for proxy: CustomProxyConfig) -> [AnyHashable: Any] {
        switch proxy.scheme {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: Int(proxy.port),
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: Int(proxy.port),
                kCFNetworkProxiesSOCKSEnable as String: 0
            ]
        case .socks5:
            return [
                kCFNetworkProxiesHTTPEnable as String: 0,
                kCFNetworkProxiesHTTPSEnable as String: 0,
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: proxy.host,
                kCFNetworkProxiesSOCKSPort as String: Int(proxy.port)
            ]
        }
    }

    // MARK: - 1. Exit Region Lanes

    private struct LaneSpec: Sendable {
        let id: String
        let titleZh: String
        let titleEn: String
        let urls: [String]
        let evaluate: @Sendable (String, AppLanguage) -> (ProbeVerdictLevel, String, String)
    }

    private func probeAllExitLanes(customProxy: CustomProxyConfig?) async -> [ExitRegionLaneResult] {
        let specs: [LaneSpec] = [
            LaneSpec(
                id: "direct",
                titleZh: "国内直连通道 (DIRECT 基准)",
                titleEn: "Domestic Direct Lane (DIRECT Baseline)",
                urls: ["https://www.visa.cn/cdn-cgi/trace", "https://www.cloudflare-cn.com/cdn-cgi/trace"],
                evaluate: { loc, lang in
                    let region = RoutingProbeFormatter.formatRegionLabel(countryCode: loc, coloCode: "", lang: lang)
                    if loc == "CN" {
                        return (
                            .pass,
                            "正常国内直连（未误开全局代理，中文 Siri 安全）",
                            "Healthy domestic DIRECT exit (Mandarin Siri safe)"
                        )
                    }
                    return (
                        .error,
                        "警告：国内流量跑到了 \(region)，疑似开启全局代理，中文 Siri 极易报错",
                        "Domestic traffic exited via \(region)! Global Proxy may break Mandarin Siri."
                    )
                }
            ),
            LaneSpec(
                id: "defaultProxy",
                titleZh: "默认海外代理出口 (PROXY 基准)",
                titleEn: "Default Overseas Proxy Exit",
                urls: ["https://1.1.1.1/cdn-cgi/trace"],
                evaluate: { loc, lang in
                    let region = RoutingProbeFormatter.formatRegionLabel(countryCode: loc, coloCode: "", lang: lang)
                    if loc == "CN" {
                        return (
                            .warn,
                            "当前为国内直连（代理软件是否未开启？）",
                            "Currently direct in CN (is proxy enabled?)"
                        )
                    }
                    if loc == "US" {
                        return (
                            .pass,
                            "默认代理即为美国节点",
                            "Connected to US exit node"
                        )
                    }
                    return (
                        .pass,
                        "默认出口为 \(region)（确保 AI/PCC 规则已单独指美区即可）",
                        "Default exit is \(region) (ensure AI/PCC routes to US)"
                    )
                }
            ),
            LaneSpec(
                id: "openai",
                titleZh: "Siri ChatGPT / OpenAI 实际出口",
                titleEn: "Siri ChatGPT / OpenAI Actual Exit",
                urls: ["https://chatgpt.com/cdn-cgi/trace", "https://platform.openai.com/cdn-cgi/trace"],
                evaluate: { loc, lang in
                    let region = RoutingProbeFormatter.formatRegionLabel(countryCode: loc, coloCode: "", lang: lang)
                    if loc == "US" {
                        return (.pass, "已精准分流至美国节点", "Optimal: Connected via US node")
                    }
                    if ["CN", "HK", "MO", "RU", "BY", "IR", "KP"].contains(loc) {
                        return (
                            .error,
                            "落在受限地区 (\(region))，Siri ChatGPT 会被拒，请分流至美区",
                            "Restricted region (\(loc)) — route OpenAI to US"
                        )
                    }
                    return (
                        .warn,
                        "当前接通 \(region)（可用，建议与 Apple PCC 统一走美区）",
                        "Connected via \(loc) (US recommended to match Apple PCC)"
                    )
                }
            ),
            LaneSpec(
                id: "pccAndClaude",
                titleZh: "Claude / PCC 中继边缘实际出口",
                titleEn: "Claude / Cloudflare Relay Actual Exit",
                urls: ["https://claude.ai/cdn-cgi/trace", "https://cp4.cloudflare.com/cdn-cgi/trace"],
                evaluate: { loc, lang in
                    let region = RoutingProbeFormatter.formatRegionLabel(countryCode: loc, coloCode: "", lang: lang)
                    if loc == "US" {
                        return (.pass, "AI 与 Cloudflare 中继已走美国节点", "Optimal: US relay exit active")
                    }
                    if ["CN", "HK", "MO"].contains(loc) {
                        return (
                            .warn,
                            "当前落在 \(region)，建议将 AI 扩展与 apple-relay.* 指向美区",
                            "Currently \(loc) — route claude.ai & apple-relay.* to US"
                        )
                    }
                    return (.pass, "已接通海外节点 (\(region))", "Connected via \(loc)")
                }
            )
        ]

        return await withTaskGroup(of: (Int, ExitRegionLaneResult).self) { group in
            for (idx, spec) in specs.enumerated() {
                group.addTask {
                    let result = await self.fetchTraceLane(spec: spec, customProxy: customProxy)
                    return (idx, result)
                }
            }
            var items: [(Int, ExitRegionLaneResult)] = []
            for await pair in group {
                items.append(pair)
            }
            return items.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func fetchTraceLane(spec: LaneSpec, customProxy: CustomProxyConfig?) async -> ExitRegionLaneResult {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6.0
        cfg.timeoutIntervalForResource = 6.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let customProxy, spec.id != "direct" {
            cfg.connectionProxyDictionary = Self.proxyDictionary(for: customProxy)
        }
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        for rawURL in spec.urls {
            guard let url = URL(string: "\(rawURL)?_al=\(Int(Date().timeIntervalSince1970 * 1000))") else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let t0 = DispatchTime.now().uptimeNanoseconds

            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                      let body = String(data: data, encoding: .utf8) else {
                    continue
                }
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                let parsed = Self.parseCloudflareTrace(body)
                let loc = (parsed["loc"] ?? "").uppercased()
                let colo = (parsed["colo"] ?? "").uppercased()
                let ip = parsed["ip"] ?? ""
                let host = parsed["h"] ?? (url.host ?? rawURL)
                if !loc.isEmpty || !ip.isEmpty {
                    let (levelZh, msgZh, _) = spec.evaluate(loc, .zhHans)
                    let (_, _, msgEn) = spec.evaluate(loc, .en)
                    return ExitRegionLaneResult(
                        id: spec.id,
                        titleZh: spec.titleZh,
                        titleEn: spec.titleEn,
                        reachable: true,
                        latencyMs: elapsedMs,
                        countryCode: loc,
                        coloCode: colo,
                        ipAddress: ip,
                        probedHost: host,
                        verdictLevel: levelZh,
                        verdictZh: msgZh,
                        verdictEn: msgEn
                    )
                }
            } catch {
                continue
            }
        }

        return ExitRegionLaneResult(
            id: spec.id,
            titleZh: spec.titleZh,
            titleEn: spec.titleEn,
            reachable: false,
            latencyMs: 0,
            countryCode: "",
            coloCode: "",
            ipAddress: "",
            probedHost: spec.urls.first ?? "",
            verdictLevel: .error,
            verdictZh: "无法接通或被拦截，请检查当前代理节点是否在线",
            verdictEn: "Unreachable or timed out; check active proxy node"
        )
    }

    public static func parseCloudflareTrace(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in body.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                result[key] = val
            }
        }
        return result
    }

    // MARK: - 2. Siri Real-IP & System Proxy Audit

    public static func auditSiriDNSAndProxy() -> SiriDNSAuditResult {
        let guzzoniIPs = DNSFakeIPMapper.resolveHostIPs("guzzoni.apple.com")
        let siriIPs = DNSFakeIPMapper.resolveHostIPs("siri.apple.com")
        let guzzoniCName = DNSFakeIPMapper.resolveCanonicalName("guzzoni.apple.com")
        let isGuzzoniFake = guzzoniIPs.contains { LLMEndpointCatalog.isFakeIP($0) }
        let isSiriFake = siriIPs.contains { LLMEndpointCatalog.isFakeIP($0) }
        let proxy = SystemProxyInfo.current()
        let proxyOn = proxy.httpEnabled || proxy.httpsEnabled || proxy.socksEnabled
        let hasException = proxy.exceptionsList.contains {
            let l = $0.lowercased()
            return l == "guzzoni.apple.com" || l == "*.guzzoni.apple.com" || l == "*.apple.com"
        }

        return SiriDNSAuditResult(
            guzzoniResolvedIPs: guzzoniIPs,
            siriResolvedIPs: siriIPs,
            isGuzzoniFakeIP: isGuzzoniFake,
            isSiriFakeIP: isSiriFake,
            systemProxyEnabled: proxyOn,
            exceptionsIncludeGuzzoni: hasException,
            guzzoniCanonicalName: guzzoniCName
        )
    }

    // MARK: - 3. TLS Certificate Chain Anti-MitM Inspector

    private struct TargetEndpointSpec: Sendable {
        let host: String
        let url: String
        let roleZh: String
        let roleEn: String
        let expectDirect: Bool
        let pinningSensitive: Bool
    }

    private static let tlsTargetSpecs: [TargetEndpointSpec] = [
        TargetEndpointSpec(
            host: "guzzoni.apple.com",
            url: "https://guzzoni.apple.com",
            roleZh: "中文 Siri 与来电筛选核心（期望：国内直连 · 禁 MitM）",
            roleEn: "Mandarin Siri Core (Expect: DIRECT · No MitM)",
            expectDirect: true,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "gspe1-ssl.ls.apple.com",
            url: "https://gspe1-ssl.ls.apple.com/pep/gcc",
            roleZh: "区域定位准入校验（期望：美区代理 · 强证书固定禁 MitM）",
            roleEn: "Geo Eligibility Check (Expect: US Proxy · Strict Pinning)",
            expectDirect: false,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "api.smoot.apple.com",
            url: "https://api.smoot.apple.com",
            roleZh: "Spotlight / Siri 搜索建议（期望：直连 · 禁旧版 MitM）",
            roleEn: "Spotlight / Siri Search (Expect: DIRECT · No MitM)",
            expectDirect: true,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "inference.issuer.apple.com",
            url: "https://inference.issuer.apple.com",
            roleZh: "PCC 盲签名推理令牌签发（期望：美区代理 · 禁 MitM）",
            roleEn: "PCC Blind-Signing Token Issuer (Expect: US Proxy · No MitM)",
            expectDirect: false,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "mask-api.icloud.com",
            url: "https://mask-api.icloud.com",
            roleZh: "PCC / 专用代理匿名令牌签发（期望：美区代理）",
            roleEn: "PCC Blind Token Mask API (Expect: US Proxy)",
            expectDirect: false,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "ropes.apple.com",
            url: "https://ropes.apple.com",
            roleZh: "PCC ROPES 隐私推理网关（期望：美区代理）",
            roleEn: "PCC ROPES Inference Gateway (Expect: US Proxy)",
            expectDirect: false,
            pinningSensitive: true
        ),
        TargetEndpointSpec(
            host: "apple-relay.cloudflare.com",
            url: "https://apple-relay.cloudflare.com",
            roleZh: "PCC Cloudflare OHTTP 边缘中继（期望：美区代理）",
            roleEn: "PCC Cloudflare OHTTP Relay (Expect: US Proxy)",
            expectDirect: false,
            pinningSensitive: false
        ),
        TargetEndpointSpec(
            host: "apple-relay.fastly-edge.com",
            url: "https://apple-relay.fastly-edge.com",
            roleZh: "PCC Fastly OHTTP 边缘中继（期望：美区代理）",
            roleEn: "PCC Fastly OHTTP Relay (Expect: US Proxy)",
            expectDirect: false,
            pinningSensitive: false
        ),
        TargetEndpointSpec(
            host: "lens.google.com",
            url: "https://lens.google.com",
            roleZh: "视觉智能 Google 识图（期望：美区代理）",
            roleEn: "Visual Intelligence Google Lens (Expect: US Proxy)",
            expectDirect: false,
            pinningSensitive: false
        )
    ]

    public static let tlsProbeTargetHosts: [String] = tlsTargetSpecs.map(\.host)

    private final class TLSInspectorDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, Sendable {
        private struct State: Sendable {
            var capturedByTaskID: [Int: CertificateChainAudit] = [:]
            var statusByTaskID: [Int: Int] = [:]
            var mostRecent: CertificateChainAudit?
            var mostRecentStatus: Int?
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func captured(for taskID: Int?) -> CertificateChainAudit? {
            state.withLock { s in
                if let taskID, let exact = s.capturedByTaskID[taskID] {
                    return exact
                }
                return s.mostRecent
            }
        }

        func statusCode(for taskID: Int?) -> Int? {
            state.withLock { s in
                if let taskID, let code = s.statusByTaskID[taskID] {
                    return code
                }
                return s.mostRecentStatus
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
                let info = RoutingProbeEngine.inspectCertificateChain(chain, host: challenge.protectionSpace.host)
                state.withLock { s in
                    s.capturedByTaskID[task.taskIdentifier] = info
                    s.mostRecent = info
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
        ) {
            if let http = response as? HTTPURLResponse {
                state.withLock { s in
                    s.statusByTaskID[dataTask.taskIdentifier] = http.statusCode
                    s.mostRecentStatus = http.statusCode
                }
            }
            completionHandler(.cancel)
        }
    }

    private final class ProbeResumeGate: Sendable {
        private struct State: Sendable {
            var resumed = false
            var storedTaskID: Int?
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func tryClaim() -> Bool {
            state.withLock { s in
                guard !s.resumed else { return false }
                s.resumed = true
                return true
            }
        }

        func setTaskIdentifier(_ id: Int) {
            state.withLock { $0.storedTaskID = id }
        }

        func getTaskIdentifier() -> Int? {
            state.withLock { $0.storedTaskID }
        }
    }

    public static func auditCertificateChain(_ chain: [SecCertificate], host: String) -> CertificateChainAudit {
        guard !chain.isEmpty else {
            return CertificateChainAudit(leafSubject: nil, rootSubject: nil, issuerSummary: nil, isMitMDetected: false, mitmReason: nil)
        }

        let summaries: [String] = chain.map { (SecCertificateCopySubjectSummary($0) as String?) ?? "" }
        let leafSubject = summaries.first
        let rootSubject = summaries.last
        let leafIssuer = extractCertificateIssuer(chain[0])
        let issuerSummary = chain.count >= 2
            ? summaries[1]
            : (leafIssuer.commonName ?? leafIssuer.fullSummary ?? rootSubject)

        // Check every cert summary and issuer fields for known proxy MitM root CAs
        var mitmHit: String? = nil
        for cert in chain {
            let subject = (SecCertificateCopySubjectSummary(cert) as String? ?? "").lowercased()
            let valuesText = extractCertificateTextTokens(cert).lowercased()
            for kw in mitmKeywords where subject.contains(kw) || valuesText.contains(kw) {
                mitmHit = "Matched proxy MitM CA token '\(kw)' in certificate chain"
                break
            }
            if mitmHit != nil { break }
        }

        // For Apple domains, if root/issuer is NOT a legitimate WebPKI / Apple CA, flag anomaly.
        // Never use the leaf's subject CN (e.g. "ropes.apple.com") as an issuer check when chain.count == 1.
        if mitmHit == nil && (host.hasSuffix(".apple.com") || host.hasSuffix(".icloud.com")) {
            let issuerCheck: String
            if chain.count >= 2 {
                issuerCheck = ((rootSubject ?? "") + " " + (issuerSummary ?? "")).lowercased()
            } else {
                issuerCheck = (leafIssuer.fullSummary ?? leafIssuer.commonName ?? "").lowercased()
            }

            if !issuerCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let looksLegit = legitimateAppleOrWebPKICAs.contains { issuerCheck.contains($0) }
                if !looksLegit {
                    let displayIssuer = chain.count >= 2
                        ? (rootSubject ?? issuerSummary ?? "unknown")
                        : (leafIssuer.commonName ?? leafIssuer.fullSummary ?? "unknown")
                    mitmHit = "Unexpected non-Apple/WebPKI issuer '\(displayIssuer)' for Apple endpoint"
                }
            }
        }

        return CertificateChainAudit(
            leafSubject: leafSubject,
            rootSubject: rootSubject,
            issuerSummary: issuerSummary,
            isMitMDetected: mitmHit != nil,
            mitmReason: mitmHit
        )
    }

    private static func extractCertificateIssuer(_ cert: SecCertificate) -> (commonName: String?, fullSummary: String?) {
        let keys = [kSecOIDX509V1IssuerName] as CFArray
        guard let values = SecCertificateCopyValues(cert, keys, nil) as? [CFString: Any],
              let section = values[kSecOIDX509V1IssuerName] as? [String: Any],
              let entries = section[kSecPropertyKeyValue as String] as? [[String: Any]] else {
            return (nil, nil)
        }

        let cnOID = kSecOIDCommonName as String
        let labelKey = kSecPropertyKeyLabel as String
        let valueKey = kSecPropertyKeyValue as String

        var commonName: String?
        var parts: [String] = []
        for entry in entries {
            guard let val = entry[valueKey] as? String, !val.isEmpty else { continue }
            parts.append(val)
            if let label = entry[labelKey] as? String, label == cnOID, commonName == nil {
                commonName = val
            }
        }

        let fullSummary = parts.isEmpty ? nil : parts.joined(separator: " / ")
        return (commonName, fullSummary)
    }

    private static func inspectCertificateChain(_ chain: [SecCertificate], host: String) -> CertificateChainAudit {
        auditCertificateChain(chain, host: host)
    }

    private static func extractCertificateTextTokens(_ cert: SecCertificate) -> String {
        guard let values = SecCertificateCopyValues(cert, nil, nil) as? [CFString: Any] else {
            return ""
        }
        var tokens: [String] = []
        func collect(_ obj: Any) {
            if let s = obj as? String {
                tokens.append(s)
            } else if let arr = obj as? [Any] {
                for item in arr { collect(item) }
            } else if let dict = obj as? [String: Any] {
                for v in dict.values { collect(v) }
            }
        }
        for val in values.values { collect(val) }
        return tokens.joined(separator: " ")
    }

    private func probeAllEndpointsWithTLS(customProxy: CustomProxyConfig?) async -> [EndpointTLSProbeResult] {
        let targets = Self.tlsTargetSpecs

        return await withTaskGroup(of: (Int, EndpointTLSProbeResult).self) { group in
            for (idx, target) in targets.enumerated() {
                group.addTask {
                    let res = await self.probeSingleEndpoint(target: target, customProxy: customProxy)
                    return (idx, res)
                }
            }
            var out: [(Int, EndpointTLSProbeResult)] = []
            for await item in group {
                out.append(item)
            }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func probeSingleEndpoint(target: TargetEndpointSpec, customProxy: CustomProxyConfig?) async -> EndpointTLSProbeResult {
        guard let url = URL(string: target.url) else {
            return EndpointTLSProbeResult(
                id: target.host, host: target.host, roleZh: target.roleZh, roleEn: target.roleEn,
                expectDirect: target.expectDirect, pinningSensitive: target.pinningSensitive,
                reachable: false, httpStatus: nil, latencyMs: 0, leafSubject: nil, issuerSummary: nil,
                rootSubject: nil, isMitMDetected: false, mitmReason: nil, errorDescription: "Invalid URL"
            )
        }

        let delegate = TLSInspectorDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6.0
        cfg.timeoutIntervalForResource = 6.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let customProxy, !target.expectDirect {
            cfg.connectionProxyDictionary = Self.proxyDictionary(for: customProxy)
        }

        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let t0 = DispatchTime.now().uptimeNanoseconds

        return await withCheckedContinuation { continuation in
            let gate = ProbeResumeGate()
            @Sendable func complete(_ res: EndpointTLSProbeResult) {
                guard gate.tryClaim() else { return }
                continuation.resume(returning: res)
            }

            let task = session.dataTask(with: request) { @Sendable _, response, error in
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
                let taskID = gate.getTaskIdentifier()
                let captured = delegate.captured(for: taskID)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? delegate.statusCode(for: taskID)
                let isCleanTLS = (captured != nil) && !(captured?.isMitMDetected ?? false)
                let isReachable = (statusCode != nil) || isCleanTLS

                complete(EndpointTLSProbeResult(
                    id: target.host,
                    host: target.host,
                    roleZh: target.roleZh,
                    roleEn: target.roleEn,
                    expectDirect: target.expectDirect,
                    pinningSensitive: target.pinningSensitive,
                    reachable: isReachable,
                    httpStatus: statusCode,
                    latencyMs: elapsedMs,
                    leafSubject: captured?.leafSubject,
                    issuerSummary: captured?.issuerSummary,
                    rootSubject: captured?.rootSubject,
                    isMitMDetected: captured?.isMitMDetected ?? false,
                    mitmReason: captured?.mitmReason,
                    errorDescription: isReachable ? nil : (error?.localizedDescription ?? "Connection failed")
                ))
            }
            gate.setTaskIdentifier(task.taskIdentifier)
            task.resume()
        }
    }

    // MARK: - 4. Native UDP 443 / QUIC (h3) Handshake Probe

    private func probeQUICConnectivity() async -> [QUICProbeResult] {
        let hosts = ["cp4.cloudflare.com", "apple-relay.fastly-edge.com"]
        return await withTaskGroup(of: (Int, QUICProbeResult).self) { group in
            for (idx, host) in hosts.enumerated() {
                group.addTask {
                    let res = await self.probeSingleQUIC(host: host, port: 443)
                    return (idx, res)
                }
            }
            var out: [(Int, QUICProbeResult)] = []
            for await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func probeSingleQUIC(host: String, port: UInt16) async -> QUICProbeResult {
        await withCheckedContinuation { continuation in
            let gate = ProbeResumeGate()

            let quicOptions = NWProtocolQUIC.Options(alpn: ["h3"])
            let params = NWParameters(quic: quicOptions)
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .https
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
            let startNs = DispatchTime.now().uptimeNanoseconds

            @Sendable func finish(succeeded: Bool, detailZh: String, detailEn: String) {
                guard gate.tryClaim() else { return }
                let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
                conn.stateUpdateHandler = nil
                conn.cancel()
                continuation.resume(returning: QUICProbeResult(
                    id: "\(host):\(port)",
                    host: host,
                    port: port,
                    succeeded: succeeded,
                    latencyMs: elapsedMs,
                    detailZh: detailZh,
                    detailEn: detailEn
                ))
            }

            conn.stateUpdateHandler = { @Sendable state in
                switch state {
                case .ready:
                    finish(
                        succeeded: true,
                        detailZh: "UDP 443 QUIC (HTTP/3) 握手畅通",
                        detailEn: "UDP 443 QUIC (HTTP/3) handshake succeeded"
                    )
                case .failed(let err):
                    finish(
                        succeeded: false,
                        detailZh: "QUIC 握手失败（\(err.localizedDescription)）— 检查节点 UDP 443 或 QUIC-BLOCK",
                        detailEn: "QUIC handshake failed (\(err.localizedDescription)) — check node UDP 443 / QUIC-BLOCK"
                    )
                case .cancelled:
                    finish(
                        succeeded: false,
                        detailZh: "QUIC 握手被取消或超时",
                        detailEn: "QUIC handshake cancelled or timed out"
                    )
                default:
                    break
                }
            }

            let queue = DispatchQueue(label: "com.kianuni.applelens.quic.\(host)")
            conn.start(queue: queue)

            queue.asyncAfter(deadline: .now() + 2.8) { @Sendable in
                finish(
                    succeeded: false,
                    detailZh: "UDP 443 QUIC 超时 (2.8s) — 若使用 Snell / UDP REJECT 策略，系统会自动回退 TCP H2",
                    detailEn: "UDP 443 QUIC timed out (2.8s) — expected under Snell / UDP-REJECT (uses TCP H2 fallback)"
                )
            }
        }
    }
}
