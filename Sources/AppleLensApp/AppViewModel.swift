import AppKit
import AppleLensCore
import Foundation
import Observation
import os
import ServiceManagement
import UniformTypeIdentifiers

enum TargetDeviceMode: String, CaseIterable, Identifiable, Sendable {
    case thisMac
    case usbIPhone

    var id: String { rawValue }

    func label(lang: AppLanguage) -> String {
        switch self {
        case .thisMac: return tr("本机 Mac", "This Mac", lang: lang)
        case .usbIPhone: return tr("USB 连接 iPhone", "Connected iPhone", lang: lang)
        }
    }

    var sfSymbol: String {
        switch self {
        case .thisMac: return "laptopcomputer"
        case .usbIPhone: return "iphone"
        }
    }
}

enum WorkbenchTab: String, CaseIterable, Identifiable, Sendable {
    case radar
    case diagnostics
    case probe
    case reportLens

    var id: String { rawValue }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .radar: return tr("实时三态雷达", "Tri-State Radar", lang: lang)
        case .diagnostics: return tr("日志与故障诊断", "Log Diagnostics", lang: lang)
        case .probe: return tr("四路预检探针", "Pre-Flight Probe", lang: lang)
        case .reportLens: return tr("透明报告解码", "Report Lens", lang: lang)
        }
    }

    var sfSymbol: String {
        switch self {
        case .radar: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "stethoscope"
        case .probe: return "antenna.radiowaves.left.and.right"
        case .reportLens: return "doc.text.magnifyingglass"
        }
    }
}

enum ReportInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case promptsAndTools
    case attestationAndX509
    case sealedHashesAndJSON

    var id: String { rawValue }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .promptsAndTools:
            return tr("AFM 提示词与工具", "AFM Prompts & Tools", lang: lang)
        case .attestationAndX509:
            return tr("CloudAttestation 与证书链", "CloudAttestation & X.509", lang: lang)
        case .sealedHashesAndJSON:
            return tr("SealedHash 账本与原始 JSON", "SealedHash & Raw JSON", lang: lang)
        }
    }
}

@MainActor
@Observable
final class AppViewModel {
    let language = LanguageManager.shared
    let radar = TriStateRadarCoordinator()
    let logStream = UnifiedLogStreamService()
    let usbBridge = USBiPhoneLogBridge()
    let probeEngine = RoutingProbeEngine()

    var selectedTab: WorkbenchTab = .radar {
        didSet {
            if selectedTab == .reportLens {
                refreshLatestDownloadsReport()
            }
        }
    }
    var targetDeviceMode: TargetDeviceMode = .thisMac

    // Visibility, Dock Auto-Hide & Launch at Login
    var isWorkbenchVisible: Bool = false
    var isPopoverVisible: Bool = false
    var hideDockWhenClosed: Bool {
        didSet {
            UserDefaults.standard.set(hideDockWhenClosed, forKey: Self.hideDockWhenClosedKey)
            applyDockVisibilityPolicy()
        }
    }
    var isLaunchAtLoginEnabled: Bool = false

    // Manual update check
    var isCheckingUpdate: Bool = false
    var updateStatusMessage: String?
    var latestReleaseURL: String?

    // USB iPhone state
    var connectedDevices: [ConnectedIOSDevice] = []
    var selectedDeviceUDID: String?

    // Diagnostics state (independent per target device)
    var isMacLiveStreaming: Bool = false
    var isIOSLiveStreaming: Bool = false
    var isMacLiveStreamDesired: Bool = true
    var isIOSLiveStreamDesired: Bool = true
    var isScanningHistory: Bool = false
    var macStreamError: String?
    var iosStreamError: String?
    var diagnosticsStatusNotice: String?
    var diagnosticFindings: [DiagnosticFinding] = []
    var rawLogEvents: [UnifiedLogEvent] = []
    var logSearchQuery: String = ""
    var severityFilter: DiagnosticSeverity?

    @ObservationIgnored private var pendingLiveEvents: [UnifiedLogEvent] = []
    @ObservationIgnored private var pendingFlushTask: Task<Void, Never>?
    @ObservationIgnored private let sleepWakeTokensLock = OSAllocatedUnfairLock(uncheckedState: [NSObjectProtocol]())

    var isLiveStreaming: Bool {
        targetDeviceMode == .thisMac ? isMacLiveStreaming : isIOSLiveStreaming
    }

    var isLiveStreamDesired: Bool {
        targetDeviceMode == .thisMac ? isMacLiveStreamDesired : isIOSLiveStreamDesired
    }

    var streamError: String? {
        get { targetDeviceMode == .thisMac ? macStreamError : iosStreamError }
        set {
            if targetDeviceMode == .thisMac {
                macStreamError = newValue
            } else {
                iosStreamError = newValue
            }
        }
    }

    var currentTargetFindingsCount: Int {
        diagnosticFindings.filter { matchesCurrentTarget(sourceDevice: $0.sourceDevice) }.count
    }

    // Probe state
    var isProbing: Bool = false
    var probeReport: FullProbeReport?
    var revealFullIPs: Bool = false
    var customProxyInput: String = ""
    var customProxyScheme: CustomProxyConfig.ProxyScheme = .http
    var customProxyValidationError: String?
    var lastProbeCustomProxySummary: String?

    // ReportLens state
    var currentReport: ParsedAppleIntelligenceReport?
    var isShowingDemoReport: Bool = false
    var selectedRequestID: String?
    var selectedReportInspectorTab: ReportInspectorTab = .promptsAndTools
    var reportError: String?
    var latestDownloadsReportURL: URL?

    var lang: AppLanguage { language.current }
    var isUSBFrameworkAvailable: Bool { usbBridge.isFrameworkAvailable }

    var activeConnectedDevice: ConnectedIOSDevice? {
        if let udid = selectedDeviceUDID,
           let matched = connectedDevices.first(where: { $0.id == udid }) {
            return matched
        }
        return connectedDevices.first
    }

    var selectedRequest: ParsedModelRequestItem? {
        guard let requests = currentReport?.requests, !requests.isEmpty else { return nil }
        if let selectedRequestID,
           let matched = requests.first(where: { $0.id == selectedRequestID }) {
            return matched
        }
        return requests.first
    }

    private func matchesCurrentTarget(sourceDevice: String) -> Bool {
        if sourceDevice == "Simulated Lab" || sourceDevice.hasPrefix("Imported (") {
            return true
        }
        switch targetDeviceMode {
        case .thisMac:
            return sourceDevice == "This Mac"
        case .usbIPhone:
            return sourceDevice != "This Mac"
        }
    }

    var filteredFindings: [DiagnosticFinding] {
        let query = logSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return diagnosticFindings.filter { finding in
            guard matchesCurrentTarget(sourceDevice: finding.sourceDevice) else {
                return false
            }
            if let severityFilter, finding.severity != severityFilter {
                return false
            }
            guard !query.isEmpty else { return true }
            return finding.titleZh.lowercased().contains(query)
                || finding.titleEn.lowercased().contains(query)
                || finding.rawLine.lowercased().contains(query)
                || finding.processName.lowercased().contains(query)
                || finding.code.rawValue.lowercased().contains(query)
        }
    }

    var filteredRawEvents: [UnifiedLogEvent] {
        let query = logSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rawLogEvents.filter { ev in
            guard matchesCurrentTarget(sourceDevice: ev.sourceDevice) else {
                return false
            }
            guard !query.isEmpty else { return true }
            return ev.processName.lowercased().contains(query)
                || ev.subsystem.lowercased().contains(query)
                || ev.message.lowercased().contains(query)
                || ev.sourceDevice.lowercased().contains(query)
        }
    }

    var filteredActivityRecords: [AIActivityRecord] {
        let wantIOS = (targetDeviceMode == .usbIPhone)
        return radar.activityRecords.filter { $0.isIOSDevice == wantIOS }
    }

    var menuBarBadgeText: String? {
        switch radar.overallState {
        case .idle:
            return nil
        case .onDevice:
            return tr("端侧", "ANE", lang: lang)
        case .applePCC:
            return "PCC"
        case .externalLLM:
            if targetDeviceMode == .usbIPhone {
                let count = radar.iosActiveSessions.filter { !$0.isSuspended }.count
                return count > 0 ? "iOS·\(count)" : "iOS"
            }
            let count = radar.activeLLMConnections.count
            return count > 0 ? "LLM·\(count)" : "LLM"
        case .hybrid:
            return tr("混合", "Hybrid", lang: lang)
        }
    }

    private static let targetModeDefaultsKey = "applelens.targetDeviceMode"
    private static let macLiveStreamDesiredKey = "applelens.liveStreamEnabled.mac"
    private static let iosLiveStreamDesiredKey = "applelens.liveStreamEnabled.ios"
    private static let hideDockWhenClosedKey = "applelens.hideDockWhenClosed"

    init() {
        self.hideDockWhenClosed = UserDefaults.standard.bool(forKey: Self.hideDockWhenClosedKey)

        usbBridge.onDevicesChanged = { [weak self] devices in
            Task { @MainActor [weak self] in
                self?.handleDevicesChanged(devices)
            }
        }
        usbBridge.onStatusMessage = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.iosStreamError = message
            }
        }

        usbBridge.startDeviceDiscovery()
        let initial = usbBridge.currentDevices
        connectedDevices = initial
        selectedDeviceUDID = initial.first?.id

        if UserDefaults.standard.string(forKey: Self.targetModeDefaultsKey) == TargetDeviceMode.usbIPhone.rawValue,
           !initial.isEmpty {
            targetDeviceMode = .usbIPhone
        }
        if UserDefaults.standard.object(forKey: Self.macLiveStreamDesiredKey) != nil {
            isMacLiveStreamDesired = UserDefaults.standard.bool(forKey: Self.macLiveStreamDesiredKey)
        }
        if UserDefaults.standard.object(forKey: Self.iosLiveStreamDesiredKey) != nil {
            isIOSLiveStreamDesired = UserDefaults.standard.bool(forKey: Self.iosLiveStreamDesiredKey)
        }

        refreshLaunchAtLoginStatus()
        refreshLatestDownloadsReport()
        observeSystemSleepWake()

        radar.setTargetIOSMode(targetDeviceMode == .usbIPhone)
        radar.startMonitoring(intervalSeconds: 1.5)
        syncDesiredStreams()
    }

    deinit {
        sleepWakeTokensLock.withLockUnchecked { tokens in
            let center = NSWorkspace.shared.notificationCenter
            for token in tokens {
                center.removeObserver(token)
            }
            tokens.removeAll()
        }
    }

    private func observeSystemSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepToken = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }
        let wakeToken = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemDidWake()
            }
        }
        sleepWakeTokensLock.withLockUnchecked { tokens in
            tokens.append(sleepToken)
            tokens.append(wakeToken)
        }
    }

    private func handleSystemWillSleep() {
        if isMacLiveStreaming {
            stopMacLiveStream()
        }
        if isIOSLiveStreaming {
            stopIOSLiveStream()
        }
        radar.setSystemSleeping(true)
    }

    private func handleSystemDidWake() {
        radar.setSystemSleeping(false)
        syncDesiredStreams()
    }

    func setWorkbenchVisible(_ visible: Bool) {
        guard isWorkbenchVisible != visible else { return }
        isWorkbenchVisible = visible
        radar.setUIVisible(isWorkbenchVisible || isPopoverVisible)
        applyDockVisibilityPolicy()
    }

    func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        if visible {
            refreshLaunchAtLoginStatus()
        }
        radar.setUIVisible(isWorkbenchVisible || isPopoverVisible)
    }

    func prepareForWorkbenchOpen() {
        if NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func applyDockVisibilityPolicy() {
        let app = NSApplication.shared
        if hideDockWhenClosed && !isWorkbenchVisible {
            if app.activationPolicy() != .accessory {
                app.setActivationPolicy(.accessory)
            }
        } else {
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
            if !hideDockWhenClosed {
                app.activate(ignoringOtherApps: true)
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        let currentlyEnabled = (service.status == .enabled)
        do {
            if currentlyEnabled {
                try service.unregister()
                isLaunchAtLoginEnabled = false
                latestReleaseURL = nil
                updateStatusMessage = tr("已关闭开机自启动", "Launch at Login disabled", lang: lang)
            } else {
                guard Bundle.main.bundleURL.pathExtension == "app" else {
                    refreshLaunchAtLoginStatus()
                    latestReleaseURL = nil
                    updateStatusMessage = tr(
                        "请将 AppleLens.app 安装至 /Applications 后再开启开机自启动。",
                        "Install AppleLens.app in /Applications to enable Launch at Login.",
                        lang: lang
                    )
                    return
                }
                try service.register()
                refreshLaunchAtLoginStatus()
                latestReleaseURL = nil
                if service.status == .requiresApproval {
                    updateStatusMessage = tr(
                        "请在「系统设置 → 通用 → 登录项」中允许 AppleLens。",
                        "Approve AppleLens in System Settings -> General -> Login Items.",
                        lang: lang
                    )
                } else {
                    updateStatusMessage = tr("已开启开机自启动", "Launch at Login enabled", lang: lang)
                }
            }
        } catch {
            refreshLaunchAtLoginStatus()
            latestReleaseURL = nil
            updateStatusMessage = tr(
                "开机自启动设置失败（建议将 AppleLens.app 置于 /Applications）：\(error.localizedDescription)",
                "Launch at Login failed (ensure AppleLens.app is in /Applications): \(error.localizedDescription)",
                lang: lang
            )
        }
    }

    func checkForUpdates() async {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }

        guard let url = URL(string: "https://api.github.com/repos/Kianuni/AppleLens/releases/latest") else {
            return
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8.0
        cfg.timeoutIntervalForResource = 8.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AppleLens", forHTTPHeaderField: "User-Agent")

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                latestReleaseURL = nil
                updateStatusMessage = tr(
                    "检查更新失败（HTTP \(http.statusCode)）",
                    "Update check failed (HTTP \(http.statusCode))",
                    lang: lang
                )
                return
            }

            let decoded = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            if Self.isVersion(decoded.tagName, newerThan: currentVersion) {
                latestReleaseURL = decoded.htmlUrl
                updateStatusMessage = tr(
                    "发现新版本 \(decoded.tagName)（当前 v\(currentVersion)）",
                    "New release \(decoded.tagName) available (current v\(currentVersion))",
                    lang: lang
                )
            } else {
                latestReleaseURL = nil
                updateStatusMessage = tr(
                    "当前已是最新版本 (v\(currentVersion))",
                    "You are up to date (v\(currentVersion))",
                    lang: lang
                )
            }
        } catch {
            latestReleaseURL = nil
            updateStatusMessage = tr(
                "检查更新失败：\(error.localizedDescription)",
                "Update check failed: \(error.localizedDescription)",
                lang: lang
            )
        }
    }

    private struct GitHubLatestRelease: Decodable, Sendable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }

    private static func isVersion(_ remoteRaw: String, newerThan currentRaw: String) -> Bool {
        func parseParts(_ s: String) -> [Int] {
            var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("v") {
                trimmed.removeFirst()
            }
            if let dash = trimmed.firstIndex(of: "-") {
                trimmed = String(trimmed[..<dash])
            }
            return trimmed.split(separator: ".").map { Int($0) ?? 0 }
        }

        let lhs = parseParts(remoteRaw)
        let rhs = parseParts(currentRaw)
        let count = max(lhs.count, rhs.count)
        for idx in 0..<count {
            let l = idx < lhs.count ? lhs[idx] : 0
            let r = idx < rhs.count ? rhs[idx] : 0
            if l != r { return l > r }
        }
        return false
    }

    private func handleDevicesChanged(_ devices: [ConnectedIOSDevice]) {
        connectedDevices = devices
        if let currentUDID = selectedDeviceUDID,
           !devices.contains(where: { $0.id == currentUDID }) {
            selectedDeviceUDID = devices.first?.id
        } else if selectedDeviceUDID == nil {
            selectedDeviceUDID = devices.first?.id
        }

        if targetDeviceMode == .thisMac,
           !devices.isEmpty,
           UserDefaults.standard.string(forKey: Self.targetModeDefaultsKey) == TargetDeviceMode.usbIPhone.rawValue {
            switchTargetDeviceMode(.usbIPhone)
            return
        }

        if activeConnectedDevice == nil {
            if isIOSLiveStreaming {
                stopIOSLiveStream()
                iosStreamError = tr(
                    "USB iPhone 已断开连接，实时 syslog 监听已停止。",
                    "USB iPhone disconnected; live syslog relay stopped.",
                    lang: lang
                )
            }
        } else if !isIOSLiveStreaming && isIOSLiveStreamDesired {
            startIOSLiveStream()
        }
    }

    func switchTargetDeviceMode(_ newMode: TargetDeviceMode) {
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.targetModeDefaultsKey)
        guard targetDeviceMode != newMode else { return }
        targetDeviceMode = newMode
        radar.setTargetIOSMode(newMode == .usbIPhone)
        syncDesiredStreams()
    }

    private func syncDesiredStreams() {
        guard !radar.isPausedForSystemSleep else { return }

        if isMacLiveStreamDesired {
            if !isMacLiveStreaming || !logStream.isStreaming {
                startMacLiveStream()
            }
        } else if isMacLiveStreaming {
            stopMacLiveStream()
        }

        if isIOSLiveStreamDesired {
            if activeConnectedDevice != nil && (!isIOSLiveStreaming || !usbBridge.isStreaming) {
                startIOSLiveStream()
            } else if activeConnectedDevice == nil && isIOSLiveStreaming {
                stopIOSLiveStream()
            }
        } else if isIOSLiveStreaming {
            stopIOSLiveStream()
        }
    }

    func refreshRadarAndStreams() async {
        syncDesiredStreams()
        await radar.performSingleScan()
    }

    // MARK: - Live Log Streaming & Scanning

    func toggleLiveStream() {
        switch targetDeviceMode {
        case .thisMac:
            if isMacLiveStreaming {
                isMacLiveStreamDesired = false
                UserDefaults.standard.set(false, forKey: Self.macLiveStreamDesiredKey)
                stopMacLiveStream()
            } else {
                isMacLiveStreamDesired = true
                UserDefaults.standard.set(true, forKey: Self.macLiveStreamDesiredKey)
                startMacLiveStream()
            }
        case .usbIPhone:
            if isIOSLiveStreaming {
                isIOSLiveStreamDesired = false
                UserDefaults.standard.set(false, forKey: Self.iosLiveStreamDesiredKey)
                stopIOSLiveStream()
            } else {
                isIOSLiveStreamDesired = true
                UserDefaults.standard.set(true, forKey: Self.iosLiveStreamDesiredKey)
                startIOSLiveStream()
            }
        }
    }

    func startLiveStream() {
        switch targetDeviceMode {
        case .thisMac:
            startMacLiveStream()
        case .usbIPhone:
            startIOSLiveStream()
        }
    }

    func stopLiveStream() {
        switch targetDeviceMode {
        case .thisMac:
            stopMacLiveStream()
        case .usbIPhone:
            stopIOSLiveStream()
        }
    }

    func startMacLiveStream() {
        logStream.stopLiveStream()
        macStreamError = nil
        diagnosticsStatusNotice = nil
        isMacLiveStreaming = true

        logStream.startLiveStream(
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.enqueueLiveEvent(event)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.macStreamError = message
                }
            }
        )
    }

    func stopMacLiveStream() {
        logStream.stopLiveStream()
        isMacLiveStreaming = false
        flushPendingLiveEvents()
    }

    func startIOSLiveStream() {
        usbBridge.stopSyslogStream()
        iosStreamError = nil
        diagnosticsStatusNotice = nil

        guard let device = activeConnectedDevice else {
            isIOSLiveStreaming = false
            iosStreamError = tr(
                "未检测到已连接的 USB iPhone，请使用数据线连接后重试。",
                "No USB iPhone detected. Connect an iPhone via USB cable and try again.",
                lang: lang
            )
            return
        }

        isIOSLiveStreaming = true
        usbBridge.startSyslogStream(
            udid: device.id,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.enqueueLiveEvent(event)
                }
            },
            onStateChange: { [weak self] active in
                Task { @MainActor [weak self] in
                    self?.isIOSLiveStreaming = active
                }
            },
            onError: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.isIOSLiveStreaming = false
                    self?.iosStreamError = message
                }
            }
        )
    }

    func stopIOSLiveStream() {
        usbBridge.stopSyslogStream()
        isIOSLiveStreaming = false
        flushPendingLiveEvents()
    }

    func scanLast15Minutes() async {
        guard !isScanningHistory else { return }
        isScanningHistory = true
        streamError = nil

        let events = await logStream.scanRecentHistory(minutes: 15)
        let now = Date()
        let newFindingsCount = ingestLogBatch(events) { event in
            abs(now.timeIntervalSince(event.timestamp)) <= 12
        }

        diagnosticsStatusNotice = tr(
            "近 15 分钟扫描完成：读取 \(events.count) 条日志，新增 \(newFindingsCount) 条故障/状态翻译",
            "Scanned last 15m: \(events.count) logs read, \(newFindingsCount) translated findings added",
            lang: lang
        )
        isScanningHistory = false
    }

    func simulateSampleDiagnostics() {
        streamError = nil
        let now = Date()
        let sampleEvents = DiagnosticTranslator.sampleFaultLogLines.map { sample in
            UnifiedLogEvent(
                timestamp: now,
                processName: sample.process,
                subsystem: sample.subsystem,
                message: sample.message,
                sourceDevice: "Simulated Lab"
            )
        }
        let addedFindings = ingestLogBatch(sampleEvents) { _ in false }
        diagnosticsStatusNotice = tr(
            "已加载 \(addedFindings) 条经典故障模拟诊断卡片",
            "Loaded \(addedFindings) simulated fault diagnostic findings",
            lang: lang
        )
    }

    func clearDiagnostics() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        pendingLiveEvents.removeAll { matchesCurrentTarget(sourceDevice: $0.sourceDevice) }
        flushPendingLiveEvents()
        diagnosticFindings.removeAll { matchesCurrentTarget(sourceDevice: $0.sourceDevice) }
        rawLogEvents.removeAll { matchesCurrentTarget(sourceDevice: $0.sourceDevice) }
        streamError = nil
        diagnosticsStatusNotice = nil
    }

    private func enqueueLiveEvent(_ event: UnifiedLogEvent) {
        pendingLiveEvents.append(event)
        guard pendingFlushTask == nil else { return }
        pendingFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.flushPendingLiveEvents()
        }
    }

    private func flushPendingLiveEvents() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        guard !pendingLiveEvents.isEmpty else { return }
        let batch = pendingLiveEvents
        pendingLiveEvents.removeAll(keepingCapacity: true)
        ingestLogBatch(batch) { _ in true }
    }

    @discardableResult
    private func ingestLogBatch(
        _ events: [UnifiedLogEvent],
        shouldFeedRadar: (UnifiedLogEvent) -> Bool
    ) -> Int {
        guard !events.isEmpty else { return 0 }

        var combinedRaw: [UnifiedLogEvent] = []
        combinedRaw.reserveCapacity(events.count + rawLogEvents.count)
        combinedRaw.append(contentsOf: events.reversed())
        combinedRaw.append(contentsOf: rawLogEvents)

        if combinedRaw.count > 400 {
            var macKept = 0
            var iosKept = 0
            combinedRaw = combinedRaw.filter { ev in
                if ev.sourceDevice == "This Mac" {
                    macKept += 1
                    return macKept <= 400
                } else {
                    iosKept += 1
                    return iosKept <= 400
                }
            }
        }
        rawLogEvents = combinedRaw

        var updatedFindings = diagnosticFindings
        var newFindingsCount = 0
        var findingsChanged = false

        for event in events {
            if shouldFeedRadar(event) {
                radar.ingestUnifiedLogEvent(event)
            }

            if let finding = DiagnosticTranslator.translate(event: event) {
                let dedupWindow: TimeInterval = finding.code == .modelAssetDownloadProgress ? 60 : 15
                if let existingIdx = updatedFindings.firstIndex(where: {
                    $0.code == finding.code
                        && $0.sourceDevice == finding.sourceDevice
                        && abs(finding.timestamp.timeIntervalSince($0.timestamp)) < dedupWindow
                }) {
                    updatedFindings.remove(at: existingIdx)
                    updatedFindings.insert(finding, at: 0)
                    findingsChanged = true
                } else {
                    updatedFindings.insert(finding, at: 0)
                    if updatedFindings.count > 200 {
                        updatedFindings = Array(updatedFindings.prefix(200))
                    }
                    newFindingsCount += 1
                    findingsChanged = true
                }
            }
        }

        if findingsChanged {
            diagnosticFindings = updatedFindings
        }
        return newFindingsCount
    }

    // MARK: - Pre-Flight Routing Probe

    func runProbe() async {
        guard !isProbing else { return }
        let trimmed = customProxyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedProxy: CustomProxyConfig?
        if trimmed.isEmpty {
            customProxyValidationError = nil
            parsedProxy = nil
        } else if let config = CustomProxyConfig.parse(trimmed, defaultScheme: customProxyScheme) {
            customProxyValidationError = nil
            parsedProxy = config
        } else {
            customProxyValidationError = tr(
                "代理格式无效，请输入如 127.0.0.1:6152 或 socks5://127.0.0.1:6153",
                "Invalid proxy format. Use e.g. 127.0.0.1:6152 or socks5://127.0.0.1:6153",
                lang: lang
            )
            return
        }

        isProbing = true
        let result = await probeEngine.runFullProbe(customProxy: parsedProxy)
        probeReport = result
        lastProbeCustomProxySummary = parsedProxy?.displayString
        isProbing = false
    }

    func copyRedactedProbeMarkdown() {
        guard let report = probeReport else { return }
        let markdown = DiagnosticReportFormatter.formatProbeMarkdown(
            report,
            customProxySummary: lastProbeCustomProxySummary,
            lang: lang
        )
        copyToPasteboard(markdown)
    }

    func copyRedactedDiagnosticsMarkdown() {
        let findings = diagnosticFindings.filter { matchesCurrentTarget(sourceDevice: $0.sourceDevice) }
        guard !findings.isEmpty else { return }
        let targetLabel = targetDeviceMode == .usbIPhone
            ? (activeConnectedDevice.map { DiagnosticReportFormatter.redactSensitiveText($0.displayTitle) } ?? "USB iPhone")
            : "This Mac"
        let markdown = DiagnosticReportFormatter.formatDiagnosticsMarkdown(
            findings: findings,
            targetLabel: targetLabel,
            lang: lang
        )
        copyToPasteboard(markdown)
    }

    // MARK: - ReportLens & Unified File Importer

    func refreshLatestDownloadsReport() {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            latestDownloadsReportURL = nil
            return
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            latestDownloadsReportURL = nil
            return
        }

        let candidates = items.filter { url in
            guard url.pathExtension.lowercased() == "json" else { return false }
            let name = url.lastPathComponent.lowercased()
            guard name.contains("intelligence") && name.contains("report") else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile ?? true
        }

        latestDownloadsReportURL = candidates.max { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]))
                .flatMap { $0.contentModificationDate ?? $0.creationDate } ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]))
                .flatMap { $0.contentModificationDate ?? $0.creationDate } ?? .distantPast
            return lDate < rDate
        }
    }

    func openLatestDownloadsReport() {
        refreshLatestDownloadsReport()
        guard let url = latestDownloadsReportURL else { return }
        importFile(url: url)
    }

    func loadDemoReport() {
        let data = SampleReportFixture.sampleReportJSONData()
        do {
            let decoded = try IntelligenceReportDecoder.decode(
                data: data,
                fileName: "Sample_Apple_Intelligence_Report.json"
            )
            currentReport = decoded
            isShowingDemoReport = true
            selectedRequestID = decoded.requests.first?.id
            reportError = nil
        } catch {
            reportError = error.localizedDescription
        }
    }

    func importFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            selectedTab = .reportLens
            do {
                let decoded = try IntelligenceReportDecoder.decodeFile(at: url)
                currentReport = decoded
                isShowingDemoReport = false
                selectedRequestID = decoded.requests.first?.id
                reportError = nil
            } catch {
                reportError = tr(
                    "无法解析报告 JSON（\(url.lastPathComponent)）：\(error.localizedDescription)",
                    "Failed to decode report JSON (\(url.lastPathComponent)): \(error.localizedDescription)",
                    lang: lang
                )
            }
            return
        }

        selectedTab = .diagnostics
        streamError = nil
        do {
            let events: [UnifiedLogEvent]
            let sourceLabel = "Imported (\(url.lastPathComponent))"
            if let data = try? Data(contentsOf: url),
               ext == "ndjson" || isLikelyNDJSON(data: data) {
                let parsed = UnifiedLogStreamService.parseNDJSONData(data, sourceDevice: sourceLabel)
                events = parsed.isEmpty ? try USBiPhoneLogBridge.importLogTextFile(url: url) : parsed
            } else {
                events = try USBiPhoneLogBridge.importLogTextFile(url: url)
            }

            let translatedCount = ingestLogBatch(events) { _ in false }
            diagnosticsStatusNotice = tr(
                "已导入 \(url.lastPathComponent)：\(events.count) 行日志，命中 \(translatedCount) 条诊断翻译",
                "Imported \(url.lastPathComponent): \(events.count) lines, \(translatedCount) translated findings",
                lang: lang
            )
        } catch {
            streamError = tr(
                "导入日志文件失败：\(error.localizedDescription)",
                "Failed to import log file: \(error.localizedDescription)",
                lang: lang
            )
        }
    }

    private func isLikelyNDJSON(data: Data) -> Bool {
        guard let text = String(data: data.prefix(4096), encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.contains("\"eventMessage\"")
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    Task { @MainActor [weak self] in
                        self?.importFile(url: url)
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                    guard let data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.importFile(url: url)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - OpenPanels & AppKit Helpers

    func closeCurrentReport() {
        currentReport = nil
        selectedRequestID = nil
        reportError = nil
        isShowingDemoReport = false
    }

    func openMacIntelligenceReportSettings() {
        let anchorURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppleIntelligenceReport")!
        if !NSWorkspace.shared.open(anchorURL) {
            if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(fallbackURL)
            }
        }
    }

    func openDownloadsFolderInFinder() {
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(downloadsURL)
        }
    }

    func openOpenPanelForReportJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = tr(
            "选择 Apple_Intelligence_Report.json 文件",
            "Select an Apple_Intelligence_Report.json file",
            lang: lang
        )
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importFile(url: url)
        }
    }

    func openOpenPanelForLogFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var contentTypes: [UTType] = [.plainText]
        for ext in ["log", "txt", "ips", "ndjson"] {
            if let ut = UTType(filenameExtension: ext) {
                contentTypes.append(ut)
            }
        }
        panel.allowedContentTypes = contentTypes
        panel.message = tr(
            "选择要离线诊断的日志文本 (.log / .txt / .ips)",
            "Select a log file (.log / .txt / .ips) for offline translation",
            lang: lang
        )
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importFile(url: url)
        }
    }

    func appIcon(for connection: ActiveLLMConnection) -> NSImage {
        if let bundlePath = connection.appBundlePath {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
        if let runningApp = NSRunningApplication(processIdentifier: connection.pid),
           let icon = runningApp.icon {
            return icon
        }
        return NSWorkspace.shared.icon(for: .unixExecutable)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openExternalURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
