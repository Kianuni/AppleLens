import Foundation
import Observation
import os
import UserNotifications

public enum RadarOverallState: String, Codable, Sendable {
    case idle
    case onDevice
    case applePCC
    case externalLLM
    case hybrid

    public func label(lang: AppLanguage) -> String {
        switch self {
        case .idle:
            return tr("静默待命（零外部 AI 外连）", "Idle (No External AI Traffic)", lang: lang)
        case .onDevice:
            return tr("端侧本地推理 (On-Device ANE)", "On-Device Local Inference", lang: lang)
        case .applePCC:
            return tr("Apple PCC 私有云端通道", "Apple Private Cloud Compute", lang: lang)
        case .externalLLM:
            return tr("检测到第三方外部大模型外连", "External LLM Outbound Active", lang: lang)
        case .hybrid:
            return tr("多端并发（端云 + 外部 AI 混合）", "Hybrid AI Activity Active", lang: lang)
        }
    }

    public var sfSymbol: String {
        switch self {
        case .idle: return "dot.radiowaves.left.and.right"
        case .onDevice: return "cpu.fill"
        case .applePCC: return "lock.icloud.fill"
        case .externalLLM: return "network.badge.shield.half.filled"
        case .hybrid: return "sparkles.rectangle.stack.fill"
        }
    }
}

public enum AIActivityKind: String, Codable, Sendable {
    case onDevice
    case applePCC
    case externalAI
}

public struct AIActivityRecord: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let isIOSDevice: Bool
    public let deviceLabel: String
    public let kind: AIActivityKind
    public let titleZh: String
    public let titleEn: String
    public let processName: String
    public let detail: String
    public let routeBadge: String?

    public func title(lang: AppLanguage) -> String {
        tr(titleZh, titleEn, lang: lang)
    }
}

public struct IOSActiveAISession: Identifiable, Hashable, Sendable {
    public let id: String
    public let pid: Int32
    public let appName: String
    public let bundleID: String?
    public let provider: LLMProviderSpec
    public let statusZh: String
    public let statusEn: String
    public let routeBadge: String?
    public let lastSeenAt: Date
    public var isSuspended: Bool

    public func status(lang: AppLanguage) -> String {
        tr(statusZh, statusEn, lang: lang)
    }
}

public struct ActiveLLMConnection: Identifiable, Hashable, Sendable {
    public let id: String
    public let pid: Int32
    public let appName: String
    public let executableName: String
    public let bundleID: String?
    public let appBundlePath: String?
    public let identityKey: String
    public let provider: LLMProviderSpec
    public let matchedDomain: String
    public let remoteIP: String
    public let confidence: EndpointMatchConfidence
    public let isFakeIP: Bool
    public let isTrusted: Bool
    public let firstSeenAt: Date
}

public struct FirstSeenAlert: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let identityKey: String
    public let appName: String
    public let executableName: String
    public let providerNameZh: String
    public let providerNameEn: String
    public let matchedDomain: String
}

public final class FirstSeenProcessTracker: Sendable {
    private static let defaultsKey = "applelens.trustedProcesses"

    private struct State: Sendable {
        var trustedKeys: Set<String>
        var alertedThisSession: Set<String> = []
        var generation: UInt64 = 0
        var persistedGeneration: UInt64 = 0
    }

    private let stateLock: OSAllocatedUnfairLock<State>
    private let defaultsLock: OSAllocatedUnfairLock<UserDefaults>
    private let persistenceQueue = DispatchQueue(label: "com.kianuni.AppleLens.trustedProcesses.persistence")

    public init(defaults: UserDefaults = .standard) {
        let saved = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        self.stateLock = OSAllocatedUnfairLock(initialState: State(trustedKeys: Set(saved)))
        self.defaultsLock = OSAllocatedUnfairLock(uncheckedState: defaults)
    }

    public func isTrusted(_ identityKey: String) -> Bool {
        stateLock.withLock { $0.trustedKeys.contains(identityKey) }
    }

    public func trust(_ identityKey: String) {
        let targetGeneration = stateLock.withLock { state -> UInt64 in
            state.trustedKeys.insert(identityKey)
            state.generation &+= 1
            return state.generation
        }
        persistUpTo(generation: targetGeneration)
    }

    public func untrust(_ identityKey: String) {
        let targetGeneration = stateLock.withLock { state -> UInt64 in
            state.trustedKeys.remove(identityKey)
            state.generation &+= 1
            return state.generation
        }
        persistUpTo(generation: targetGeneration)
    }

    private func persistUpTo(generation targetGeneration: UInt64) {
        persistenceQueue.sync {
            let pending: (snapshot: [String], generation: UInt64)? = stateLock.withLock { state in
                guard state.persistedGeneration < targetGeneration || state.persistedGeneration < state.generation else {
                    return nil
                }
                return (Array(state.trustedKeys).sorted(), state.generation)
            }
            guard let pending else { return }

            let defaults = defaultsLock.withLockUnchecked { $0 }
            defaults.set(pending.snapshot, forKey: Self.defaultsKey)

            stateLock.withLock { state in
                if pending.generation > state.persistedGeneration {
                    state.persistedGeneration = pending.generation
                }
            }
        }
    }

    public func allTrustedKeys() -> [String] {
        stateLock.withLock { Array($0.trustedKeys).sorted() }
    }

    /// Returns true once per session when an untrusted process connects to an external LLM.
    public func shouldNotifyFirstSeen(identityKey: String) -> Bool {
        stateLock.withLock { state in
            if state.trustedKeys.contains(identityKey) || state.alertedThisSession.contains(identityKey) {
                return false
            }
            state.alertedThisSession.insert(identityKey)
            return true
        }
    }
}

public struct RadarSnapshot: Sendable {
    public let overallState: RadarOverallState
    public let isOnDeviceActive: Bool
    public let isPCCActive: Bool
    public let lastOnDeviceSignal: Date?
    public let lastPCCSignal: Date?
    public let activeLLMConnections: [ActiveLLMConnection]
    public let pccSocketCount: Int
    public let mappedDomainsCount: Int
    public let activeProxyPorts: [UInt16]
    public let scannedAt: Date
}

@MainActor
@Observable
public final class TriStateRadarCoordinator {
    public private(set) var overallState: RadarOverallState = .idle
    public private(set) var isTargetIOS: Bool = false
    public private(set) var isOnDeviceActive: Bool = false
    public private(set) var isPCCActive: Bool = false
    public private(set) var lastOnDeviceDetail: String = ""
    public private(set) var lastPCCDetail: String = ""
    public private(set) var lastOnDeviceSignal: Date?
    public private(set) var lastPCCSignal: Date?
    public private(set) var activeLLMConnections: [ActiveLLMConnection] = []
    public private(set) var iosActiveSessions: [IOSActiveAISession] = []
    public private(set) var activityRecords: [AIActivityRecord] = []
    public private(set) var recentTimeline: [String] = []
    public private(set) var firstSeenAlerts: [FirstSeenAlert] = []
    public private(set) var activeProxyPorts: [UInt16] = []
    public private(set) var mappedIPCount: Int = 0
    public private(set) var lastScanDate: Date?
    public private(set) var trustedProcessKeys: [String] = []
    public private(set) var currentPollIntervalSeconds: TimeInterval = 1.5
    public private(set) var isPausedForSystemSleep: Bool = false

    public let dnsMapper: DNSFakeIPMapper
    public let socketScanner: ProcessSocketScanner
    public let tracker: FirstSeenProcessTracker

    private var monitoringTask: Task<Void, Never>?
    private var firstSeenTimestamps: [String: Date] = [:]

    private var targetIOSInternal: Bool = false
    private var macOnDeviceSignal: Date?
    private var macOnDeviceDetail: String = ""
    private var macPCCSignal: Date?
    private var macPCCDetail: String = ""
    private var iosOnDeviceSignal: Date?
    private var iosOnDeviceDetail: String = ""
    private var iosLastHighPriorityOnDeviceAt: Date?
    private var iosPCCSignal: Date?
    private var iosPCCDetail: String = ""
    private var macConnectionsCache: [ActiveLLMConnection] = []
    private var iosSessionsMap: [String: IOSActiveAISession] = [:]
    private var activityThrottleMap: [String: Date] = [:]

    private var configuredActiveIntervalSeconds: TimeInterval = 1.5
    private var isUIVisible: Bool = true
    private var uiHiddenSince: Date?
    private var continuousIdleSince: Date?

    private let activeHoldSeconds: TimeInterval = 35
    private let iosActiveSessionExpirySeconds: TimeInterval = 300
    private let iosSuspendedSessionExpirySeconds: TimeInterval = 90

    private static let idleBackoffIntervalSeconds: TimeInterval = 5.0
    private static let idleBackoffDelaySeconds: TimeInterval = 60.0
    private static let cachePruneThreshold = 256
    private static let cacheHardCap = 512
    private static let cacheEntryTTL: TimeInterval = 3600

    private static let timelineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public init(
        dnsMapper: DNSFakeIPMapper = DNSFakeIPMapper(),
        socketScanner: ProcessSocketScanner = ProcessSocketScanner(),
        tracker: FirstSeenProcessTracker = FirstSeenProcessTracker()
    ) {
        self.dnsMapper = dnsMapper
        self.socketScanner = socketScanner
        self.tracker = tracker
        self.trustedProcessKeys = tracker.allTrustedKeys()
        self.continuousIdleSince = Date()
    }

    public func requestNotificationPermissionIfAppBundle() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func setTargetIOSMode(_ isIOS: Bool) {
        let now = Date()
        targetIOSInternal = isIOS
        pruneExpiredIOSSessions(now: now)
        applyViewState(buildCurrentViewState(now: now), now: now)
    }

    public func setUIVisible(_ visible: Bool) {
        let now = Date()
        if visible {
            isUIVisible = true
            uiHiddenSince = nil
            currentPollIntervalSeconds = configuredActiveIntervalSeconds
        } else {
            if isUIVisible {
                isUIVisible = false
                uiHiddenSince = now
            }
            updateAdaptivePollingInterval(now: now)
        }
    }

    public func setSystemSleeping(_ sleeping: Bool) {
        let wasSleeping = isPausedForSystemSleep
        isPausedForSystemSleep = sleeping
        if !sleeping {
            let now = Date()
            if !isUIVisible {
                uiHiddenSince = now
            }
            currentPollIntervalSeconds = configuredActiveIntervalSeconds
            if wasSleeping {
                Task { @MainActor [weak self] in
                    guard let self, !self.isPausedForSystemSleep else { return }
                    _ = await self.performSingleScan()
                }
            }
        }
    }

    public func clearActivityRecords(isIOS: Bool? = nil) {
        if let isIOS {
            activityRecords.removeAll { $0.isIOSDevice == isIOS }
        } else {
            activityRecords.removeAll()
        }
    }

    public func startMonitoring(intervalSeconds: TimeInterval = 1.5) {
        stopMonitoring()
        requestNotificationPermissionIfAppBundle()

        let clampedInterval = max(0.1, intervalSeconds)
        configuredActiveIntervalSeconds = clampedInterval
        updateAdaptivePollingInterval(now: Date())

        monitoringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastDNSRefreshDate: Date?
            if !self.isPausedForSystemSleep {
                await self.dnsMapper.refreshMappings()
                guard !Task.isCancelled else { return }
                lastDNSRefreshDate = Date()
                _ = await self.performSingleScan()
            }

            while !Task.isCancelled {
                let sleepDuration = self.currentPollIntervalSeconds
                try? await Task.sleep(for: .seconds(sleepDuration))
                guard !Task.isCancelled else { break }

                if self.isPausedForSystemSleep {
                    continue
                }

                let now = Date()
                let shouldRefreshDNS = lastDNSRefreshDate.map { now.timeIntervalSince($0) >= 90 } ?? true
                if shouldRefreshDNS {
                    await self.dnsMapper.refreshMappings()
                    guard !Task.isCancelled else { break }
                    if self.isPausedForSystemSleep {
                        continue
                    }
                    lastDNSRefreshDate = Date()
                }
                _ = await self.performSingleScan()
            }
        }
    }

    public func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    public func ingestUnifiedLogEvent(_ event: UnifiedLogEvent) {
        let now = Date()
        let isIOS = event.sourceDevice != "This Mac"
        let cleanProc = event.cleanProcessName
        let bodySnippet = Self.extractMessageBody(event.message)
        let routeBadge = Self.extractRouteBadge(from: event.message)
        var didUpdateState = false

        // 1. iOS third-party AI app detection from syslog_relay (Claude / ChatGPT / Gemini / DeepSeek / etc.)
        if isIOS {
            let bundleID = Self.extractBundleID(from: event.message)
            let matchedProvider: LLMProviderSpec?
            let extensionStatusOverride: (zh: String, en: String)?
            if let direct = LLMEndpointCatalog.matchIOSApp(bundleID: bundleID, processName: cleanProc) {
                matchedProvider = direct
                extensionStatusOverride = nil
            } else {
                let lowerProc = cleanProc.lowercased()
                let lowerMsg = event.message.lowercased()
                let isVisualOrSiriSystem = lowerProc.contains("assistant")
                    || lowerProc.contains("siri")
                    || lowerProc.contains("visualintelligence")
                    || lowerProc == "cameraoverlayangel"
                if isVisualOrSiriSystem && (lowerMsg.contains("chatgpt") || lowerMsg.contains("api.openai.com") || lowerMsg.contains("montara") || lowerMsg.contains("siriexternalai")) {
                    matchedProvider = LLMEndpointCatalog.providers.first(where: { $0.id == "openai" })
                    extensionStatusOverride = ("Siri / 视觉智能 · 询问 ChatGPT", "Siri / Visual Intelligence · Ask ChatGPT")
                } else {
                    matchedProvider = nil
                    extensionStatusOverride = nil
                }
            }

            if let matchedProvider {
                let suspended = Self.isSuspensionMessage(event.message)
                let shouldRecordActivity = !suspended && (extensionStatusOverride != nil || Self.isForegroundOrNetworkActivity(event: event))
                let activeZh = extensionStatusOverride?.zh ?? Self.iosStatusLabelZh(event: event, body: bodySnippet)
                let activeEn = extensionStatusOverride?.en ?? Self.iosStatusLabelEn(event: event, body: bodySnippet)
                let session = IOSActiveAISession(
                    id: matchedProvider.id,
                    pid: event.processID,
                    appName: matchedProvider.knownIOSProcessNames.first ?? cleanProc,
                    bundleID: bundleID,
                    provider: matchedProvider,
                    statusZh: suspended ? "已切入后台休眠" : activeZh,
                    statusEn: suspended ? "Suspended in background" : activeEn,
                    routeBadge: routeBadge ?? iosSessionsMap[matchedProvider.id]?.routeBadge,
                    lastSeenAt: now,
                    isSuspended: suspended
                )

                iosSessionsMap[matchedProvider.id] = session

                let throttleKey = "\(AIActivityKind.externalAI.rawValue)|\(matchedProvider.nameEn)|ios"
                if shouldRecordActivity, shouldRecordThrottledActivity(key: throttleKey, cooldown: 8, now: now) {
                    appendActivity(AIActivityRecord(
                        id: UUID(),
                        timestamp: now,
                        isIOSDevice: true,
                        deviceLabel: event.sourceDevice,
                        kind: .externalAI,
                        titleZh: matchedProvider.nameZh,
                        titleEn: matchedProvider.nameEn,
                        processName: cleanProc,
                        detail: activeZh + " · " + String(bodySnippet.prefix(120)),
                        routeBadge: routeBadge
                    ))
                    appendTimeline("[iPhone] \(matchedProvider.nameEn) (\(cleanProc))", now: now)
                }

                didUpdateState = true
            }
        }

        // 2. On-device AI / Photos Clean Up signal
        if event.isOnDeviceInferenceSignal {
            let feature = event.recognizedFeatureTitle ?? ("端侧本地推理 (ANE)", "On-Device Inference")
            let detailLine = "\(feature.zh) — \(cleanProc): \(String(bodySnippet.prefix(140)))"
            let isHighPriorityFeature = event.isPhotosCleanUpSignal || event.isVisualIntelligenceSignal
            let throttleKey = "\(AIActivityKind.onDevice.rawValue)|\(feature.en)|\(isIOS ? "ios" : "mac")"

            if isIOS {
                iosOnDeviceSignal = now
                if isHighPriorityFeature {
                    iosLastHighPriorityOnDeviceAt = now
                    iosOnDeviceDetail = detailLine
                } else if iosLastHighPriorityOnDeviceAt.map({ now.timeIntervalSince($0) >= 20 }) ?? true {
                    iosOnDeviceDetail = detailLine
                }
            } else {
                macOnDeviceSignal = now
                macOnDeviceDetail = detailLine
            }

            if shouldRecordThrottledActivity(key: throttleKey, cooldown: 5, now: now) {
                appendActivity(AIActivityRecord(
                    id: UUID(),
                    timestamp: now,
                    isIOSDevice: isIOS,
                    deviceLabel: event.sourceDevice,
                    kind: .onDevice,
                    titleZh: feature.zh,
                    titleEn: feature.en,
                    processName: cleanProc,
                    detail: String(bodySnippet.prefix(140)),
                    routeBadge: routeBadge
                ))
                appendTimeline("\(isIOS ? "[iPhone] " : "")\(cleanProc) · \(feature.en)", now: now)
            }
            didUpdateState = true
        }

        // 3. Apple PCC signal
        if event.isPCCSignal {
            let feature: (zh: String, en: String) = event.isPhotosCleanUpSignal
                ? ("相册 · 高质量消除 (PCC)", "Photos Clean Up (PCC)")
                : ("Apple PCC 私有云推理", "Apple PCC Inference")
            let detailLine = "\(feature.zh) — \(cleanProc): \(String(bodySnippet.prefix(140)))"
            let throttleKey = "\(AIActivityKind.applePCC.rawValue)|\(feature.en)|\(isIOS ? "ios" : "mac")"

            if isIOS {
                iosPCCSignal = now
                iosPCCDetail = detailLine
            } else {
                macPCCSignal = now
                macPCCDetail = detailLine
            }

            if shouldRecordThrottledActivity(key: throttleKey, cooldown: 5, now: now) {
                appendActivity(AIActivityRecord(
                    id: UUID(),
                    timestamp: now,
                    isIOSDevice: isIOS,
                    deviceLabel: event.sourceDevice,
                    kind: .applePCC,
                    titleZh: feature.zh,
                    titleEn: feature.en,
                    processName: cleanProc,
                    detail: String(bodySnippet.prefix(140)),
                    routeBadge: routeBadge
                ))
                appendTimeline("\(isIOS ? "[iPhone] " : "")\(cleanProc) · \(feature.en)", now: now)
            }
            didUpdateState = true
        }

        if didUpdateState {
            pruneExpiredIOSSessions(now: now)
            applyViewState(buildCurrentViewState(now: now), now: now)
        }
    }

    private enum ScannedSocketOutcome: Sendable {
        case applePCC(appName: String, domain: String, remoteIP: String)
        case externalLLM(
            dedupKey: String,
            pid: Int32,
            appName: String,
            executableName: String,
            bundleID: String?,
            appBundlePath: String?,
            identityKey: String,
            provider: LLMProviderSpec,
            matchedDomain: String,
            remoteIP: String,
            confidence: EndpointMatchConfidence,
            isFakeIP: Bool
        )
    }

    private struct DetachedScanPayload: Sendable {
        let proxyPortList: [UInt16]
        let mappedCount: Int
        let outcomes: [ScannedSocketOutcome]
    }

    @discardableResult
    public func performSingleScan() async -> RadarSnapshot {
        if dnsMapper.lastRefreshDate == nil {
            await dnsMapper.refreshMappings()
        }

        let isIOSModeAtStart = targetIOSInternal
        let scanner = socketScanner
        let mapper = dnsMapper

        let payload = await Task.detached(priority: .utility) { () -> DetachedScanPayload in
            let proxyInfo = SystemProxyInfo.current()
            let localProxyPorts = proxyInfo.activeLocalProxyPorts
            let proxyPortList = Array(localProxyPorts).sorted()
            let mappedCount = mapper.mappedEntryCount

            guard !isIOSModeAtStart else {
                return DetachedScanPayload(
                    proxyPortList: proxyPortList,
                    mappedCount: mappedCount,
                    outcomes: []
                )
            }

            let rawSockets = scanner.scanActiveOutboundSockets(localProxyPorts: localProxyPorts)
            var outcomes: [ScannedSocketOutcome] = []
            outcomes.reserveCapacity(rawSockets.count)

            for sock in rawSockets {
                if let match = mapper.match(
                    remoteIP: sock.remoteIP,
                    executableName: sock.metadata.executableName,
                    bundleID: sock.metadata.bundleID
                ) {
                    if match.provider.category == .applePCC {
                        outcomes.append(.applePCC(
                            appName: sock.metadata.appName,
                            domain: match.matchedDomain,
                            remoteIP: sock.remoteIP
                        ))
                    } else {
                        let dedupKey = "\(sock.metadata.identityKey)|\(match.provider.id)|\(sock.remoteIP)"
                        outcomes.append(.externalLLM(
                            dedupKey: dedupKey,
                            pid: sock.pid,
                            appName: sock.metadata.appName,
                            executableName: sock.metadata.executableName,
                            bundleID: sock.metadata.bundleID,
                            appBundlePath: sock.metadata.appBundlePath,
                            identityKey: sock.metadata.identityKey,
                            provider: match.provider,
                            matchedDomain: match.matchedDomain,
                            remoteIP: sock.remoteIP,
                            confidence: match.confidence,
                            isFakeIP: match.isFakeIP
                        ))
                    }
                } else if localProxyPorts.contains(sock.remotePort),
                          SystemProxyInfo.isLoopback(sock.remoteIP),
                          let bundleID = sock.metadata.bundleID,
                          let mappedProvider = Self.providerForDedicatedClientBundle(bundleID) {
                    let dedupKey = "\(sock.metadata.identityKey)|\(mappedProvider.id)|proxy:\(sock.remotePort)"
                    outcomes.append(.externalLLM(
                        dedupKey: dedupKey,
                        pid: sock.pid,
                        appName: sock.metadata.appName,
                        executableName: sock.metadata.executableName,
                        bundleID: sock.metadata.bundleID,
                        appBundlePath: sock.metadata.appBundlePath,
                        identityKey: sock.metadata.identityKey,
                        provider: mappedProvider,
                        matchedDomain: mappedProvider.domains.first ?? "proxy:\(sock.remotePort)",
                        remoteIP: "\(sock.remoteIP):\(sock.remotePort)",
                        confidence: .systemProxyKnownClient,
                        isFakeIP: false
                    ))
                }
            }

            return DetachedScanPayload(
                proxyPortList: proxyPortList,
                mappedCount: mappedCount,
                outcomes: outcomes
            )
        }.value

        let now = Date()

        if isIOSModeAtStart {
            pruneExpiredIOSSessions(now: now)
            let snapshot = buildCurrentViewState(now: now)
            applyViewState(snapshot, now: now)
            activeProxyPorts = payload.proxyPortList
            mappedIPCount = payload.mappedCount
            lastScanDate = now

            return RadarSnapshot(
                overallState: snapshot.overallState,
                isOnDeviceActive: snapshot.isOnDeviceActive,
                isPCCActive: snapshot.isPCCActive,
                lastOnDeviceSignal: snapshot.lastOnDeviceSignal,
                lastPCCSignal: snapshot.lastPCCSignal,
                activeLLMConnections: [],
                pccSocketCount: 0,
                mappedDomainsCount: payload.mappedCount,
                activeProxyPorts: payload.proxyPortList,
                scannedAt: now
            )
        }

        var pccHits = 0
        var dedupMap: [String: ActiveLLMConnection] = [:]

        for outcome in payload.outcomes {
            switch outcome {
            case let .applePCC(appName, domain, remoteIP):
                pccHits += 1
                macPCCSignal = now
                macPCCDetail = "\(appName) -> \(domain) (\(remoteIP))"
            case let .externalLLM(
                dedupKey, pid, appName, executableName, bundleID, appBundlePath,
                identityKey, provider, matchedDomain, remoteIP, confidence, isFakeIP
            ):
                if dedupMap[dedupKey] == nil {
                    let firstSeen = recordFirstSeenTimestamp(for: dedupKey, now: now)
                    let trusted = tracker.isTrusted(identityKey)
                    dedupMap[dedupKey] = ActiveLLMConnection(
                        id: dedupKey,
                        pid: pid,
                        appName: appName,
                        executableName: executableName,
                        bundleID: bundleID,
                        appBundlePath: appBundlePath,
                        identityKey: identityKey,
                        provider: provider,
                        matchedDomain: matchedDomain,
                        remoteIP: remoteIP,
                        confidence: confidence,
                        isFakeIP: isFakeIP,
                        isTrusted: trusted,
                        firstSeenAt: firstSeen
                    )
                }
            }
        }

        let sortedConnections = dedupMap.values.sorted {
            if $0.appName != $1.appName { return $0.appName < $1.appName }
            return $0.provider.id < $1.provider.id
        }

        // Record throttled Mac external LLM sessions in the activity log
        for conn in sortedConnections {
            let throttleKey = "\(AIActivityKind.externalAI.rawValue)|\(conn.appName)|\(conn.provider.id)|mac"
            if shouldRecordThrottledActivity(key: throttleKey, cooldown: 30, now: now) {
                appendActivity(AIActivityRecord(
                    id: UUID(),
                    timestamp: now,
                    isIOSDevice: false,
                    deviceLabel: "This Mac",
                    kind: .externalAI,
                    titleZh: "\(conn.appName) -> \(conn.provider.nameZh)",
                    titleEn: "\(conn.appName) -> \(conn.provider.nameEn)",
                    processName: conn.executableName,
                    detail: "\(conn.matchedDomain) (\(conn.confidence.label(lang: .en)))",
                    routeBadge: conn.isFakeIP ? "Fake-IP" : nil
                ))
            }
        }

        var newlyAlerted: [FirstSeenAlert] = []
        for conn in sortedConnections where !conn.isTrusted {
            if tracker.shouldNotifyFirstSeen(identityKey: conn.identityKey) {
                let alert = FirstSeenAlert(
                    id: UUID(),
                    timestamp: now,
                    identityKey: conn.identityKey,
                    appName: conn.appName,
                    executableName: conn.executableName,
                    providerNameZh: conn.provider.nameZh,
                    providerNameEn: conn.provider.nameEn,
                    matchedDomain: conn.matchedDomain
                )
                newlyAlerted.append(alert)
                postNotificationIfAppBundle(alert: alert)
                appendTimeline("[First-Seen] \(conn.appName) -> \(conn.provider.nameEn) (\(conn.matchedDomain))", now: now)
            }
        }

        macConnectionsCache = sortedConnections
        let snapshot = buildCurrentViewState(now: now)
        applyViewState(snapshot, now: now)
        if !newlyAlerted.isEmpty {
            firstSeenAlerts.insert(contentsOf: newlyAlerted, at: 0)
            if firstSeenAlerts.count > 20 {
                firstSeenAlerts = Array(firstSeenAlerts.prefix(20))
            }
        }
        activeProxyPorts = payload.proxyPortList
        mappedIPCount = payload.mappedCount
        lastScanDate = now

        return RadarSnapshot(
            overallState: snapshot.overallState,
            isOnDeviceActive: snapshot.isOnDeviceActive,
            isPCCActive: snapshot.isPCCActive,
            lastOnDeviceSignal: snapshot.lastOnDeviceSignal,
            lastPCCSignal: snapshot.lastPCCSignal,
            activeLLMConnections: sortedConnections,
            pccSocketCount: pccHits,
            mappedDomainsCount: payload.mappedCount,
            activeProxyPorts: payload.proxyPortList,
            scannedAt: now
        )
    }

    public func trustProcess(identityKey: String) {
        tracker.trust(identityKey)
        trustedProcessKeys = tracker.allTrustedKeys()
        firstSeenAlerts.removeAll { $0.identityKey == identityKey }
        activeLLMConnections = Self.updatingTrustedState(
            in: activeLLMConnections,
            identityKey: identityKey,
            isTrusted: true
        )
        macConnectionsCache = Self.updatingTrustedState(
            in: macConnectionsCache,
            identityKey: identityKey,
            isTrusted: true
        )
    }

    public func untrustProcess(identityKey: String) {
        tracker.untrust(identityKey)
        trustedProcessKeys = tracker.allTrustedKeys()
        activeLLMConnections = Self.updatingTrustedState(
            in: activeLLMConnections,
            identityKey: identityKey,
            isTrusted: false
        )
        macConnectionsCache = Self.updatingTrustedState(
            in: macConnectionsCache,
            identityKey: identityKey,
            isTrusted: false
        )
    }

    private static func updatingTrustedState(
        in connections: [ActiveLLMConnection],
        identityKey: String,
        isTrusted: Bool
    ) -> [ActiveLLMConnection] {
        connections.map { conn in
            guard conn.identityKey == identityKey else { return conn }
            return ActiveLLMConnection(
                id: conn.id,
                pid: conn.pid,
                appName: conn.appName,
                executableName: conn.executableName,
                bundleID: conn.bundleID,
                appBundlePath: conn.appBundlePath,
                identityKey: conn.identityKey,
                provider: conn.provider,
                matchedDomain: conn.matchedDomain,
                remoteIP: conn.remoteIP,
                confidence: conn.confidence,
                isFakeIP: conn.isFakeIP,
                isTrusted: isTrusted,
                firstSeenAt: conn.firstSeenAt
            )
        }
    }

    public func dismissAlert(_ alertID: UUID) {
        firstSeenAlerts.removeAll { $0.id == alertID }
    }

    // MARK: - Target-Isolated State Derivation

    private struct RadarViewStateSnapshot: Sendable {
        let isTargetIOS: Bool
        let overallState: RadarOverallState
        let isOnDeviceActive: Bool
        let isPCCActive: Bool
        let lastOnDeviceSignal: Date?
        let lastOnDeviceDetail: String
        let lastPCCSignal: Date?
        let lastPCCDetail: String
        let macConnections: [ActiveLLMConnection]
        let iosSessions: [IOSActiveAISession]
    }

    private func pruneExpiredIOSSessions(now: Date) {
        iosSessionsMap = iosSessionsMap.filter { _, session in
            let maxAge = session.isSuspended ? iosSuspendedSessionExpirySeconds : iosActiveSessionExpirySeconds
            return now.timeIntervalSince(session.lastSeenAt) <= maxAge
        }
    }

    private func buildCurrentViewState(now: Date) -> RadarViewStateSnapshot {
        let onDevTS = targetIOSInternal ? iosOnDeviceSignal : macOnDeviceSignal
        let onDevDetail = targetIOSInternal ? iosOnDeviceDetail : macOnDeviceDetail
        let pccTS = targetIOSInternal ? iosPCCSignal : macPCCSignal
        let pccDetail = targetIOSInternal ? iosPCCDetail : macPCCDetail

        let onDevActive = onDevTS.map { now.timeIntervalSince($0) <= activeHoldSeconds } ?? false
        let pccActive = pccTS.map { now.timeIntervalSince($0) <= activeHoldSeconds } ?? false

        let sortedIOSSessions = iosSessionsMap.values.sorted { $0.lastSeenAt > $1.lastSeenAt }
        let extActive = targetIOSInternal
            ? sortedIOSSessions.contains(where: { !$0.isSuspended })
            : !macConnectionsCache.isEmpty

        let activeModeCount = [onDevActive, pccActive, extActive].filter { $0 }.count
        let state: RadarOverallState
        if activeModeCount >= 2 {
            state = .hybrid
        } else if extActive {
            state = .externalLLM
        } else if pccActive {
            state = .applePCC
        } else if onDevActive {
            state = .onDevice
        } else {
            state = .idle
        }

        return RadarViewStateSnapshot(
            isTargetIOS: targetIOSInternal,
            overallState: state,
            isOnDeviceActive: onDevActive,
            isPCCActive: pccActive,
            lastOnDeviceSignal: onDevTS,
            lastOnDeviceDetail: onDevDetail,
            lastPCCSignal: pccTS,
            lastPCCDetail: pccDetail,
            macConnections: targetIOSInternal ? [] : macConnectionsCache,
            iosSessions: sortedIOSSessions
        )
    }

    private func applyViewState(_ snapshot: RadarViewStateSnapshot, now: Date = Date()) {
        isTargetIOS = snapshot.isTargetIOS
        overallState = snapshot.overallState
        isOnDeviceActive = snapshot.isOnDeviceActive
        isPCCActive = snapshot.isPCCActive
        lastOnDeviceSignal = snapshot.lastOnDeviceSignal
        lastOnDeviceDetail = snapshot.lastOnDeviceDetail
        lastPCCSignal = snapshot.lastPCCSignal
        lastPCCDetail = snapshot.lastPCCDetail
        activeLLMConnections = snapshot.macConnections
        iosActiveSessions = snapshot.iosSessions
        updateAdaptivePollingInterval(now: now)
    }

    private func updateAdaptivePollingInterval(now: Date) {
        if overallState != .idle {
            continuousIdleSince = nil
            if currentPollIntervalSeconds != configuredActiveIntervalSeconds {
                currentPollIntervalSeconds = configuredActiveIntervalSeconds
            }
            return
        }

        if continuousIdleSince == nil {
            continuousIdleSince = now
        }

        guard !isUIVisible,
              let uiHiddenSince,
              let idleSince = continuousIdleSince else {
            if currentPollIntervalSeconds != configuredActiveIntervalSeconds {
                currentPollIntervalSeconds = configuredActiveIntervalSeconds
            }
            return
        }

        let idleAndHiddenSince = max(uiHiddenSince, idleSince)
        if now.timeIntervalSince(idleAndHiddenSince) >= Self.idleBackoffDelaySeconds {
            let backedOff = max(configuredActiveIntervalSeconds, Self.idleBackoffIntervalSeconds)
            if currentPollIntervalSeconds != backedOff {
                currentPollIntervalSeconds = backedOff
            }
        } else if currentPollIntervalSeconds != configuredActiveIntervalSeconds {
            currentPollIntervalSeconds = configuredActiveIntervalSeconds
        }
    }

    private func appendActivity(_ record: AIActivityRecord) {
        activityRecords.insert(record, at: 0)
        if activityRecords.count > 80 {
            activityRecords = Array(activityRecords.prefix(80))
        }
    }

    // MARK: - iOS Syslog Parsing Helpers

    private static func extractBundleID(from message: String) -> String? {
        for marker in ["app<", "application<"] {
            if let range = message.range(of: marker) {
                let tail = message[range.upperBound...]
                if let endIdx = tail.firstIndex(where: { $0 == "(" || $0 == ">" || $0 == ":" }) {
                    let candidate = String(tail[..<endIdx])
                    if candidate.contains(".") {
                        return candidate
                    }
                }
            }
        }
        if let sceneRange = message.range(of: "sceneID:", options: [.caseInsensitive]) {
            let tail = message[sceneRange.upperBound...]
            let delimiters: Set<Character> = ["-", " ", ")", "]", ">", ";"]
            let endIdx = tail.firstIndex(where: { delimiters.contains($0) }) ?? tail.endIndex
            let candidate = String(tail[..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.contains(".") {
                return candidate
            }
        }
        return nil
    }

    private static func extractRouteBadge(from message: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("utun") { return "utun 代理隧道" }
        if lower.contains("uses wifi") || lower.contains("interface: en") { return "Wi-Fi" }
        if lower.contains("pdp_ip") || lower.contains("cellular") { return "蜂窝网络" }
        return nil
    }

    private static func extractMessageBody(_ rawLine: String) -> String {
        if let marker = rawLine.range(of: ">: ") {
            return String(rawLine[marker.upperBound...])
        }
        return rawLine
    }

    private static func isSuspensionMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("running-active")
            || lower.contains("userinteractivefocal")
            || lower.contains("state to: running") {
            return false
        }
        return lower.contains("running-suspended")
            || lower.contains("setting process task state to: suspended")
            || lower.contains("role: noninteractive")
            || lower.contains("role: background")
    }

    private static func isForegroundOrNetworkActivity(event: UnifiedLogEvent) -> Bool {
        let sub = event.subsystem.lowercased()
        let proc = event.cleanProcessName.lowercased()
        let msg = event.message.lowercased()
        if sub == "cfnetwork" || sub == "network" || sub.contains("boringssl") || sub.contains("quic") {
            return true
        }
        if proc != "runningboardd" && proc != "springboard" && proc != "dasd" {
            return true
        }
        return msg.contains("running-active")
            || msg.contains("foreground")
            || msg.contains("acquired assertion")
            || msg.contains("setting process task state to: running")
    }

    private static func iosStatusLabelZh(event: UnifiedLogEvent, body: String) -> String {
        let sub = event.subsystem.lowercased()
        let lower = body.lowercased()
        if lower.contains("tls") || sub == "cfnetwork" || sub == "network" {
            return "TLS / HTTPS :443 活跃"
        }
        return "前台 / 网络活跃"
    }

    private static func iosStatusLabelEn(event: UnifiedLogEvent, body: String) -> String {
        let sub = event.subsystem.lowercased()
        let lower = body.lowercased()
        if lower.contains("tls") || sub == "cfnetwork" || sub == "network" {
            return "HTTPS :443 / TLS Active"
        }
        return "Foreground Active"
    }

    private func shouldRecordThrottledActivity(key: String, cooldown: TimeInterval, now: Date) -> Bool {
        if let last = activityThrottleMap[key], now.timeIntervalSince(last) < cooldown {
            return false
        }
        activityThrottleMap[key] = now
        Self.pruneTimestampCache(&activityThrottleMap, now: now)
        return true
    }

    private func recordFirstSeenTimestamp(for key: String, now: Date) -> Date {
        if let existing = firstSeenTimestamps[key] {
            return existing
        }
        firstSeenTimestamps[key] = now
        Self.pruneTimestampCache(&firstSeenTimestamps, now: now)
        return now
    }

    private static func pruneTimestampCache(_ cache: inout [String: Date], now: Date) {
        guard cache.count > cachePruneThreshold else { return }
        cache = cache.filter { now.timeIntervalSince($0.value) <= cacheEntryTTL }
        if cache.count > cacheHardCap {
            let newest = cache.sorted { $0.value > $1.value }.prefix(cacheHardCap)
            cache = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
    }

    nonisolated private static func providerForDedicatedClientBundle(_ bundleID: String) -> LLMProviderSpec? {
        for provider in LLMEndpointCatalog.providers where provider.knownClientBundleIDs.contains(bundleID) {
            return provider
        }
        return nil
    }

    private func appendTimeline(_ entry: String, now: Date = Date()) {
        let line = "[\(Self.timelineFormatter.string(from: now))] \(entry)"
        recentTimeline.insert(line, at: 0)
        if recentTimeline.count > 40 {
            recentTimeline = Array(recentTimeline.prefix(40))
        }
    }

    private func postNotificationIfAppBundle(alert: FirstSeenAlert) {
        // CRITICAL: Never invoke UNUserNotificationCenter outside a .app bundle (crashes CLI & swift test).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        let lang = LanguageManager.shared.current
        content.title = tr(
            "AppleLens：陌生进程首次外连大模型",
            "AppleLens: First-Time External LLM Connection",
            lang: lang
        )
        content.body = tr(
            "\(alert.appName) (\(alert.executableName)) 正在连接 \(alert.providerNameZh) [\(alert.matchedDomain)]",
            "\(alert.appName) (\(alert.executableName)) connected to \(alert.providerNameEn) [\(alert.matchedDomain)]",
            lang: lang
        )
        let req = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
