import AppleLensCore
import SwiftUI

struct RadarView: View {
    @Bindable var viewModel: AppViewModel

    private var lang: AppLanguage { viewModel.lang }
    private var radar: TriStateRadarCoordinator { viewModel.radar }
    private var isIOSMode: Bool { viewModel.targetDeviceMode == .usbIPhone }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !viewModel.isLiveStreaming {
                    streamPausedBanner
                }

                overallBannerCard

                if !isIOSMode && !radar.firstSeenAlerts.isEmpty {
                    firstSeenAlertsSection
                }

                triStateGrid
                activityFeedSection
                externalConnectionsSection

                if !radar.trustedProcessKeys.isEmpty {
                    trustedProcessesSection
                }

                if !isIOSMode {
                    proxyAndDnsSection
                }

                timelineSection
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassHeaderBar(
                title: tr("实时端云 AI 隐私雷达", "Real-Time Tri-State AI Radar", lang: lang),
                subtitle: isIOSMode
                    ? tr(
                        "USB 只读接入 iPhone syslog_relay 实时捕捉端侧 ANE / 相册智能消除 / PCC 与第三方 AI 客户端会话",
                        "Read-only USB syslog_relay telemetry for iPhone On-Device ANE, Photos Clean Up, PCC & AI apps",
                        lang: lang
                    )
                    : tr(
                        "纯本机只读进程 Socket 表与 DNS Fake-IP 反查 + Unified Log 端云信号交叉印证（零 MitM）",
                        "Read-only socket inspection, DNS Fake-IP reverse lookup & Unified Log correlation (Zero-MitM)",
                        lang: lang
                    )
            ) {
                if !isIOSMode {
                    Toggle(isOn: $viewModel.revealFullIPs) {
                        Text(tr("完整 IP", "Full IPs", lang: lang))
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }

                Button {
                    viewModel.toggleLiveStream()
                } label: {
                    Label(
                        viewModel.isLiveStreaming
                            ? tr("暂停日志流", "Pause Stream", lang: lang)
                            : tr("开启实时监听", "Start Live Stream", lang: lang),
                        systemImage: viewModel.isLiveStreaming ? "pause.circle" : "play.circle.fill"
                    )
                }
                .lensGlassButton(
                    prominent: !viewModel.isLiveStreaming,
                    tint: viewModel.isLiveStreaming ? Color.secondary : LensTheme.emerald
                )
                .controlSize(.small)

                Button {
                    Task {
                        await viewModel.refreshRadarAndStreams()
                    }
                } label: {
                    Label(tr("立即扫描", "Scan Now", lang: lang), systemImage: "arrow.clockwise")
                }
                .lensGlassButton(prominent: true)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Stream Paused Banner

    private var streamPausedBanner: some View {
        SurfaceCard(tint: LensTheme.amber) {
            if isIOSMode && viewModel.activeConnectedDevice == nil {
                HStack(spacing: 12) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LensTheme.amber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("尚未检测到已信任配对的 USB iPhone", "No Trusted USB iPhone Connected", lang: lang))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(tr("请通过数据线连接 iPhone 并在手机屏幕点击「信任此电脑」，连接后将自动开始雷达实时采集。", "Connect your iPhone via USB cable and tap 'Trust This Computer' to begin live telemetry.", lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LensTheme.amber)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            isIOSMode
                                ? tr("iPhone 实时日志流已暂停 — 雷达当前无法捕获手机端 AI 活动", "iPhone Live Stream Paused — Radar Telemetry Inactive", lang: lang)
                                : tr("Mac 统一日志流已暂停 — 当前仅运行外部大模型 Socket 扫描", "Mac Unified Log Stream Paused — Socket Scan Only", lang: lang)
                        )
                        .font(.system(size: 13.5, weight: .semibold))

                        Text(
                            isIOSMode
                                ? tr("iPhone 三态雷达（端侧 ANE、相册消除、视觉智能、PCC 与 Claude/ChatGPT 会话）依赖 USB syslog 实时流。无需前往「日志与故障诊断」，点击右侧按钮即可直接开启。", "iPhone Radar relies on live USB syslog_relay telemetry. Click Start on the right to resume directly without switching tabs.", lang: lang)
                                : tr("第三方 AI 外连进程（ChatGPT / Claude 等）仍每 1.5 秒正常扫描，但本机「端侧 ANE」与「Apple PCC」状态需开启实时日志流才能实时捕获。", "External LLM socket polling remains active every 1.5s, but local On-Device ANE and Apple PCC signals require the live log stream.", lang: lang)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        viewModel.toggleLiveStream()
                    } label: {
                        Label(
                            isIOSMode
                                ? tr("立即开启 iPhone 实时监听", "Start iPhone Live Stream", lang: lang)
                                : tr("开启 Mac 实时日志流", "Start Mac Live Stream", lang: lang),
                            systemImage: "play.fill"
                        )
                    }
                    .lensGlassButton(prominent: true, tint: LensTheme.sapphire)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Overall Status Banner

    private var overallBannerCard: some View {
        SurfaceCard(tint: radar.overallState.tintColor) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(radar.overallState.tintColor.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(radar.overallState.tintColor.opacity(0.25), lineWidth: 0.75)
                        )
                    Image(systemName: radar.overallState.sfSymbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(radar.overallState.tintColor)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        PulseIndicatorDot(
                            color: radar.overallState.tintColor,
                            isActive: radar.overallState != .idle,
                            size: 7.5
                        )
                        Text(radar.overallState.label(lang: lang))
                            .font(.system(size: 16, weight: .semibold))

                        if isIOSMode {
                            StatusBadge(
                                text: viewModel.activeConnectedDevice?.displayTitle
                                    ?? tr("未连接 USB iPhone", "No USB iPhone", lang: lang),
                                color: viewModel.activeConnectedDevice != nil ? LensTheme.sapphire : LensTheme.amber,
                                icon: "iphone"
                            )
                            if viewModel.isLiveStreaming {
                                StatusBadge(text: tr("USB 实时流运行中", "USB Live", lang: lang), color: LensTheme.emerald)
                            } else {
                                StatusBadge(text: tr("实时流已暂停", "Stream Paused", lang: lang), color: LensTheme.amber, icon: "pause.fill")
                            }
                        } else {
                            StatusBadge(
                                text: viewModel.targetDeviceMode.label(lang: lang),
                                color: LensTheme.sapphire,
                                icon: viewModel.targetDeviceMode.sfSymbol
                            )
                            StatusBadge(
                                text: viewModel.isLiveStreaming
                                    ? tr("日志 + Socket 运行中", "Logs + Sockets Live", lang: lang)
                                    : tr("日志已暂停 · 仅 Socket", "Logs Paused · Sockets Only", lang: lang),
                                color: viewModel.isLiveStreaming ? LensTheme.emerald : LensTheme.amber,
                                icon: viewModel.isLiveStreaming ? "waveform" : "pause.fill"
                            )
                        }
                    }

                    Text(
                        isIOSMode
                            ? tr(
                                "已隔离本机 Mac 进程，仅实时读取 USB 连线 iPhone 的系统日志流（识别端侧 ANE、相册智能消除、Apple PCC 与原生 AI 客户端）。",
                                "Isolated from Mac processes; streams read-only USB syslog_relay from iPhone (On-Device ANE, Photos Clean Up, PCC & AI apps).",
                                lang: lang
                            )
                            : tr(
                                "实时监听本机统一日志流并每 1.5 秒被动轮询出站 Socket 元数据，与 DNS Fake-IP 交叉匹配，零流量劫持。",
                                "Streams local unified logs and passively polls socket metadata every 1.5s without traffic interception.",
                                lang: lang
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    if let scanned = radar.lastScanDate {
                        Text(scanned, style: .time)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    MetaPill(
                        text: isIOSMode
                            ? tr("触发记录 \(viewModel.filteredActivityRecords.count) 条", "\(viewModel.filteredActivityRecords.count) events", lang: lang)
                            : tr("DNS 缓存 \(radar.mappedIPCount) 条", "\(radar.mappedIPCount) DNS entries", lang: lang)
                    )
                    MetaPill(
                        text: tr("轮询 \(radarPollIntervalText(radar: radar, lang: lang))", "Poll \(radarPollIntervalText(radar: radar, lang: lang))", lang: lang),
                        icon: radar.isPausedForSystemSleep ? "moon.zzz" : "timer"
                    )
                }
            }
        }
    }

    // MARK: - First-Seen Alerts

    private var firstSeenAlertsSection: some View {
        SurfaceCard(tint: LensTheme.amber) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: tr("陌生进程首次外连外部 AI API", "First-Seen Process Alert: External AI API", lang: lang),
                    subtitle: tr("核实该桌面应用是否为预期调用，可选择信任放行或忽略", "Verify whether this process is expected to call external AI APIs", lang: lang),
                    icon: "exclamationmark.triangle.fill"
                )

                ForEach(radar.firstSeenAlerts) { alert in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(alert.appName)
                                    .font(.system(size: 13, weight: .semibold))
                                StatusBadge(
                                    text: tr(alert.providerNameZh, alert.providerNameEn, lang: lang),
                                    color: LensTheme.amber
                                )
                                MetaPill(text: alert.matchedDomain)
                            }
                            Text(alert.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        LensActionCluster(spacing: 6) {
                            Button(tr("信任此进程", "Trust Process", lang: lang)) {
                                radar.trustProcess(identityKey: alert.identityKey)
                            }
                            .lensGlassButton(prominent: false)
                            .controlSize(.small)

                            Button(tr("忽略", "Dismiss", lang: lang)) {
                                radar.dismissAlert(alert.id)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
                    )
                }
            }
        }
    }

    // MARK: - Tri-State Three Columns

    private var triStateGrid: some View {
        let activeIOSSessions = radar.iosActiveSessions.filter { !$0.isSuspended }
        let thirdActive = isIOSMode ? !activeIOSSessions.isEmpty : !radar.activeLLMConnections.isEmpty
        let thirdCount = isIOSMode ? activeIOSSessions.count : radar.activeLLMConnections.count
        let thirdDetail: String = {
            if isIOSMode {
                if activeIOSSessions.isEmpty {
                    return tr(
                        "当前 iPhone 前台未检测到第三方 AI 客户端活动（如 Claude / ChatGPT / Gemini / DeepSeek）。",
                        "No active third-party AI app detected on connected iPhone.",
                        lang: lang
                    )
                }
                let names = activeIOSSessions.map(\.appName).joined(separator: " / ")
                return tr(
                    "正在捕获 \(names) 的 iOS 网络 / 前台调度信号，详情见下方会话表。",
                    "Capturing active iOS sessions for \(names) below.",
                    lang: lang
                )
            } else {
                return radar.activeLLMConnections.isEmpty
                    ? tr("当前未检测到桌面进程外连 OpenAI / Anthropic / DeepSeek / 通义 / Kimi 等外部 API。", "No local process is currently connected to external LLM endpoints.", lang: lang)
                    : tr("已检测到 \(radar.activeLLMConnections.count) 条第三方 AI API 出站连接，请核查下方进程表。", "Detected \(radar.activeLLMConnections.count) external LLM outbound connections below.", lang: lang)
            }
        }()

        return HStack(alignment: .top, spacing: 14) {
            triStateCard(
                title: tr("端侧本地推理 (On-Device)", "On-Device Inference (ANE)", lang: lang),
                active: radar.isOnDeviceActive,
                color: LensTheme.emerald,
                icon: "cpu.fill",
                statusLabel: radar.isOnDeviceActive ? tr("活跃", "Active", lang: lang) : tr("待机", "Standby", lang: lang),
                detail: radar.lastOnDeviceDetail.isEmpty
                    ? tr("等待端侧 ANE / modelmanagerd / 相册智能消除信号", "Waiting for ANE / modelmanagerd / Photos Clean Up logs", lang: lang)
                    : radar.lastOnDeviceDetail,
                lastDate: radar.lastOnDeviceSignal
            )

            triStateCard(
                title: tr("Apple PCC 私有云", "Apple Private Cloud Compute", lang: lang),
                active: radar.isPCCActive,
                color: LensTheme.sapphire,
                icon: "lock.icloud.fill",
                statusLabel: radar.isPCCActive ? tr("活跃", "Active", lang: lang) : tr("待机", "Standby", lang: lang),
                detail: radar.lastPCCDetail.isEmpty
                    ? tr("等待 privatecloudcomputed (Thimble) / OHTTP / 高质量消除信号", "Waiting for privatecloudcomputed (Thimble) / OHTTP / Clean Up signal", lang: lang)
                    : radar.lastPCCDetail,
                lastDate: radar.lastPCCSignal
            )

            triStateCard(
                title: isIOSMode
                    ? tr("iPhone AI 客户端审计", "iPhone AI App Audit", lang: lang)
                    : tr("第三方大模型外连审计", "External LLM Egress Audit", lang: lang),
                active: thirdActive,
                color: LensTheme.amber,
                icon: "network.badge.shield.half.filled",
                statusLabel: thirdActive
                    ? tr("\(thirdCount) 活跃", "\(thirdCount) Active", lang: lang)
                    : tr("清净", "Clear", lang: lang),
                detail: thirdDetail,
                lastDate: isIOSMode ? activeIOSSessions.first?.lastSeenAt : radar.lastScanDate
            )
        }
    }

    private func triStateCard(
        title: String,
        active: Bool,
        color: Color,
        icon: String,
        statusLabel: String,
        detail: String,
        lastDate: Date?
    ) -> some View {
        SurfaceCard(tint: active ? color : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active ? color.opacity(0.14) : Color.primary.opacity(0.06))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? color : .secondary)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    PulseIndicatorDot(color: color, isActive: active, size: 6)
                }

                StatusBadge(text: statusLabel, color: active ? color : .secondary)

                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(minHeight: 42, alignment: .topLeading)

                HStack {
                    Spacer()
                    if let lastDate {
                        Text(lastDate, style: .time)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Persistent Session Activity Feed (Photos Clean Up, PCC, ANE, AI Apps)

    private var activityFeedSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    SectionHeader(
                        title: tr("近期端云 AI 与智能消除触发记录", "Session AI & Photos Clean Up Activity Log", lang: lang),
                        subtitle: tr(
                            "持久留存本轮触发过的相册智能消除 (Clean Up)、Apple PCC、Siri/写作工具与 AI App 事件，不会随 10 秒冷却自动消失",
                            "Retains Photos Clean Up, Apple PCC, Siri/Writing Tools & AI client triggers from this session",
                            lang: lang
                        ),
                        icon: "bolt.badge.clock"
                    )

                    if !viewModel.filteredActivityRecords.isEmpty {
                        Button(tr("清空记录", "Clear Log", lang: lang)) {
                            radar.clearActivityRecords(isIOS: isIOSMode)
                        }
                        .lensGlassButton(prominent: false)
                        .controlSize(.small)
                    }
                }

                if viewModel.filteredActivityRecords.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.checkmark")
                            .font(.system(size: 19))
                            .foregroundStyle(LensTheme.sapphire)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                isIOSMode
                                    ? tr("等待捕捉 iPhone 端侧 AI / 相册智能消除 / AI App 触发记录", "Waiting for iPhone AI / Photos Clean Up / AI App Events", lang: lang)
                                    : tr("等待捕捉本机 Mac AI / 相册智能消除 / PCC 触发记录", "Waiting for Mac AI / Photos Clean Up / PCC Events", lang: lang)
                            )
                            .font(.system(size: 13, weight: .medium))
                            Text(
                                isIOSMode
                                    ? tr("在相连 iPhone 上打开「照片 → 消除」修图、唤醒 Siri 或使用 Claude 等 AI 客户端，事件会立刻记录在此卡片中。", "Use Photos Clean Up, Siri, or Claude on your connected iPhone to capture events here automatically.", lang: lang)
                                    : tr("在 Mac 上打开「照片 → 消除」、写作工具、Siri 或任意 AI 客户端，事件会自动沉淀在此处。", "Use Photos Clean Up, Writing Tools, Siri, or an AI client on this Mac to log events here.", lang: lang)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.filteredActivityRecords.prefix(15)) { rec in
                            activityRecordRow(rec)
                        }
                    }
                }
            }
        }
    }

    private func activityRecordRow(_ rec: AIActivityRecord) -> some View {
        let tint = activityTint(rec.kind)
        let iconName = rec.titleEn.contains("Clean Up")
            ? "photo.badge.checkmark"
            : (rec.kind == .applePCC ? "lock.icloud.fill" : (rec.kind == .onDevice ? "cpu.fill" : "network"))

        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rec.title(lang: lang))
                        .font(.system(size: 13, weight: .semibold))
                    StatusBadge(text: activityCategoryLabel(rec.kind), color: tint)
                    MetaPill(text: rec.processName)
                    if let route = rec.routeBadge {
                        MetaPill(text: route, icon: "arrow.triangle.branch")
                    }
                }
                Text(rec.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(rec.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 0.75)
        )
    }

    // MARK: - Active External Connections / iPhone AI Sessions

    private var externalConnectionsSection: some View {
        Group {
            if isIOSMode {
                iPhoneSessionsCard
            } else {
                macConnectionsCard
            }
        }
    }

    private var iPhoneSessionsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: tr("iPhone 第三方 AI 客户端实时会话 (USB syslog_relay)", "iPhone AI Client Sessions (USB syslog_relay)", lang: lang),
                    subtitle: tr(
                        "识别 Claude / ChatGPT / Gemini / DeepSeek / 豆包 / 通义 / Kimi 原生客户端调度与加密出站（浏览器网页受 iOS 沙盒隔离不透传）",
                        "Detects native Claude / ChatGPT / Gemini / DeepSeek / Doubao / Qwen / Kimi activity via USB syslog (browser URLs remain sandboxed on iOS)",
                        lang: lang
                    ),
                    icon: "iphone.gen3.radiowaves.left.and.right"
                )

                if viewModel.activeConnectedDevice == nil {
                    HStack(spacing: 12) {
                        Image(systemName: "cable.connector.slash")
                            .font(.system(size: 19))
                            .foregroundStyle(LensTheme.amber)
                        Text(tr("未检测到已信任配对的 USB iPhone，请插入数据线并在 iPhone 上确认信任此电脑。", "No trusted USB iPhone connected. Connect via cable and tap Trust This Computer.", lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if radar.iosActiveSessions.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(LensTheme.emerald)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("当前 iPhone 无活跃第三方 AI 客户端会话", "No Active iPhone AI Client Sessions", lang: lang))
                                .font(.system(size: 13, weight: .medium))
                            Text(tr("保持 USB 连接并打开手机端 Claude / ChatGPT 等应用发一条消息，此处将实时捕获进程会话。", "Keep iPhone connected and open Claude / ChatGPT on your iPhone to inspect live sessions.", lang: lang))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(radar.iosActiveSessions) { session in
                            iosSessionRow(session)
                        }
                    }
                }
            }
        }
    }

    private func iosSessionRow(_ session: IOSActiveAISession) -> some View {
        let color = session.isSuspended ? Color.secondary : LensTheme.amber
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(session.appName)
                        .font(.system(size: 13, weight: .semibold))
                    if session.pid > 0 {
                        MetaPill(text: "PID \(session.pid)")
                    }
                    StatusBadge(
                        text: session.isSuspended
                            ? tr("后台休眠", "Background", lang: lang)
                            : tr("活跃会话", "Active", lang: lang),
                        color: session.isSuspended ? .secondary : LensTheme.emerald
                    )
                }

                HStack(spacing: 6) {
                    MetaPill(text: session.provider.displayName(lang: lang))
                    if let bid = session.bundleID {
                        MetaPill(text: bid)
                    }
                    if let route = session.routeBadge {
                        MetaPill(text: route, icon: "arrow.triangle.branch")
                    }
                    Text(session.status(lang: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(session.lastSeenAt, style: .time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
        )
    }

    private var macConnectionsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: tr("外部大模型外连进程审计表", "External LLM Process Audit", lang: lang),
                    subtitle: tr("支持 OpenAI / Anthropic / Gemini / OpenRouter / DeepSeek / 豆包 / 通义 / Kimi / 智谱", "Audits OpenAI / Anthropic / Gemini / OpenRouter / DeepSeek / Doubao / Qwen / Kimi / Zhipu", lang: lang),
                    icon: "list.bullet.rectangle.portrait"
                )

                if radar.activeLLMConnections.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(LensTheme.emerald)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("当前无第三方 AI 外连活动", "No External AI Connections Detected", lang: lang))
                                .font(.system(size: 13, weight: .medium))
                            Text(tr("所有被审计主流 AI 服务商当前均未处于活跃连接状态。", "No active TCP/UDP sockets match audited LLM provider domains or dedicated CIDRs.", lang: lang))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(radar.activeLLMConnections) { conn in
                            connectionRow(conn)
                        }
                    }
                }
            }
        }
    }

    private func connectionRow(_ conn: ActiveLLMConnection) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: viewModel.appIcon(for: conn))
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(conn.appName)
                        .font(.system(size: 13, weight: .semibold))
                    MetaPill(text: "PID \(conn.pid)")
                    if !conn.isTrusted {
                        StatusBadge(text: tr("未信任", "Untrusted", lang: lang), color: LensTheme.amber)
                    } else {
                        StatusBadge(text: tr("已信任", "Trusted", lang: lang), color: LensTheme.emerald)
                    }
                }

                HStack(spacing: 6) {
                    MetaPill(text: conn.provider.displayName(lang: lang))
                    MetaPill(text: conn.confidence.label(lang: lang))
                    Text("\(conn.matchedDomain) · \(RoutingProbeFormatter.maskIP(conn.remoteIP, revealFull: viewModel.revealFullIPs))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !conn.isTrusted {
                Button(tr("标记为信任", "Trust", lang: lang)) {
                    radar.trustProcess(identityKey: conn.identityKey)
                }
                .lensGlassButton(prominent: false)
                .controlSize(.small)
            } else {
                Button(tr("取消信任", "Untrust", lang: lang)) {
                    radar.untrustProcess(identityKey: conn.identityKey)
                }
                .lensGlassButton(prominent: false)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Trusted Processes Management

    private var trustedProcessesSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: tr("已信任进程管理 (\(radar.trustedProcessKeys.count))", "Trusted Processes (\(radar.trustedProcessKeys.count))", lang: lang),
                    subtitle: tr("已放行且不再触发首次外连告警的本地进程标识；支持一键撤销信任", "Process identity keys allowed without First-Seen alerts", lang: lang),
                    icon: "checkmark.shield"
                )

                VStack(spacing: 8) {
                    ForEach(radar.trustedProcessKeys, id: \.self) { identityKey in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(LensTheme.emerald)

                            Text(identityKey)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                radar.untrustProcess(identityKey: identityKey)
                            } label: {
                                Label(tr("移除", "Remove", lang: lang), systemImage: "xmark.circle")
                            }
                            .lensGlassButton(prominent: false)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Proxy & DNS Telemetry

    private var proxyAndDnsSection: some View {
        HStack(alignment: .top, spacing: 14) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(
                        title: tr("本机代理端口与 Fake-IP 透视", "Local Proxy & Fake-IP Context", lang: lang),
                        icon: "arrow.triangle.branch"
                    )
                    HStack(spacing: 8) {
                        Text(tr("检测到的活跃代理端口：", "Active proxy ports:", lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if radar.activeProxyPorts.isEmpty {
                            MetaPill(text: tr("未开启或直连", "None / Direct", lang: lang))
                        } else {
                            ForEach(radar.activeProxyPorts, id: \.self) { port in
                                MetaPill(text: ":\(port)")
                            }
                        }
                    }
                    Text(tr(
                        "当开启 Surge / Clash / Quantumult X Fake-IP 模式时，AppleLens 通过统一日志与路由表反查 `198.18.x.x` 对应真实域名，同时自动过滤本地回环代理进程归因。",
                        "Under Surge / Clash Fake-IP mode, AppleLens resolves 198.18.x.x back to domains from system DNS caches & logs without MitM.",
                        lang: lang
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: tr("近期端云行为时间线", "Recent Compute & Egress Timeline", lang: lang),
                    icon: "clock.arrow.circlepath"
                )

                if radar.recentTimeline.isEmpty {
                    Text(tr("尚无触发信号，尝试唤醒 Siri / 写作工具或开启任意 AI 客户端。", "No signals yet. Trigger Siri / Writing Tools or an AI client to observe events.", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    InsetCodeWell(maxHeight: 160) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(radar.recentTimeline.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(timelineAccent(line))
                                        .frame(width: 5.5, height: 5.5)
                                        .padding(.top, 4.5)
                                    Text(cleanTelemetryLine(line))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary.opacity(0.85))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func activityTint(_ kind: AIActivityKind) -> Color {
        switch kind {
        case .onDevice: return LensTheme.emerald
        case .applePCC: return LensTheme.sapphire
        case .externalAI: return LensTheme.amber
        }
    }

    private func activityCategoryLabel(_ kind: AIActivityKind) -> String {
        switch kind {
        case .onDevice: return tr("端侧本地", "On-Device", lang: lang)
        case .applePCC: return tr("Apple PCC", "Apple PCC", lang: lang)
        case .externalAI: return tr("外部 AI", "External AI", lang: lang)
        }
    }

    private func timelineAccent(_ line: String) -> Color {
        if line.contains("🟠") || line.contains("First-Seen") || line.contains("Claude") || line.contains("ChatGPT") {
            return LensTheme.amber
        }
        if line.contains("🔵") || line.contains("PCC") {
            return LensTheme.sapphire
        }
        if line.contains("🟢") || line.contains("On-Device") || line.contains("Clean Up") {
            return LensTheme.emerald
        }
        return .secondary
    }
}
