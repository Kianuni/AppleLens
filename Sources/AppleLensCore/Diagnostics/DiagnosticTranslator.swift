import Foundation

public struct UnifiedLogEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let processName: String
    public let processID: Int32
    public let subsystem: String
    public let category: String
    public let message: String
    public let sourceDevice: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        processName: String,
        processID: Int32 = 0,
        subsystem: String = "",
        category: String = "",
        message: String,
        sourceDevice: String = "This Mac"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.processName = processName
        self.processID = processID
        self.subsystem = subsystem
        self.category = category
        self.message = message
        self.sourceDevice = sourceDevice
    }

    public var cleanProcessName: String {
        LLMEndpointCatalog.normalizeProcessName(processName)
    }

    private var isBenignXPCLifecycleNoise: Bool {
        let msg = message.lowercased()
        return msg.contains("xpc_error_connection_interrupted")
            || msg.contains("re-initialization successful")
            || msg.contains("requesting resource bundle container")
    }

    private static let nonAISystemDaemons: Set<String> = [
        "kernel", "runningboardd", "springboard", "dasd", "backboardd",
        "windowserver", "networkserviceproxy", "nrdupdated", "softwareupdated",
        "backupd", "securityd", "akd", "devicecheckd"
    ]

    private static let pccSharedProtocolProcesses: Set<String> = [
        "privatecloudcomputed", "assistantd", "generativeexperiencesd",
        "modelmanagerd", "mobileslideshow", "photos", "mediaanalysisd",
        "photoanalysisd", "vcpmediaanalysisservice", "cloudphotod",
        "nsurlsessiond", "cloudd", "thimble", "importedlog", "unknown", ""
    ]

    public var isPhotosCleanUpSignal: Bool {
        let proc = cleanProcessName.lowercased()
        let sub = subsystem.lowercased()
        let msg = message.lowercased()
        guard !Self.nonAISystemDaemons.contains(proc), !isBenignXPCLifecycleNoise else {
            return false
        }
        let isPhotoProc = proc == "mobileslideshow" || proc == "photos" || proc == "mediaanalysisd" || proc == "photoanalysisd" || proc == "vcpmediaanalysisservice"
        if isPhotoProc {
            if sub == "visualintelligence" || sub == "generativemodels" {
                return true
            }
            if sub == "photoimaging" && (msg.contains("inpaint") || msg.contains("cleanup") || msg.contains("retouch") || msg.contains("brush") || msg.contains("pec")) {
                return true
            }
            return msg.contains("cleanup") || msg.contains("clean up") || msg.contains("inpaint")
                || msg.contains("retouch") || msg.contains("eraser") || msg.contains("cleanup-proxy")
                || msg.contains("remoteinpaint") || msg.contains("segmentation") || msg.contains("generative")
        }
        return sub.contains("cleanup") || sub.contains("inpaint")
            || msg.contains("ss-cleanup-proxy") || msg.contains("remoteinpaint") || msg.contains("photocleanup")
    }

    public var isVisualIntelligenceSignal: Bool {
        let proc = cleanProcessName.lowercased()
        let sub = subsystem.lowercased()
        let msg = message.lowercased()
        guard !Self.nonAISystemDaemons.contains(proc), !isBenignXPCLifecycleNoise else {
            return false
        }
        return proc.contains("visualintelligence")
            || proc == "cameraoverlayangel"
            || sub.contains("visualintelligence")
            || msg.contains("visualintelligence")
            || msg.contains("lens.google")
    }

    public var isOnDeviceInferenceSignal: Bool {
        if isBenignXPCLifecycleNoise {
            return false
        }
        let proc = cleanProcessName.lowercased()
        let sub = subsystem.lowercased()
        let msg = message.lowercased()
        if Self.nonAISystemDaemons.contains(proc) {
            return false
        }
        if proc.contains("tgondeviceinference")
            || proc == "siriinferenced"
            || proc.contains("generativeexperiencessafetyinference")
            || proc == "imageplayground"
            || proc == "writingtools" {
            return true
        }
        if proc.contains("modelmanagerd") || proc.contains("generativeexperiences") {
            return msg.contains("inference") || msg.contains("session") || msg.contains("generate") || msg.contains("model") || msg.contains("token") || msg.contains("ane") || sub.contains("generativemodels") || sub.contains("foundationmodels")
        }
        if proc == "aned" {
            return msg.contains("model") || msg.contains("compile") || msg.contains("execute") || msg.contains("program") || msg.contains("inpaint")
        }
        if isPhotosCleanUpSignal && !isPCCSignal {
            return true
        }
        if isVisualIntelligenceSignal && !isPCCSignal && !msg.contains("chatgpt") && !msg.contains("openai") && !msg.contains("lens.google") {
            return true
        }
        if proc == "mobileslideshow" || proc == "photos" || proc == "mediaanalysisd" || proc == "photoanalysisd" || proc == "vcpmediaanalysisservice" {
            return msg.contains("generative") || msg.contains("neuralengine") || msg.contains("ane") || msg.contains("visualintelligence")
        }
        if sub.contains("generativemodels") || sub.contains("foundationmodels") || sub.contains("intelligenceflow") {
            return msg.contains("on-device") || msg.contains("ondevice") || msg.contains("local") || msg.contains("inference")
        }
        return false
    }

    public var isPCCSignal: Bool {
        if isBenignXPCLifecycleNoise {
            return false
        }
        let proc = cleanProcessName.lowercased()
        let sub = subsystem.lowercased()
        let msg = message.lowercased()
        if Self.nonAISystemDaemons.contains(proc) {
            return false
        }
        if proc == "privatecloudcomputed"
            || sub.contains("privatecloudcompute")
            || sub.contains("cloudattestation")
            || msg.contains("thimble")
            || msg.contains("privatecloudcompute")
            || msg.contains("issuer.apple.com")
            || msg.contains("ss-cleanup-proxy")
            || msg.contains("ropes.apple.com") {
            return true
        }
        let isPCCRelatedOrigin = Self.pccSharedProtocolProcesses.contains(proc)
            || sub.contains("siri")
            || sub.contains("generative")
            || sub.contains("ios.syslog_relay")
            || sub.contains("file.import")
        if isPCCRelatedOrigin
            && (msg.contains("attestation")
                || msg.contains("ohttp")
                || msg.contains("mask-api.icloud.com")
                || msg.contains("apple-relay")
                || msg.contains("cleanup-proxy")
                || msg.contains("remoteinpaint")) {
            return true
        }
        return false
    }

    public var recognizedFeatureTitle: (zh: String, en: String)? {
        if isPhotosCleanUpSignal {
            return ("相册 · 智能消除 (Clean Up)", "Photos Clean Up")
        }
        if isVisualIntelligenceSignal {
            return ("视觉智能 · 相机控制 (Visual Intelligence)", "Visual Intelligence")
        }
        if isPCCSignal {
            return ("Apple PCC 私有云推理", "Apple PCC Inference")
        }
        let proc = cleanProcessName.lowercased()
        if proc == "assistantd" || proc == "writingtools" || proc == "siri" {
            return ("Siri / 智能写作工具", "Siri / Writing Tools")
        }
        if isOnDeviceInferenceSignal {
            return ("端侧大模型 / ANE 本地推理", "On-Device ANE Inference")
        }
        return nil
    }
}

public enum DiagnosticCode: String, CaseIterable, Codable, Sendable {
    case code32033BlindTokenLeak = "PCC_32033_BLIND_TOKEN_LEAK"
    case quicUDP443Blocked = "PCC_QUIC_UDP443_BLOCKED"
    case code1009LocalCooldown = "PCC_1009_LOCAL_COOLDOWN"
    case code1009ServerQuota = "PCC_1009_SERVER_QUOTA"
    case ios27_3CHRegionPolicyLock = "IOS27_3_CH_POLICY_LOCK"
    case siriGuzzoniProxyMisroute = "SIRI_GUZZONI_PROXY_MISROUTE"
    case slot266InstantAbort = "GESTALT_SLOT_266_ABORT"
    case modelAssetDownloadProgress = "UAF_MODEL_ASSET_STATUS"
}

public enum DiagnosticSeverity: String, Codable, Sendable {
    case critical
    case warning
    case info

    public func label(lang: AppLanguage) -> String {
        switch self {
        case .critical: return tr("严重拦截", "Critical", lang: lang)
        case .warning: return tr("注意风险", "Warning", lang: lang)
        case .info: return tr("资产/状态", "Status", lang: lang)
        }
    }
}

public struct DiagnosticFinding: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let code: DiagnosticCode
    public let severity: DiagnosticSeverity
    public let timestamp: Date
    public let sourceDevice: String
    public let processName: String
    public let rawLine: String
    public let titleZh: String
    public let titleEn: String
    public let explanationZh: String
    public let explanationEn: String
    public let remediationZh: String
    public let remediationEn: String
    public let copyableSnippet: String?
    public let actionURL: String?
    public let actionLabelZh: String?
    public let actionLabelEn: String?
    public let progressFraction: Double?

    public func title(lang: AppLanguage) -> String { tr(titleZh, titleEn, lang: lang) }
    public func explanation(lang: AppLanguage) -> String { tr(explanationZh, explanationEn, lang: lang) }
    public func remediation(lang: AppLanguage) -> String { tr(remediationZh, remediationEn, lang: lang) }
    public func actionLabel(lang: AppLanguage) -> String? {
        guard let zh = actionLabelZh, let en = actionLabelEn else { return nil }
        return tr(zh, en, lang: lang)
    }
}

public enum DiagnosticTranslator {
    public static let appleFlowURL = "https://kianuni.github.io/AppleFlow/"
    public static let erosionURL = "https://github.com/Kianuni/Erosion-CN"

    private static let pccRuleSnippet = """
    # AppleFlow PCC Core Rules (place BEFORE Apple_All / GEOSITE,apple)
    DOMAIN,gspe1-ssl.ls.apple.com,US_PROXY
    DOMAIN-SUFFIX,issuer.apple.com,US_PROXY
    DOMAIN-SUFFIX,ropes.apple.com,US_PROXY
    DOMAIN,mask-api.icloud.com,US_PROXY
    DOMAIN,mask.icloud.com,US_PROXY
    DOMAIN,mask-h2.icloud.com,US_PROXY
    DOMAIN,ss-cleanup-proxy-prod.us-east-1m.app.apple.com,US_PROXY
    DOMAIN-SUFFIX,app.apple.com,US_PROXY
    DOMAIN-SUFFIX,apple-relay.apple.com,US_PROXY
    DOMAIN-SUFFIX,apple-relay.cloudflare.com,US_PROXY
    DOMAIN-SUFFIX,apple-relay.fastly-edge.com,US_PROXY
    DOMAIN-SUFFIX,apple-relay.akamaized.net,US_PROXY
    """

    private static let siriDirectSnippet = """
    # AppleFlow Siri Direct Guardrail (Surge / Clash / Mihomo)
    [General]
    skip-proxy = 127.0.0.1, 192.168.0.0/16, 10.0.0.0/8, localhost, *.local, guzzoni.apple.com
    always-real-ip = guzzoni.apple.com, *.guzzoni.apple.com, *.siri.apple.com

    [Rule]
    DOMAIN-SUFFIX,guzzoni.apple.com,DIRECT
    DOMAIN-SUFFIX,siri.apple.com,DIRECT
    DOMAIN,dejavu.apple.com,DIRECT
    DOMAIN,sequoia.apple.com,DIRECT
    DOMAIN-SUFFIX,smoot.apple.com,DIRECT
    """

    private static let siriConnectionRegex = try? NSRegularExpression(
        pattern: #"\b(adconnection|siriconnection)\b"#,
        options: [.caseInsensitive]
    )
    private static let uafWordRegex = try? NSRegularExpression(
        pattern: #"\buaf\b"#,
        options: [.caseInsensitive]
    )
    private static let percentRegex = try? NSRegularExpression(
        pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#,
        options: [.caseInsensitive]
    )
    private static let ratioRegex = try? NSRegularExpression(
        pattern: #"(?:downloaded|bytes|progress)[^\d]{0,16}(\d+)\s*/\s*(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let langTagRegex = try? NSRegularExpression(
        pattern: #"lang:([A-Za-z0-9_-]+)"#,
        options: [.caseInsensitive]
    )
    private static let ifFlagRegex = try? NSRegularExpression(
        pattern: #"IF:\s*(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let nlRouterFlagRegex = try? NSRegularExpression(
        pattern: #"NLRouter:\s*(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let asrFlagRegex = try? NSRegularExpression(
        pattern: #"ASR:\s*(\d+)"#,
        options: [.caseInsensitive]
    )

    private static let excludedSystemDaemons: Set<String> = [
        "backboardd", "springboard", "runningboardd", "networkserviceproxy",
        "nrdupdated", "softwareupdated", "windowserver", "kernel", "backupd", "dasd"
    ]

    private static let aiAndPCCProcessPrefixes: [String] = [
        "privatecloudcompute", "generative", "assistant", "modelmanager",
        "photos", "mobileslideshow", "mediaanalysis", "photoanalysis",
        "vcpmediaanalysis", "tgondeviceinference", "siriinference",
        "eligibility", "writingtools", "imageplayground", "visualintelligence",
        "nsurlsessiond", "cloudd", "thimble"
    ]

    private struct LineContext {
        let rawLine: String
        let lowerLine: String
        let process: String
        let lowerProc: String
        let subsystem: String
        let lowerSub: String
        let sourceDevice: String
        let timestamp: Date
        let benignNull: Bool
        let isGenericOrImported: Bool
        let isExcludedSystemDaemon: Bool
        let isPCCOrAIProc: Bool
        let isSiriProc: Bool
        let isAIOrPCCContext: Bool

        var combinedContext: String {
            "\(lowerProc) \(lowerSub) \(lowerLine)"
        }

        init(line: String, process: String, subsystem: String, sourceDevice: String, timestamp: Date) {
            let lowerLine = line.lowercased()
            let lowerProc = LLMEndpointCatalog.normalizeProcessName(process).lowercased()
            let lowerSub = subsystem.lowercased()
            let isGenericOrImported = lowerProc.isEmpty
                || lowerProc == "unknown"
                || lowerProc == "importedlog"
                || lowerSub == "file.import"
            let isExcluded = DiagnosticTranslator.excludedSystemDaemons.contains(lowerProc)

            self.rawLine = line
            self.lowerLine = lowerLine
            self.process = process
            self.lowerProc = lowerProc
            self.subsystem = subsystem
            self.lowerSub = lowerSub
            self.sourceDevice = sourceDevice
            self.timestamp = timestamp
            self.benignNull = DiagnosticTranslator.isBenignNullError(lowerLine)
            self.isGenericOrImported = isGenericOrImported
            self.isExcludedSystemDaemon = isExcluded
            self.isPCCOrAIProc = !isExcluded && (
                isGenericOrImported
                    || DiagnosticTranslator.aiAndPCCProcessPrefixes.contains(where: { lowerProc.contains($0) })
                    || lowerSub.contains("privatecloudcompute")
                    || lowerSub.contains("generative")
                    || lowerSub.contains("unifiedassetframework")
            )
            self.isSiriProc = !isExcluded && (
                isGenericOrImported
                    || lowerProc.contains("assistant")
                    || lowerProc.contains("siri")
                    || lowerProc.contains("corespeech")
                    || lowerSub.contains("com.apple.siri")
            )
            self.isAIOrPCCContext = lowerProc.contains("privatecloudcompute")
                || lowerProc.contains("generative")
                || lowerProc.contains("assistantd")
                || lowerProc.contains("modelmanagerd")
                || lowerProc.contains("photos")
                || lowerProc.contains("mobileslideshow")
                || lowerProc.contains("mediaanalysisd")
                || lowerSub.contains("privatecloudcompute")
                || lowerSub.contains("generative")
                || lowerLine.contains("privatecloudcompute")
                || lowerLine.contains("thimble")
                || lowerLine.contains("issuer.apple.com")
                || lowerLine.contains("ss-cleanup-proxy")
        }

        func resolvedProcessName(fallback: String) -> String {
            process.isEmpty ? fallback : process
        }
    }

    public static func translate(event: UnifiedLogEvent) -> DiagnosticFinding? {
        translate(
            line: event.message,
            process: event.processName,
            subsystem: event.subsystem,
            sourceDevice: event.sourceDevice,
            timestamp: event.timestamp
        )
    }

    private static func isBenignNullError(_ lowerLine: String) -> Bool {
        lowerLine.contains("error=(null)")
            || lowerLine.contains("error: (null)")
            || lowerLine.contains("error: nil")
            || lowerLine.contains("error=nil")
            || lowerLine.contains("error=0")
            || lowerLine.contains("err=0")
            || lowerLine.contains("no error")
    }

    public static func translate(
        line: String,
        process: String = "",
        subsystem: String = "",
        sourceDevice: String = "This Mac",
        timestamp: Date = Date()
    ) -> DiagnosticFinding? {
        let ctx = LineContext(
            line: line,
            process: process,
            subsystem: subsystem,
            sourceDevice: sourceDevice,
            timestamp: timestamp
        )

        if let finding = matchIOS27CHRegionPolicyLock(ctx) { return finding }
        if let finding = matchCode32033BlindTokenLeak(ctx) { return finding }
        if let finding = matchQuicUDP443Blocked(ctx) { return finding }
        if let finding = matchCode1009RateLimit(ctx) { return finding }
        if let finding = matchSiriGuzzoniProxyMisroute(ctx) { return finding }
        if let finding = matchSlot266InstantAbort(ctx) { return finding }
        if let finding = matchModelAssetStatus(ctx) { return finding }
        return nil
    }

    // MARK: - Structured Diagnostic Matchers

    private static func matchIOS27CHRegionPolicyLock(_ ctx: LineContext) -> DiagnosticFinding? {
        let hasExplicitCHPolicy = ctx.lowerLine.contains("no cn region policy on a ch region code device")
            || (ctx.combinedContext.contains("generativefunctions") && ctx.lowerLine.contains("no cn region policy"))
        guard ctx.isPCCOrAIProc && hasExplicitCHPolicy else { return nil }

        return DiagnosticFinding(
            id: UUID(),
            code: .ios27_3CHRegionPolicyLock,
            severity: .critical,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "Photos / GenerativeFunctions"),
            rawLine: ctx.rawLine,
            titleZh: "iOS 27.3 国行硬件本地策略锁拦截",
            titleEn: "iOS 27.3 CH Hardware Local Region Policy Lock",
            explanationZh: "系统 GenerativeFunctionsFoundation 在发出任何网络请求前直接读取主板只读 SysCfg（非 MobileGestalt 缓存），识别到国行 CH 硬件后查询「CN 区域 AI 策略」，因策略未下发而在本地 0 秒拦截。",
            explanationEn: "GenerativeFunctionsFoundation read factory non-cached SysCfg (CH hardware) before any network call and found no CN region policy, aborting locally.",
            remediationZh: "1. 切勿向 MobileGestalt CacheExtra 强行注入 slot=-1 键（会触发开机缓存重置）；\n2. 改区与代理规则无法绕过此本地检查，需停留在或降回 iOS 27.0–27.2.1（刷机前请在 Erosion-CN 先恢复原厂备份），或等待苹果后续下发策略。",
            remediationEn: "1. NEVER inject slot=-1 keys into MobileGestalt CacheExtra (triggers boot-time reset).\n2. Proxy or region changes cannot bypass this check; stay on or downgrade to iOS 27.0–27.2.1 (restore factory MobileGestalt first in Erosion-CN), or wait for Apple policy rollout.",
            copyableSnippet: nil,
            actionURL: erosionURL,
            actionLabelZh: "查看 Erosion-CN 兼容性说明",
            actionLabelEn: "Open Erosion-CN Compatibility Guide",
            progressFraction: nil
        )
    }

    private static func matchCode32033BlindTokenLeak(_ ctx: LineContext) -> DiagnosticFinding? {
        let explicit32033 = ctx.lowerLine.contains("code=32033")
            || ctx.lowerLine.contains("code = 32033")
            || ctx.lowerLine.contains("error 32033")
        let issuerDenied = ctx.lowerLine.contains("issuer.apple.com")
            && (ctx.lowerLine.contains("403")
                || ctx.lowerLine.contains("denied")
                || ctx.lowerLine.contains("untrusted")
                || (ctx.lowerLine.contains("failed") && !ctx.benignNull))
        guard ctx.isPCCOrAIProc && ctx.isAIOrPCCContext && (explicit32033 || issuerDenied) else {
            return nil
        }

        return DiagnosticFinding(
            id: UUID(),
            code: .code32033BlindTokenLeak,
            severity: .critical,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "privatecloudcomputed"),
            rawLine: ctx.rawLine,
            titleZh: "PCC 盲签令牌漏走直连 (Code=32033)",
            titleEn: "PCC Blind-Sign Token Issuer Misrouted (Code=32033)",
            explanationZh: "Private Cloud Compute 盲签名令牌签发域（*.issuer.apple.com / ropes.apple.com / mask*.icloud.com / *.app.apple.com）未置于 Apple_All 之前，漏走国内直连暴露了中国大陆 IP 被苹果秒拒。",
            explanationEn: "PCC blind-signing token endpoints (*.issuer.apple.com, ropes.apple.com, mask*.icloud.com) fell through to DIRECT/Apple_All, leaking a restricted region IP.",
            remediationZh: "1. 安装或更新 AppleFlow 规则/模块并置顶于 Apple_All 之前；\n2. 在代理软件点击「更新外部资源 (Update External Resources)」；\n3. 关机冷重启设备一次，清空 privatecloudcomputed 内存里的退避缓存。",
            remediationEn: "1. Install/update AppleFlow PCC rules ABOVE Apple_All / GEOSITE,apple.\n2. Update External Resources in your proxy client.\n3. Reboot the device once to clear privatecloudcomputed's in-memory failure cache.",
            copyableSnippet: pccRuleSnippet,
            actionURL: appleFlowURL,
            actionLabelZh: "打开 AppleFlow 一键修复分流",
            actionLabelEn: "Open AppleFlow Rule Workbench",
            progressFraction: nil
        )
    }

    private static func matchQuicUDP443Blocked(_ ctx: LineContext) -> DiagnosticFinding? {
        let hasRelayOrOHTTP = ctx.lowerLine.contains("quic")
            || ctx.lowerLine.contains("ohttp")
            || ctx.lowerLine.contains("apple-relay")
            || ctx.lowerLine.contains("mask.icloud.com")
        let hasRealQuicFailure = ctx.lowerLine.contains("timed out")
            || ctx.lowerLine.contains("handshake failed")
            || ctx.lowerLine.contains("connection refused")
            || ctx.lowerLine.contains("unreachable")
            || ctx.lowerLine.contains("blocked")
        let isPCCOrRelayContext = ctx.combinedContext.contains("privatecloudcompute")
            || ctx.lowerLine.contains("ohttp")
            || ctx.lowerLine.contains("apple-relay")
            || ctx.lowerLine.contains("mask.icloud.com")
            || ctx.lowerLine.contains("quic-block")
        guard ctx.isPCCOrAIProc
            && isPCCOrRelayContext
            && (ctx.lowerLine.contains("quic-block") || (hasRelayOrOHTTP && hasRealQuicFailure && !ctx.benignNull)) else {
            return nil
        }

        let explicitBlockRule = ctx.lowerLine.contains("quic-block")
        return DiagnosticFinding(
            id: UUID(),
            code: .quicUDP443Blocked,
            severity: explicitBlockRule ? .warning : .info,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "privatecloudcomputed"),
            rawLine: ctx.rawLine,
            titleZh: "检测到 QUIC (UDP 443) 未放行（系统支持自动回退 TCP HTTP/2）",
            titleEn: "QUIC (UDP 443) Unavailable — TCP HTTP/2 Fallback Active",
            explanationZh: "Apple PCC / 相册高质量消除会优先并发尝试 UDP 443 (QUIC)。当代理节点使用 Snell 或开启 udp-policy-not-supported-behaviour = REJECT 时，UDP 会被拒绝并自动无缝切回 TCP HTTP/2 完成推理——若消除/对话已成功则完全正常，无需处理。仅在功能实际报错无法完成时才需排查节点。",
            explanationEn: "Apple PCC races UDP 443 (QUIC) first and automatically falls back to TCP HTTP/2 when Snell or UDP-REJECT drops UDP. If Clean Up or Apple Intelligence succeeded, this is normal and requires no action.",
            remediationZh: "1. 若「高质量消除」或 PCC 对话已成功完成，可忽略此回退提示；\n2. 如确实触发超慢或断连报错，请移除针对 apple-relay.* 的 QUIC-BLOCK 规则或改用支持 UDP 转发的美区节点。",
            remediationEn: "1. If Photos Clean Up or PCC requests succeed normally, you can safely ignore this TCP fallback note.\n2. Only if requests actually fail, remove QUIC-BLOCK rules or switch to a UDP-capable US node.",
            copyableSnippet: nil,
            actionURL: appleFlowURL,
            actionLabelZh: "查看 AppleFlow 节点要求",
            actionLabelEn: "View AppleFlow Node Requirements",
            progressFraction: nil
        )
    }

    private static func matchCode1009RateLimit(_ ctx: LineContext) -> DiagnosticFinding? {
        let has1009Code = ctx.lowerLine.contains("code=1009") && !ctx.lowerLine.contains("code=-1009")
        let hasRateLimitText = ctx.lowerLine.contains("rate-limited") || ctx.lowerLine.contains("rate limited")
        guard !ctx.isExcludedSystemDaemon
            && ctx.isPCCOrAIProc
            && ctx.isAIOrPCCContext
            && (has1009Code || hasRateLimitText) else {
            return nil
        }

        if ctx.lowerLine.contains("retry-after") {
            return DiagnosticFinding(
                id: UUID(),
                code: .code1009LocalCooldown,
                severity: .warning,
                timestamp: ctx.timestamp,
                sourceDevice: ctx.sourceDevice,
                processName: ctx.resolvedProcessName(fallback: "privatecloudcomputed"),
                rawLine: ctx.rawLine,
                titleZh: "Code=1009 本机内存退避冷却命中 (retry-after)",
                titleEn: "Code=1009 Local In-Memory Cooldown Active (retry-after)",
                explanationZh: "令牌签发端此前返回了 retry-after 头，privatecloudcomputed 已将冷却倒计时缓存在本机内存中，因此后续点击会被本机瞬间秒拒，即使已经修好规则也会继续报错。",
                explanationEn: "privatecloudcomputed cached a retry-after backoff window in local RAM from an earlier failure, causing immediate local rejections even after fixing proxy rules.",
                remediationZh: "请先确认 AppleFlow 规则与 UDP 节点已修好，然后**立即关机并重启一次设备**清空 privatecloudcomputed 内存冷却缓存，切勿连续狂点重试。",
                remediationEn: "Confirm your AppleFlow rules and UDP node are ready, then **reboot the device once** to purge privatecloudcomputed's in-memory retry-after cooldown.",
                copyableSnippet: nil,
                actionURL: nil,
                actionLabelZh: nil,
                actionLabelEn: nil,
                progressFraction: nil
            )
        }

        return DiagnosticFinding(
            id: UUID(),
            code: .code1009ServerQuota,
            severity: .warning,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "privatecloudcomputed"),
            rawLine: ctx.rawLine,
            titleZh: "Code=1009 苹果云端令牌配额限流 (Rate Limited)",
            titleEn: "Code=1009 Apple Cloud Token Quota Rate Limit",
            explanationZh: "本地尚未缓存 retry-after，但服务端直接返回限流。常见于短时间内高频触发消除/请求，或使用多人共用高并发节点出口 IP 抢占了苹果盲签配额。",
            explanationEn: "Apple's token issuer enforced server-side rate limiting—often caused by rapid retries or a heavily shared proxy exit IP exhausting anonymous token quotas.",
            remediationZh: "1. 立即停止连续重试，静置等待数小时至约 24 小时自然恢复（端侧快速消除不受影响）；\n2. 如长期触发，建议切换低并发独享或洁净美区节点。",
            remediationEn: "1. Stop retrying for several hours (up to ~24h) for quota recovery; on-device Fast Clean Up remains unaffected.\n2. Switch to a lower-concurrency clean US exit node.",
            copyableSnippet: nil,
            actionURL: nil,
            actionLabelZh: nil,
            actionLabelEn: nil,
            progressFraction: nil
        )
    }

    private static func matchSiriGuzzoniProxyMisroute(_ ctx: LineContext) -> DiagnosticFinding? {
        let hasGuzzoniOrSiriHost = ctx.lowerLine.contains("guzzoni.apple.com") || ctx.lowerLine.contains("siri.apple.com")
        let hasWordBoundedSiriConn = matchesRegex(siriConnectionRegex, in: ctx.lowerLine)
        let hasSiriNetworkFailure = ctx.lowerLine.contains("connection reset")
            || ctx.lowerLine.contains("timed out")
            || ctx.lowerLine.contains("handshake failed")
            || ctx.lowerLine.contains("connection refused")
            || ctx.lowerLine.contains("interrupted")
            || ctx.lowerLine.contains("cannot connect")
            || ctx.lowerLine.contains("not connected")
            || ctx.lowerLine.contains("network is unreachable")
            || (ctx.lowerLine.contains("error") && (ctx.lowerLine.contains("connect") || ctx.lowerLine.contains("proxy") || ctx.lowerLine.contains("fail")))
        guard ctx.isSiriProc
            && (hasGuzzoniOrSiriHost || hasWordBoundedSiriConn)
            && hasSiriNetworkFailure
            && !ctx.benignNull else {
            return nil
        }

        return DiagnosticFinding(
            id: UUID(),
            code: .siriGuzzoniProxyMisroute,
            severity: .critical,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "assistantd"),
            rawLine: ctx.rawLine,
            titleZh: "中文 Siri 核心网关 (guzzoni) 被代理或 Fake-IP 误伤",
            titleEn: "Mandarin Siri Gateway (guzzoni.apple.com) Hijacked by Proxy / Fake-IP",
            explanationZh: "中文普通话 Siri 与「询问来电原因」依赖 guzzoni.apple.com 及 *.siri.apple.com 的国内真实 IP 直连。走海外代理、开启全局代理或被 VIF 解析成 198.18.x.x Fake-IP 会导致「碰到了一点问题」。",
            explanationEn: "Mandarin Siri requires real-IP DIRECT connectivity to guzzoni.apple.com and *.siri.apple.com. Overseas proxies or 198.18.0.0/15 Fake-IPs break Siri sessions.",
            remediationZh: "将 guzzoni.apple.com 与 *.siri.apple.com 设为 DIRECT 并加入 skip-proxy 与 always-real-ip / fake-ip-filter（点击右侧复制完整 Surge 修复片段）。",
            remediationEn: "Route guzzoni.apple.com and *.siri.apple.com DIRECT and add them to skip-proxy + always-real-ip / fake-ip-filter.",
            copyableSnippet: siriDirectSnippet,
            actionURL: appleFlowURL,
            actionLabelZh: "安装 AppleFlow Siri 直连护栏",
            actionLabelEn: "Install AppleFlow Siri Direct Guardrail",
            progressFraction: nil
        )
    }

    private static func matchSlot266InstantAbort(_ ctx: LineContext) -> DiagnosticFinding? {
        let mentionsSlot266 = ctx.lowerLine.contains("personal translator")
            || ctx.lowerLine.contains("#266")
            || ctx.lowerLine.contains("m1n2saqf33naogzrgxqyba")
        let hasSlotFailureToken = ctx.lowerLine.contains("fail")
            || ctx.lowerLine.contains("abort")
            || ctx.lowerLine.contains("unavailable")
            || ctx.lowerLine.contains("false")
            || ctx.lowerLine.contains("mismatch")
            || ctx.lowerLine.contains("error")
        guard ctx.isPCCOrAIProc && mentionsSlot266 && hasSlotFailureToken && !ctx.benignNull else {
            return nil
        }

        return DiagnosticFinding(
            id: UUID(),
            code: .slot266InstantAbort,
            severity: .critical,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "GenerativeModels"),
            rawLine: ctx.rawLine,
            titleZh: "本地功能槽位基线异常（疑似 #266 Personal Translator）",
            titleEn: "Local Capability Baseline Mismatch (Slot #266 / ModelCatalog)",
            explanationZh: "原生支持 Apple 智能的机型要求 CacheData 槽位 #266 (Personal Translator) 为 true。若被旧工具写为 false，系统会在 0 毫秒预检直接熔断报错。",
            explanationEn: "Native Apple Intelligence hardware requires CacheData slot #266 (Personal Translator) = true. Mismatched baselines abort immediately before loading.",
            remediationZh: "请更新至 Erosion-CN v0.9.1+，点击顶部「一键配齐 / 修复」->「应用」并手动关机冷重启。",
            remediationEn: "Update to Erosion-CN v0.9.1+, run the 1-click baseline fix, apply, and cold-reboot the device.",
            copyableSnippet: nil,
            actionURL: erosionURL,
            actionLabelZh: "打开 Erosion-CN 修复",
            actionLabelEn: "Open Erosion-CN",
            progressFraction: nil
        )
    }

    private static func matchModelAssetStatus(_ ctx: LineContext) -> DiagnosticFinding? {
        guard let progressResult = parseModelAssetStatus(ctx: ctx) else { return nil }
        return DiagnosticFinding(
            id: UUID(),
            code: .modelAssetDownloadProgress,
            severity: .info,
            timestamp: ctx.timestamp,
            sourceDevice: ctx.sourceDevice,
            processName: ctx.resolvedProcessName(fallback: "modelmanagerd"),
            rawLine: ctx.rawLine,
            titleZh: progressResult.titleZh,
            titleEn: progressResult.titleEn,
            explanationZh: progressResult.detailZh,
            explanationEn: progressResult.detailEn,
            remediationZh: progressResult.hintZh,
            remediationEn: progressResult.hintEn,
            copyableSnippet: nil,
            actionURL: nil,
            actionLabelZh: nil,
            actionLabelEn: nil,
            progressFraction: progressResult.fraction
        )
    }

    private struct ParsedAssetStatus {
        let titleZh: String
        let titleEn: String
        let detailZh: String
        let detailEn: String
        let hintZh: String
        let hintEn: String
        let fraction: Double?
    }

    private static func parseModelAssetStatus(ctx: LineContext) -> ParsedAssetStatus? {
        if ctx.isExcludedSystemDaemon {
            return nil
        }

        let isAssetProc = ctx.isGenericOrImported
            || ctx.lowerProc.contains("modelmanagerd")
            || ctx.lowerProc.contains("assistantd")
            || ctx.lowerProc.contains("generative")
            || ctx.lowerProc == "mobileassetd"
        let isAssetSub = ctx.lowerSub.contains("unifiedassetframework")
            || ctx.lowerSub.contains("mobileasset")
            || ctx.lowerSub.contains("generativemodels")
            || ctx.lowerSub.contains("com.apple.siri")
        let hasWordBoundedUAF = matchesRegex(uafWordRegex, in: ctx.lowerLine)
        let hasExplicitAssetMessage = ctx.lowerLine.contains("sadmobileassetdownloadstate")
            || hasWordBoundedUAF
            || ctx.lowerLine.contains("retrieved asset status")

        guard (isAssetProc && (isAssetSub || hasExplicitAssetMessage || ctx.lowerProc.contains("modelmanagerd")))
            || (ctx.isPCCOrAIProc && isAssetSub) else {
            return nil
        }

        // Pattern 1: Explicit percentage e.g. "68.5%" or "progress: 68%"
        if let percent = extractFirstMatch(regex: percentRegex, in: ctx.rawLine),
           let value = Double(percent), (0...100).contains(value),
           (ctx.lowerLine.contains("download")
                || ctx.lowerLine.contains("asset")
                || ctx.lowerLine.contains("model")
                || ctx.lowerLine.contains("progress")) {
            let frac = value / 100.0
            let pctText = String(format: "%.1f%%", value)
            let procLabel = ctx.resolvedProcessName(fallback: "modelmanagerd")
            return ParsedAssetStatus(
                titleZh: "端侧模型资产下载进度：\(pctText)",
                titleEn: "On-Device Model Asset Download: \(pctText)",
                detailZh: "检测到 \(procLabel) 正在后台拉取端侧模型包（\(pctText)）。",
                detailEn: "Observed \(procLabel) downloading local AI assets (\(pctText)).",
                hintZh: "请保持连接电源、Wi-Fi 与非大陆 Apple ID（App Store）直至达到 100%。",
                hintEn: "Keep the device on Wi-Fi and charger with a non-Mainland App Store account until 100%.",
                fraction: frac
            )
        }

        // Pattern 2: Byte ratio e.g. "downloaded: 1048576 / 2097152" or "bytesWritten=500 totalBytes=1000"
        if let ratio = extractRatio(in: ctx.rawLine), ratio >= 0, ratio <= 1 {
            let pctText = String(format: "%.1f%%", ratio * 100.0)
            return ParsedAssetStatus(
                titleZh: "端侧模型资产下载进度：\(pctText)",
                titleEn: "On-Device Model Asset Download: \(pctText)",
                detailZh: "后台 MobileAsset 传输完成 \(pctText)。",
                detailEn: "Background MobileAsset download is at \(pctText).",
                hintZh: "端侧推理与高质量视觉功能需等所有基础权重文件下载完备。",
                hintEn: "Wait for asset weights to complete before testing local intelligence features.",
                fraction: ratio
            )
        }

        // Pattern 3: Real macOS/iOS ADAssetManager status line observed in unified logs:
        // "Retrieved asset status ASR: 1, NL: 0, Morphun: 1, Attention: 0, NLRouter: 0, IF: 0, TB: 0 (lang:zh-CN, uod:1, hybrid:0)"
        if ctx.lowerLine.contains("retrieved asset status") {
            let langTag = extractFirstMatch(regex: langTagRegex, in: ctx.rawLine) ?? "unknown"
            let ifReady = extractFirstMatch(regex: ifFlagRegex, in: ctx.rawLine) == "1"
            let nlRouterReady = extractFirstMatch(regex: nlRouterFlagRegex, in: ctx.rawLine) == "1"
            let asrReady = extractFirstMatch(regex: asrFlagRegex, in: ctx.rawLine) == "1"

            if asrReady && nlRouterReady {
                return ParsedAssetStatus(
                    titleZh: "Siri 语音与意图路由子模块已就绪 (\(langTag))",
                    titleEn: "Siri Speech & Intent Router Ready (\(langTag))",
                    detailZh: "语音识别(ASR)=就绪 · 意图路由(NLRouter)=就绪 · 旧版 IF 标记=\(ifReady ? "1" : "0（简中环境正常）")。注：此项为 assistantd 内部子模块开关状态，并非模型下载百分比；Apple 智能与视觉智能模型由 UAF 独立管理。",
                    detailEn: "ASR=Ready · NLRouter=Ready · Legacy IF=\(ifReady ? "1" : "0 (normal in zh-CN)"). Note: These are assistantd subsystem flags, not a download percentage; Apple Intelligence models are managed separately by UAF.",
                    hintZh: "无需操作，端侧能力已就绪。iPhone 仅在首次下载期间于「设置 → Apple 智能与 Siri」顶部显示准备进度，下载 100% 激活后系统会自动隐藏进度条。",
                    hintEn: "No action needed. iPhone only shows a preparation status in Settings -> Apple Intelligence & Siri during initial download and hides it once 100% active.",
                    fraction: nil
                )
            } else {
                return ParsedAssetStatus(
                    titleZh: "Siri 语音/路由子模块状态 (\(langTag))",
                    titleEn: "Siri Speech/Router Subsystem Status (\(langTag))",
                    detailZh: "语音识别(ASR)=\(asrReady ? "就绪" : "未就绪") · 意图路由(NLRouter)=\(nlRouterReady ? "就绪" : "未就绪") · 旧版 IF 标记=\(ifReady ? "1" : "0")（此项为子开关状态，非下载进度百分比）。",
                    detailEn: "ASR=\(asrReady ? "Ready" : "Missing") · NLRouter=\(nlRouterReady ? "Ready" : "Missing") · Legacy IF=\(ifReady ? "1" : "0") (subsystem readiness flags, not a download percentage).",
                    hintZh: "可在 iPhone「设置 → Apple 智能与 Siri」顶部查看是否仍有「正在准备 Apple 智能…」提示；若该提示已消失且视觉智能/消除正常可用，说明端侧模型早已 100% 下载完毕。",
                    hintEn: "Check Settings -> Apple Intelligence & Siri on iPhone; if no 'Preparing Apple Intelligence' banner appears and features work, models are already 100% downloaded.",
                    fraction: nil
                )
            }
        }

        return nil
    }

    private static func matchesRegex(_ regex: NSRegularExpression?, in text: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func extractFirstMatch(regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private static func extractRatio(in text: String) -> Double? {
        guard let regex = ratioRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let numR = Range(match.range(at: 1), in: text),
              let denR = Range(match.range(at: 2), in: text),
              let num = Double(text[numR]),
              let den = Double(text[denR]),
              den > 0 else {
            return nil
        }
        return min(1.0, max(0.0, num / den))
    }

    /// Built-in realistic diagnostic log lines covering all 6 core scenarios for instant UI preview.
    public static let sampleFaultLogLines: [(process: String, subsystem: String, message: String)] = [
        (
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute",
            message: "Token request to inference.issuer.apple.com failed with PrivateCloudComputeError Code=32033 (client region mismatch / untrusted egress)"
        ),
        (
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute",
            message: "OHTTP QUIC handshake to apple-relay.cloudflare.com:443 timed out over UDP (QUIC-BLOCK suspected)"
        ),
        (
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute",
            message: "PrivateCloudComputeError Code=1009 \"Rate-limited for token issuer based on retry-after header\""
        ),
        (
            process: "Photos",
            subsystem: "com.apple.GenerativeFunctionsFoundation",
            message: "[GenerativeFunctionsFoundation:Eligibility] Eligibility returned no CN region policy on a CH region code device"
        ),
        (
            process: "assistantd",
            subsystem: "com.apple.siri",
            message: "ADConnection error connecting to guzzoni.apple.com via 198.18.4.22 (connection reset by proxy)"
        ),
        (
            process: "modelmanagerd",
            subsystem: "com.apple.UnifiedAssetFramework",
            message: "UAF model asset download progress for com.apple.if.generative: 68.5% downloaded"
        )
    ]
}
