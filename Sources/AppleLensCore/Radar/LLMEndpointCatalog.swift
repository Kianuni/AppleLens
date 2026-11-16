import Darwin
import Foundation
import os

public enum EndpointCategory: String, Codable, Sendable {
    case applePCC
    case internationalLLM
    case domesticLLM

    public func label(lang: AppLanguage) -> String {
        switch self {
        case .applePCC:
            return tr("Apple PCC 私有云", "Apple PCC", lang: lang)
        case .internationalLLM:
            return tr("海外大模型 API", "International LLM", lang: lang)
        case .domesticLLM:
            return tr("国产大模型 API", "Domestic LLM", lang: lang)
        }
    }
}

public enum EndpointMatchConfidence: String, Codable, Sendable {
    case exactFakeIP
    case dedicatedIP
    case resolvedDomainKnownClient
    case systemProxyKnownClient

    public func label(lang: AppLanguage) -> String {
        switch self {
        case .exactFakeIP:
            return tr("Fake-IP 精确命中", "Exact Fake-IP", lang: lang)
        case .dedicatedIP:
            return tr("专用 IP 段命中", "Dedicated IP", lang: lang)
        case .resolvedDomainKnownClient:
            return tr("域名 IP + 客户端命中", "Resolved IP + Client", lang: lang)
        case .systemProxyKnownClient:
            return tr("系统代理端口直连", "Via System Proxy", lang: lang)
        }
    }
}

public struct LLMProviderSpec: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let nameZh: String
    public let nameEn: String
    public let category: EndpointCategory
    public let domains: [String]
    public let dedicatedIPv4Prefixes: [String]
    public let knownClientBundleIDs: [String]
    public let knownIOSProcessNames: [String]

    public init(
        id: String,
        nameZh: String,
        nameEn: String,
        category: EndpointCategory,
        domains: [String],
        dedicatedIPv4Prefixes: [String] = [],
        knownClientBundleIDs: [String] = [],
        knownIOSProcessNames: [String] = []
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.category = category
        self.domains = domains
        self.dedicatedIPv4Prefixes = dedicatedIPv4Prefixes
        self.knownClientBundleIDs = knownClientBundleIDs
        self.knownIOSProcessNames = knownIOSProcessNames
    }

    public func displayName(lang: AppLanguage) -> String {
        tr(nameZh, nameEn, lang: lang)
    }
}

public struct EndpointMatchResult: Sendable, Hashable {
    public let provider: LLMProviderSpec
    public let matchedDomain: String
    public let confidence: EndpointMatchConfidence
    public let isFakeIP: Bool
}

public enum LLMEndpointCatalog {
    public static let providers: [LLMProviderSpec] = [
        // Apple Private Cloud Compute (PCC)
        LLMProviderSpec(
            id: "apple-pcc",
            nameZh: "Apple PCC 私有云",
            nameEn: "Apple Private Cloud Compute",
            category: .applePCC,
            domains: [
                "inference.issuer.apple.com",
                "compute.issuer.apple.com",
                "premium-inference.issuer.apple.com",
                "creator-studio.issuer.apple.com",
                "ropes.apple.com",
                "mask-api.icloud.com",
                "mask.icloud.com",
                "mask-h2.icloud.com",
                "ss-cleanup-proxy-prod.us-east-1m.app.apple.com",
                "apple-relay.apple.com",
                "apple-relay.cloudflare.com",
                "apple-relay.fastly-edge.com",
                "apple-relay.akamaized.net"
            ]
        ),

        // International LLM Providers
        LLMProviderSpec(
            id: "openai",
            nameZh: "OpenAI / ChatGPT",
            nameEn: "OpenAI / ChatGPT",
            category: .internationalLLM,
            domains: [
                "api.openai.com",
                "chatgpt.com",
                "chat.com",
                "platform.openai.com"
            ],
            knownClientBundleIDs: [
                "com.openai.chat",
                "com.openai.codex",
                "com.openai.sora"
            ],
            knownIOSProcessNames: [
                "ChatGPT",
                "Sora"
            ]
        ),
        LLMProviderSpec(
            id: "anthropic",
            nameZh: "Anthropic / Claude",
            nameEn: "Anthropic / Claude",
            category: .internationalLLM,
            domains: [
                "api.anthropic.com",
                "claude.ai",
                "claude.com"
            ],
            dedicatedIPv4Prefixes: [
                "160.79.104."
            ],
            knownClientBundleIDs: [
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude"
            ],
            knownIOSProcessNames: [
                "Claude"
            ]
        ),
        LLMProviderSpec(
            id: "gemini",
            nameZh: "Google Gemini",
            nameEn: "Google Gemini",
            category: .internationalLLM,
            domains: [
                "generativelanguage.googleapis.com",
                "daily-cloudcode-pa.googleapis.com",
                "cloudcode-pa.googleapis.com",
                "aistudio.google.com",
                "gemini.google.com",
                "proactivebackend-pa.googleapis.com",
                "alkalimakersuite-pa.clients6.google.com"
            ],
            knownClientBundleIDs: [
                "com.google.Gemini",
                "com.google.gemini",
                "com.google.OPA"
            ],
            knownIOSProcessNames: [
                "Gemini"
            ]
        ),
        LLMProviderSpec(
            id: "openrouter",
            nameZh: "OpenRouter",
            nameEn: "OpenRouter",
            category: .internationalLLM,
            domains: [
                "openrouter.ai",
                "api.openrouter.ai"
            ]
        ),
        LLMProviderSpec(
            id: "xai",
            nameZh: "xAI / Grok",
            nameEn: "xAI / Grok",
            category: .internationalLLM,
            domains: [
                "api.x.ai",
                "grok.com"
            ],
            knownClientBundleIDs: [
                "ai.x.GrokApp",
                "com.x.grok"
            ],
            knownIOSProcessNames: [
                "Grok",
                "GrokApp"
            ]
        ),
        LLMProviderSpec(
            id: "groq",
            nameZh: "Groq",
            nameEn: "Groq",
            category: .internationalLLM,
            domains: [
                "api.groq.com"
            ]
        ),
        LLMProviderSpec(
            id: "perplexity",
            nameZh: "Perplexity",
            nameEn: "Perplexity",
            category: .internationalLLM,
            domains: [
                "api.perplexity.ai",
                "www.perplexity.ai"
            ],
            knownClientBundleIDs: [
                "ai.perplexity.mac",
                "ai.perplexity.app"
            ],
            knownIOSProcessNames: [
                "Perplexity"
            ]
        ),
        LLMProviderSpec(
            id: "mistral",
            nameZh: "Mistral AI",
            nameEn: "Mistral AI",
            category: .internationalLLM,
            domains: [
                "api.mistral.ai"
            ]
        ),

        // Domestic Chinese LLM Providers
        LLMProviderSpec(
            id: "deepseek",
            nameZh: "DeepSeek 深度求索",
            nameEn: "DeepSeek",
            category: .domesticLLM,
            domains: [
                "api.deepseek.com",
                "chat.deepseek.com"
            ],
            knownClientBundleIDs: [
                "com.deepseek.chat"
            ],
            knownIOSProcessNames: [
                "DeepSeek"
            ]
        ),
        LLMProviderSpec(
            id: "doubao",
            nameZh: "豆包 / 火山方舟",
            nameEn: "Doubao / Volcengine Ark",
            category: .domesticLLM,
            domains: [
                "ark.cn-beijing.volces.com",
                "ark.cn-shanghai.volces.com",
                "www.doubao.com",
                "api.doubao.com"
            ],
            knownClientBundleIDs: [
                "com.bytedance.doubao",
                "com.larus.nova",
                "com.bot.doubao"
            ],
            knownIOSProcessNames: [
                "Doubao",
                "Nova",
                "Grace"
            ]
        ),
        LLMProviderSpec(
            id: "qwen",
            nameZh: "通义千问 / 百炼",
            nameEn: "Qwen / DashScope",
            category: .domesticLLM,
            domains: [
                "dashscope.aliyuncs.com",
                "dashscope-intl.aliyuncs.com",
                "tongyi.aliyun.com"
            ],
            knownClientBundleIDs: [
                "com.aliyun.tongyi"
            ],
            knownIOSProcessNames: [
                "Tongyi"
            ]
        ),
        LLMProviderSpec(
            id: "kimi",
            nameZh: "Kimi / 月之暗面",
            nameEn: "Kimi / Moonshot",
            category: .domesticLLM,
            domains: [
                "api.moonshot.cn",
                "api.moonshot.ai",
                "kimi.moonshot.cn"
            ],
            knownClientBundleIDs: [
                "com.moonshot.kimichat"
            ],
            knownIOSProcessNames: [
                "Kimi",
                "Kimichat"
            ]
        ),
        LLMProviderSpec(
            id: "zhipu",
            nameZh: "智谱清言 / BigModel",
            nameEn: "Zhipu / BigModel",
            category: .domesticLLM,
            domains: [
                "open.bigmodel.cn",
                "chatglm.cn"
            ],
            knownClientBundleIDs: [
                "com.zhipuai.qingyan"
            ],
            knownIOSProcessNames: [
                "Qingyan"
            ]
        ),
        LLMProviderSpec(
            id: "minimax",
            nameZh: "MiniMax",
            nameEn: "MiniMax",
            category: .domesticLLM,
            domains: [
                "api.minimaxi.chat",
                "api.minimax.chat",
                "api.minimaxi.com"
            ]
        ),
        LLMProviderSpec(
            id: "siliconflow",
            nameZh: "硅基流动 SiliconFlow",
            nameEn: "SiliconFlow",
            category: .domesticLLM,
            domains: [
                "api.siliconflow.cn",
                "api.siliconflow.com"
            ]
        )
    ]

    public static let knownAIMultiClientBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.cherrystudio.app",
        "xyz.chatboxapp.app",
        "com.google.antigravity",
        "dev.zed.Zed",
        "com.raycast.macos",
        "dev.warp.Warp-Stable",
        "com.openai.chat",
        "com.openai.codex",
        "com.anthropic.claudefordesktop",
        "ai.perplexity.mac",
        "com.bytedance.doubao",
        "com.larus.nova",
        "com.trae.app",
        "com.exafunction.windsurf"
    ]

    public static let knownAICliExecutableNames: Set<String> = [
        "language_server",
        "claude",
        "codex",
        "cursor",
        "antigravity",
        "cherry studio",
        "chatbox",
        "python",
        "python3",
        "node",
        "bun",
        "deno",
        "curl",
        "ollama"
    ]

    public static let knownApplePCCDaemons: Set<String> = [
        "privatecloudcomputed",
        "generativeexperiencesd",
        "assistantd",
        "modelmanagerd",
        "photos",
        "nsurlsessiond",
        "cloudd"
    ]

    public static let excludedProxyExecutableNames: Set<String> = [
        "surge",
        "surge-cli",
        "com.nssurge.surge-mac.ne",
        "clash",
        "clashx",
        "clashx pro",
        "clash verge",
        "clash-verge",
        "mihomo",
        "stash",
        "loon",
        "shadowrocket",
        "quantumult",
        "quantumult x",
        "sing-box",
        "xray",
        "v2ray",
        "privoxy",
        "tor",
        "hysteria",
        "tuic",
        "nekoray",
        "v2rayu",
        "applelens",
        "usbmuxd"
    ]

    public static let excludedProxyBundlePrefixes: [String] = [
        "com.nssurge.",
        "com.metacubex.",
        "com.clash.",
        "ws.stash.",
        "com.loon.",
        "com.liguangming.Shadowrocket",
        "com.kianuni.AppleLens"
    ]

    public static func isFakeIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              let first = UInt8(parts[0]),
              let second = UInt8(parts[1]) else {
            return false
        }
        return first == 198 && (second == 18 || second == 19)
    }

    public static func isSharedCloudflareAnycast(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              let a = UInt8(parts[0]),
              let b = UInt8(parts[1]) else {
            return false
        }
        if a == 104 && (16...31).contains(b) { return true }
        if a == 172 && (64...71).contains(b) { return true }
        if a == 162 && b == 159 { return true }
        if a == 188 && b == 114 { return true }
        return false
    }

    public static func isExcludedProxyProcess(executableName: String, bundleID: String?, bundlePath: String?) -> Bool {
        let lowerExec = executableName.lowercased()
        if excludedProxyExecutableNames.contains(lowerExec) {
            return true
        }
        if lowerExec.contains("surge") || lowerExec.contains("mihomo") || lowerExec.contains("clash") {
            return true
        }
        if let bundleID = bundleID?.lowercased() {
            for prefix in excludedProxyBundlePrefixes where bundleID.hasPrefix(prefix.lowercased()) {
                return true
            }
        }
        if let bundlePath = bundlePath?.lowercased() {
            if bundlePath.contains("surge.app") || bundlePath.contains("clash") || bundlePath.contains("stash.app") || bundlePath.contains("applelens.app") {
                return true
            }
        }
        return false
    }

    public static func isKnownAIClient(executableName: String, bundleID: String?) -> Bool {
        if let bundleID, knownAIMultiClientBundleIDs.contains(bundleID) {
            return true
        }
        let lower = executableName.lowercased()
        if knownAICliExecutablesOrAppsContains(lower) {
            return true
        }
        return false
    }

    private static func knownAICliExecutablesOrAppsContains(_ lowerExec: String) -> Bool {
        if knownAICliExecutableNames.contains(lowerExec) {
            return true
        }
        return lowerExec.hasPrefix("python3.") || lowerExec.hasPrefix("node")
    }

    private struct DynamicIOSState: Sendable {
        var bundleMap: [String: LLMProviderSpec] = [:]
        var execMap: [String: LLMProviderSpec] = [:]
        var keywords: Set<String> = []
    }

    private static let dynamicIOSState = OSAllocatedUnfairLock(initialState: DynamicIOSState())

    private static let aiDiscoveryTokens: [String] = [
        "claude", "anthropic", "openai", "chatgpt", "sora", "gemini",
        "grok", "deepseek", "doubao", "kimi", "kimichat", "moonshot",
        "tongyi", "qwen", "qingyan", "zhipu", "perplexity", "yuanbao",
        "poe", "copilot", "coze", "minimax", "bailian"
    ]

    /// Registers AI apps discovered via USB `installation_proxy` so localized or non-obvious executable names (e.g. `Grace`) match automatically.
    public static func registerDynamicIOSApps(_ entries: [(bundleID: String, executable: String, displayName: String)]) {
        dynamicIOSState.withLock { state in
            for entry in entries {
                let bundle = entry.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                let exec = entry.executable.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundle.isEmpty, !exec.isEmpty else { continue }

                let combined = "\(bundle) \(exec) \(name)".lowercased()
                let isKnownBuiltIn = providers.contains { spec in
                    spec.knownClientBundleIDs.contains { $0.lowercased() == bundle.lowercased() }
                        || spec.knownIOSProcessNames.contains { $0.lowercased() == exec.lowercased() }
                }
                let matchesToken = aiDiscoveryTokens.contains { combined.contains($0) }
                guard isKnownBuiltIn || matchesToken else { continue }

                let spec: LLMProviderSpec
                if let existing = providers.first(where: { s in
                    s.knownClientBundleIDs.contains { $0.lowercased() == bundle.lowercased() }
                        || s.knownIOSProcessNames.contains { $0.lowercased() == exec.lowercased() }
                }) {
                    spec = existing
                } else {
                    let label = name.isEmpty ? exec : name
                    spec = LLMProviderSpec(
                        id: "ios.\(bundle.lowercased())",
                        nameZh: label,
                        nameEn: label,
                        category: .internationalLLM,
                        domains: [],
                        knownClientBundleIDs: [bundle],
                        knownIOSProcessNames: [exec]
                    )
                }

                state.bundleMap[bundle.lowercased()] = spec
                state.execMap[exec.lowercased()] = spec
                state.keywords.insert(exec.lowercased())
                state.keywords.insert(bundle.lowercased())
            }
        }
    }

    public static func dynamicIOSExecutableKeywords() -> [String] {
        dynamicIOSState.withLock { Array($0.keywords) }
    }

    /// Normalizes syslog tokens such as `Claude(CFNetwork)` to `Claude`.
    public static func normalizeProcessName(_ raw: String) -> String {
        if let paren = raw.firstIndex(of: "(") {
            let trimmed = raw[..<paren].trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func matchIOSApp(bundleID: String?, processName: String) -> LLMProviderSpec? {
        if let bundleID, !bundleID.isEmpty {
            let lowerBundle = bundleID.lowercased()
            if let exact = providers.first(where: { spec in
                spec.knownClientBundleIDs.contains {
                    let known = $0.lowercased()
                    return lowerBundle == known || lowerBundle.hasPrefix(known + ".")
                }
            }) {
                return exact
            }
            if let dynamic = dynamicIOSState.withLock({ state in
                state.bundleMap[lowerBundle]
                    ?? state.bundleMap.first(where: { lowerBundle.hasPrefix($0.key + ".") })?.value
            }) {
                return dynamic
            }
        }

        let cleanLower = normalizeProcessName(processName).lowercased()
        guard !cleanLower.isEmpty else { return nil }
        if let builtIn = providers.first(where: { spec in
            spec.knownIOSProcessNames.contains { $0.lowercased() == cleanLower }
        }) {
            return builtIn
        }
        return dynamicIOSState.withLock { $0.execMap[cleanLower] }
    }

    static func decodeNullTerminatedCString(_ buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

public final class DNSFakeIPMapper: Sendable {
    public struct ResolvedRecord: Sendable, Hashable {
        public let provider: LLMProviderSpec
        public let domain: String
    }

    private struct State: Sendable {
        var ipToRecords: [String: [ResolvedRecord]] = [:]
        var lastRefreshedAt: Date?
    }

    private static let dnsResolutionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.kianuni.AppleLens.dnsResolver"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 8
        return queue
    }()

    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public var lastRefreshDate: Date? {
        stateLock.withLock { $0.lastRefreshedAt }
    }

    public var mappedEntryCount: Int {
        stateLock.withLock { $0.ipToRecords.count }
    }

    /// Resolves all catalogued domains concurrently on a bounded `OperationQueue` via POSIX `getaddrinfo` (zero cooperative pool starvation).
    public func refreshMappings() async {
        let pairs: [(LLMProviderSpec, String)] = LLMEndpointCatalog.providers.flatMap { provider in
            provider.domains.map { (provider, $0) }
        }

        let resolved: [(String, ResolvedRecord)] = await withCheckedContinuation { continuation in
            guard !pairs.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            final class BatchCollector: Sendable {
                private struct CollectorState: Sendable {
                    var remaining: Int
                    var collected: [(String, ResolvedRecord)] = []
                }

                private let lock: OSAllocatedUnfairLock<CollectorState>
                private let continuation: CheckedContinuation<[(String, ResolvedRecord)], Never>

                init(totalCount: Int, continuation: CheckedContinuation<[(String, ResolvedRecord)], Never>) {
                    self.lock = OSAllocatedUnfairLock(initialState: CollectorState(remaining: totalCount))
                    self.continuation = continuation
                }

                func append(_ batch: [(String, ResolvedRecord)]) {
                    let finalResults: [(String, ResolvedRecord)]? = lock.withLock { state in
                        state.collected.append(contentsOf: batch)
                        state.remaining -= 1
                        return state.remaining == 0 ? state.collected : nil
                    }
                    if let finalResults {
                        continuation.resume(returning: finalResults)
                    }
                }
            }

            let collector = BatchCollector(totalCount: pairs.count, continuation: continuation)
            for (provider, domain) in pairs {
                Self.dnsResolutionQueue.addOperation {
                    let ips = Self.resolveHostIPs(domain)
                    let batch = ips.map { ($0, ResolvedRecord(provider: provider, domain: domain)) }
                    collector.append(batch)
                }
            }
        }

        let nextMap: [String: [ResolvedRecord]] = resolved.reduce(into: [:]) { map, entry in
            let (ip, record) = entry
            var arr = map[ip] ?? []
            if !arr.contains(record) {
                arr.append(record)
            }
            map[ip] = arr
        }

        stateLock.withLock { state in
            state.ipToRecords = nextMap
            state.lastRefreshedAt = Date()
        }
    }

    /// Allows injecting deterministic DNS/Fake-IP records in unit tests.
    public func seedMapping(ip: String, provider: LLMProviderSpec, domain: String) {
        stateLock.withLock { state in
            var arr = state.ipToRecords[ip] ?? []
            let rec = ResolvedRecord(provider: provider, domain: domain)
            if !arr.contains(rec) {
                arr.append(rec)
            }
            state.ipToRecords[ip] = arr
            state.lastRefreshedAt = Date()
        }
    }

    public func match(
        remoteIP: String,
        executableName: String,
        bundleID: String?
    ) -> EndpointMatchResult? {
        // 1. Check dedicated static IPv4 prefixes (e.g. Anthropic 160.79.104.*)
        for provider in LLMEndpointCatalog.providers {
            for prefix in provider.dedicatedIPv4Prefixes where remoteIP.hasPrefix(prefix) {
                return EndpointMatchResult(
                    provider: provider,
                    matchedDomain: provider.domains.first ?? remoteIP,
                    confidence: .dedicatedIP,
                    isFakeIP: false
                )
            }
        }

        // 2. Lookup cached DNS / Fake-IP table
        let records = stateLock.withLock { $0.ipToRecords[remoteIP] }

        guard let records, let first = records.first else {
            return nil
        }

        if LLMEndpointCatalog.isFakeIP(remoteIP) {
            return EndpointMatchResult(
                provider: first.provider,
                matchedDomain: first.domain,
                confidence: .exactFakeIP,
                isFakeIP: true
            )
        }

        // Real-IP attribution guards against false positives on shared CDNs / Google frontends:
        let lowerExec = executableName.lowercased()
        if first.provider.category == .applePCC {
            if LLMEndpointCatalog.knownApplePCCDaemons.contains(lowerExec) {
                return EndpointMatchResult(
                    provider: first.provider,
                    matchedDomain: first.domain,
                    confidence: .resolvedDomainKnownClient,
                    isFakeIP: false
                )
            }
            return nil
        }

        let isKnownClient = LLMEndpointCatalog.isKnownAIClient(executableName: executableName, bundleID: bundleID)
            || (bundleID.map { first.provider.knownClientBundleIDs.contains($0) } ?? false)

        if LLMEndpointCatalog.isSharedCloudflareAnycast(remoteIP) || first.provider.id == "gemini" {
            guard isKnownClient else {
                return nil
            }
        }

        return EndpointMatchResult(
            provider: first.provider,
            matchedDomain: first.domain,
            confidence: .resolvedDomainKnownClient,
            isFakeIP: false
        )
    }

    public static func resolveHostIPs(_ hostname: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &res)
        guard status == 0, let firstAddr = res else {
            return []
        }
        defer { freeaddrinfo(firstAddr) }

        var ips: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
        while let current = ptr {
            let family = current.pointee.ai_family
            if family == AF_INET, let sa = current.pointee.ai_addr {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = LLMEndpointCatalog.decodeNullTerminatedCString(buffer)
                    if !ips.contains(ip) { ips.append(ip) }
                }
            } else if family == AF_INET6, let sa = current.pointee.ai_addr {
                var addr6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                    let ip = LLMEndpointCatalog.decodeNullTerminatedCString(buffer)
                    if !ips.contains(ip) { ips.append(ip) }
                }
            }
            ptr = current.pointee.ai_next
        }
        return ips
    }

    public static func resolveCanonicalName(_ hostname: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_CANONNAME

        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &res) == 0, let firstAddr = res else {
            return nil
        }
        defer { freeaddrinfo(firstAddr) }
        guard let cnamePtr = firstAddr.pointee.ai_canonname else { return nil }
        let cname = String(cString: cnamePtr)
        return cname.isEmpty ? nil : cname
    }
}
