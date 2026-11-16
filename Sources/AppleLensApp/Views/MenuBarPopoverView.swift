import AppKit
import AppleLensCore
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    private var lang: AppLanguage { viewModel.lang }
    private var radar: TriStateRadarCoordinator { viewModel.radar }

    var body: some View {
        ZStack {
            VibrancyBackdrop(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                UpdateStatusNoticeBar(viewModel: viewModel, compact: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        statusHeroCard

                        if !viewModel.isLiveStreaming && (!isIOSMode || viewModel.activeConnectedDevice != nil) {
                            SurfaceCard(tint: LensTheme.amber, padding: 10, cornerRadius: 11) {
                                HStack(spacing: 8) {
                                    Image(systemName: "pause.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(LensTheme.amber)
                                    Text(tr("实时日志流已暂停，部分雷达信号未启用", "Live log stream is paused", lang: lang))
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    Button(tr("开启", "Start", lang: lang)) {
                                        viewModel.toggleLiveStream()
                                    }
                                    .lensGlassButton(prominent: true, tint: LensTheme.sapphire)
                                    .controlSize(.mini)
                                }
                            }
                        }

                        triStateTilesRow

                        if !isIOSMode && !radar.firstSeenAlerts.isEmpty {
                            firstSeenAlertsCard
                        }

                        if isIOSMode {
                            if !radar.iosActiveSessions.isEmpty {
                                activeIOSSessionsCard
                            } else {
                                emptyConnectionsHint
                            }
                        } else if !radar.activeLLMConnections.isEmpty {
                            activeConnectionsCard
                        } else {
                            emptyConnectionsHint
                        }

                        if !radar.recentTimeline.isEmpty {
                            timelineStrip
                        }
                    }
                    .padding(14)
                }
                .scrollContentBackground(.hidden)

                footerBar
            }
        }
        .onAppear {
            viewModel.setPopoverVisible(true)
        }
        .onDisappear {
            viewModel.setPopoverVisible(false)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MiniPrismEmblem(size: 26)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("AppleLens")
                            .font(.system(size: 13.5, weight: .semibold))
                        StatusBadge(
                            text: tr("零 MitM", "Zero-MitM", lang: lang),
                            color: LensTheme.emerald
                        )
                    }
                    Text(tr("端云 AI 隐私与推理雷达", "AI Compute & Egress Radar", lang: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                LanguageToggleButton(manager: viewModel.language)

                Button {
                    Task { await viewModel.refreshRadarAndStreams() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .lensGlassButton(prominent: false)
                .controlSize(.small)
                .help(tr("立即刷新进程与通道", "Scan Now", lang: lang))

                SettingsPreferencesMenu(viewModel: viewModel, compact: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Rectangle()
                .fill(LensTheme.hairline)
                .frame(height: 0.75)
        }
    }

    // MARK: - Hero Status Card

    private var statusHeroCard: some View {
        SurfaceCard(tint: radar.overallState.tintColor, padding: 12, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PulseIndicatorDot(
                        color: radar.overallState.tintColor,
                        isActive: radar.overallState != .idle,
                        size: 7.5
                    )
                    Image(systemName: radar.overallState.sfSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(radar.overallState.tintColor)

                    Text(radar.overallState.label(lang: lang))
                        .font(.system(size: 13.5, weight: .semibold))

                    Spacer()

                    if let scanned = radar.lastScanDate {
                        Text(scanned, style: .time)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    MetaPill(
                        text: viewModel.targetDeviceMode.label(lang: lang),
                        icon: viewModel.targetDeviceMode.sfSymbol
                    )
                    if !radar.activeProxyPorts.isEmpty {
                        let ports = radar.activeProxyPorts.map(String.init).joined(separator: ",")
                        MetaPill(
                            text: tr("代理 :\(ports)", "Proxy :\(ports)", lang: lang),
                            icon: "arrow.triangle.branch"
                        )
                    }
                    MetaPill(
                        text: "\(radar.mappedIPCount) IP",
                        icon: "link"
                    )
                    MetaPill(
                        text: radarPollIntervalText(radar: radar, lang: lang),
                        icon: radar.isPausedForSystemSleep ? "moon.zzz" : "timer"
                    )
                }
            }
        }
    }

    private var isIOSMode: Bool { viewModel.targetDeviceMode == .usbIPhone }

    // MARK: - Tri-State Compact Tiles

    private var triStateTilesRow: some View {
        let activeIOSCount = radar.iosActiveSessions.filter { !$0.isSuspended }.count
        let thirdCount = isIOSMode ? activeIOSCount : radar.activeLLMConnections.count
        let thirdActive = thirdCount > 0

        return HStack(spacing: 8) {
            compactTile(
                title: tr("端侧本地", "On-Device", lang: lang),
                subtitle: radar.isOnDeviceActive ? tr("ANE / 智能消除", "ANE Active", lang: lang) : tr("待机", "Standby", lang: lang),
                icon: "cpu.fill",
                color: LensTheme.emerald,
                active: radar.isOnDeviceActive
            )
            compactTile(
                title: "Apple PCC",
                subtitle: radar.isPCCActive ? tr("OHTTP 私密云", "OHTTP Live", lang: lang) : tr("待机", "Standby", lang: lang),
                icon: "lock.icloud.fill",
                color: LensTheme.sapphire,
                active: radar.isPCCActive
            )
            compactTile(
                title: isIOSMode ? tr("iPhone AI", "iPhone AI", lang: lang) : tr("外部大模型", "External AI", lang: lang),
                subtitle: !thirdActive
                    ? tr("无外连", "Clear", lang: lang)
                    : tr("\(thirdCount) 活跃", "\(thirdCount) active", lang: lang),
                icon: "network",
                color: LensTheme.amber,
                active: thirdActive
            )
        }
    }

    private func compactTile(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        active: Bool
    ) -> some View {
        SurfaceCard(tint: active ? color : nil, padding: 10, cornerRadius: 11) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(active ? color : .secondary)
                    Spacer()
                    PulseIndicatorDot(color: color, isActive: active, size: 5.5)
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(active ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - First-Seen Alert

    private var firstSeenAlertsCard: some View {
        SurfaceCard(tint: LensTheme.amber, padding: 11, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(LensTheme.amber)
                    Text(tr("陌生进程首次外连 AI API", "First-Seen AI Egress", lang: lang))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    MetaPill(text: "\(radar.firstSeenAlerts.count)")
                }

                ForEach(radar.firstSeenAlerts.prefix(2)) { alert in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(alert.appName) -> \(tr(alert.providerNameZh, alert.providerNameEn, lang: lang))")
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Text(alert.matchedDomain)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(tr("信任", "Trust", lang: lang)) {
                            radar.trustProcess(identityKey: alert.identityKey)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - Active Connections

    private var activeConnectionsCard: some View {
        SurfaceCard(padding: 11, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("当前活跃外部 AI 外连", "Active External AI Egress", lang: lang))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    MetaPill(text: "\(radar.activeLLMConnections.count)")
                }

                ForEach(radar.activeLLMConnections.prefix(4)) { conn in
                    HStack(spacing: 8) {
                        Image(nsImage: viewModel.appIcon(for: conn))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(conn.appName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text("\(conn.provider.displayName(lang: lang)) · \(conn.matchedDomain)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if !conn.isTrusted {
                            StatusBadge(text: tr("未信任", "Untrusted", lang: lang), color: LensTheme.amber)
                        }
                    }
                }
            }
        }
    }

    private var activeIOSSessionsCard: some View {
        SurfaceCard(padding: 11, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("iPhone 活跃 AI 会话", "iPhone AI Sessions", lang: lang))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    MetaPill(text: "\(radar.iosActiveSessions.count)")
                }

                ForEach(radar.iosActiveSessions.prefix(4)) { session in
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 13))
                            .foregroundStyle(session.isSuspended ? Color.secondary : LensTheme.amber)
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.appName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text("\(session.provider.displayName(lang: lang)) · \(session.status(lang: lang))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        StatusBadge(
                            text: session.isSuspended ? tr("后台", "BG", lang: lang) : tr("活跃", "Live", lang: lang),
                            color: session.isSuspended ? .secondary : LensTheme.emerald
                        )
                    }
                }
            }
        }
    }

    private var emptyConnectionsHint: some View {
        SurfaceCard(padding: 12, cornerRadius: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(LensTheme.emerald)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("当前无外部大模型直连", "No External AI Connections", lang: lang))
                        .font(.system(size: 12, weight: .medium))
                    Text(tr("仅本机按需读取只读连接表与统一日志流。", "Read-only socket metadata & local unified logs only.", lang: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Compact Timeline

    private var timelineStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("最近端云信号", "Recent Telemetry", lang: lang))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            InsetCodeWell {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(radar.recentTimeline.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(cleanTelemetryLine(line))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LensTheme.hairline)
                .frame(height: 0.75)

            HStack(spacing: 8) {
                LensActionCluster(spacing: 6) {
                    Button {
                        viewModel.selectedTab = .diagnostics
                        openWorkbench()
                    } label: {
                        Label(tr("日志排障", "Diagnose", lang: lang), systemImage: "stethoscope")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .lensGlassButton(prominent: false)
                    .controlSize(.small)

                    Button {
                        viewModel.selectedTab = .probe
                        openWorkbench()
                    } label: {
                        Label(tr("预检", "Probe", lang: lang), systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .lensGlassButton(prominent: false)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        openWorkbench()
                    } label: {
                        Label(tr("打开工作台", "Workbench", lang: lang), systemImage: "macwindow")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .lensGlassButton(prominent: true)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func openWorkbench() {
        viewModel.prepareForWorkbenchOpen()
        openWindow(id: "workbench")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
