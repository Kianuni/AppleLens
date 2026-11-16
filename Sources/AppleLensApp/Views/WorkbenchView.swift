import AppleLensCore
import SwiftUI

struct WorkbenchView: View {
    @Bindable var viewModel: AppViewModel
    let isDropTargeted: Bool

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 244)

            Rectangle()
                .fill(LensTheme.hairline)
                .frame(width: 0.75)
                .ignoresSafeArea()

            detailContainer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("", selection: targetModeBinding) {
                    ForEach(TargetDeviceMode.allCases) { mode in
                        Label(mode.label(lang: lang), systemImage: mode.sfSymbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 248)
                .help(tr("切换监测目标：本机 Mac 或 USB 连线 iPhone", "Switch Target: This Mac or USB iPhone", lang: lang))
            }

            if viewModel.targetDeviceMode == .usbIPhone, viewModel.connectedDevices.count > 1 {
                ToolbarItem(placement: .automatic) {
                    Picker(tr("iPhone", "iPhone", lang: lang), selection: $viewModel.selectedDeviceUDID) {
                        ForEach(viewModel.connectedDevices) { dev in
                            Text(dev.displayTitle).tag(Optional(dev.id))
                        }
                    }
                    .frame(maxWidth: 210)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                LensActionCluster(spacing: 8) {
                    LanguageToggleButton(manager: viewModel.language)

                    Button {
                        Task { await viewModel.refreshRadarAndStreams() }
                    } label: {
                        Label(tr("刷新", "Scan", lang: lang), systemImage: "arrow.clockwise")
                    }
                    .lensGlassButton(prominent: false)
                    .controlSize(.small)

                    SettingsPreferencesMenu(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            viewModel.setWorkbenchVisible(true)
        }
        .onDisappear {
            viewModel.setWorkbenchVisible(false)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    private var targetModeBinding: Binding<TargetDeviceMode> {
        Binding(
            get: { viewModel.targetDeviceMode },
            set: { newValue in viewModel.switchTargetDeviceMode(newValue) }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            VibrancyBackdrop(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    MiniPrismEmblem(size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AppleLens")
                            .font(.system(size: 14, weight: .semibold))
                        Text(tr("端云 AI 透明度套件", "Zero-MitM Inspector", lang: lang))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)

                VStack(spacing: 4) {
                    ForEach(WorkbenchTab.allCases) { tab in
                        Button {
                            viewModel.selectedTab = tab
                        } label: {
                            sidebarRow(for: tab)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 0)

                sourceTelemetryFooter
            }
        }
    }

    private func sidebarRow(for tab: WorkbenchTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return HStack(spacing: 9) {
            Image(systemName: tab.sfSymbol)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? LensTheme.sapphire : .secondary)
                .frame(width: 18)

            Text(tab.title(lang: lang))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 4)

            switch tab {
            case .radar:
                PulseIndicatorDot(
                    color: viewModel.radar.overallState.tintColor,
                    isActive: viewModel.radar.overallState != .idle,
                    size: 6
                )
            case .diagnostics:
                if viewModel.currentTargetFindingsCount > 0 {
                    MetaPill(text: "\(viewModel.currentTargetFindingsCount)")
                }
            case .probe:
                if let report = viewModel.probeReport, report.mitmDetectedCount > 0 {
                    StatusBadge(text: "\(report.mitmDetectedCount)", color: LensTheme.coral)
                }
            case .reportLens:
                if let report = viewModel.currentReport {
                    MetaPill(text: "\(report.requests.count)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LensTheme.sapphire.opacity(0.15))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(LensTheme.sapphire.opacity(0.32), lineWidth: 0.75)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Read-only target & architecture telemetry card at the sidebar footer (avoids duplicating the toolbar picker).
    private var sourceTelemetryFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LensTheme.hairline)
                .frame(height: 0.75)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    PulseIndicatorDot(
                        color: viewModel.isLiveStreaming || viewModel.targetDeviceMode == .thisMac
                            ? LensTheme.emerald
                            : LensTheme.sapphire,
                        isActive: viewModel.isLiveStreaming || viewModel.activeConnectedDevice != nil,
                        size: 5.5
                    )
                    Text(viewModel.targetDeviceMode.label(lang: lang))
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    MetaPill(text: radarPollIntervalText(radar: viewModel.radar, lang: lang))
                    MetaPill(text: viewModel.radar.overallState.shortBadgeLabel(lang: lang))
                }

                if viewModel.targetDeviceMode == .usbIPhone {
                    if let dev = viewModel.activeConnectedDevice {
                        Text(dev.displayTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if !viewModel.isUSBFrameworkAvailable {
                        Text(tr("MobileDevice 私有框架不可用", "MobileDevice unavailable", lang: lang))
                            .font(.system(size: 11))
                            .foregroundStyle(LensTheme.amber)
                    } else {
                        Text(tr("请通过 USB 连接并信任此 Mac", "Connect iPhone via USB & tap Trust", lang: lang))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(tr("零 MitM · 纯本地只读架构", "Zero-MitM · Read-only local telemetry", lang: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Detail Container

    @ViewBuilder
    private var detailContainer: some View {
        ZStack {
            VibrancyBackdrop(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color(nsColor: .windowBackgroundColor)
                .opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                UpdateStatusNoticeBar(viewModel: viewModel)

                Group {
                    switch viewModel.selectedTab {
                    case .radar:
                        RadarView(viewModel: viewModel)
                    case .diagnostics:
                        DiagnosticsView(viewModel: viewModel)
                    case .probe:
                        ProbeView(viewModel: viewModel)
                    case .reportLens:
                        ReportLensView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Drag & Drop Glass Overlay

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                MiniPrismEmblem(size: 52)
                Text(tr("松开以在透明报告镜中解码", "Drop to Decode in Report Lens", lang: lang))
                    .font(.title3.weight(.semibold))
                Text(tr("支持 Apple_Intelligence_Report.json 或 .log / .txt 系统日志", "Supports Apple_Intelligence_Report.json or .log / .txt captures", lang: lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .lensFloatingGlass(cornerRadius: 20)
        }
    }
}
