import AppleLensCore
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var viewModel: AppViewModel

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controlCard
                filterBar

                if !viewModel.filteredFindings.isEmpty {
                    findingsSection
                } else {
                    emptyFindingsCard
                }

                rawLogConsoleSection
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassHeaderBar(
                title: tr("端云日志与一键人话排障台", "Live Logs & Plain-Language Diagnostics", lang: lang),
                subtitle: tr(
                    "实时/回溯监听 privatecloudcomputed、eligibilityd、assistantd、modelmanagerd，并自动翻译典型错误与修复步骤",
                    "Streams or scans privatecloudcomputed, eligibilityd, assistantd & modelmanagerd logs with instant remediation guidance",
                    lang: lang
                )
            ) {
                if viewModel.currentTargetFindingsCount > 0 {
                    CopyActionButton(
                        title: tr("复制脱敏诊断单", "Copy Redacted Report", lang: lang),
                        copiedTitle: tr("已复制脱敏诊断单", "Copied Redacted", lang: lang),
                        useGlassStyle: true
                    ) {
                        viewModel.copyRedactedDiagnosticsMarkdown()
                    }
                }

                if viewModel.currentTargetFindingsCount > 0 || !viewModel.filteredRawEvents.isEmpty {
                    Button(tr("清空", "Clear", lang: lang)) {
                        viewModel.clearDiagnostics()
                    }
                    .lensGlassButton(prominent: false)
                    .controlSize(.small)
                }

                Button {
                    viewModel.openOpenPanelForLogFile()
                } label: {
                    Label(tr("导入日志", "Import Log", lang: lang), systemImage: "folder")
                }
                .lensGlassButton(prominent: false)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Controls

    private var controlCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    LensActionCluster(spacing: 8) {
                        Button {
                            viewModel.toggleLiveStream()
                        } label: {
                            let isMac = viewModel.targetDeviceMode == .thisMac
                            let activeLabel = isMac
                                ? tr("停止 Mac 实时监听", "Stop Mac Live Stream", lang: lang)
                                : tr("停止 iPhone 实时监听", "Stop iPhone Live Stream", lang: lang)
                            let idleLabel = isMac
                                ? tr("开启 Mac 实时日志流", "Start Mac Live Stream", lang: lang)
                                : tr("开启 iPhone 实时日志流", "Start iPhone Live Stream", lang: lang)
                            Label(
                                viewModel.isLiveStreaming ? activeLabel : idleLabel,
                                systemImage: viewModel.isLiveStreaming ? "stop.circle.fill" : "play.circle.fill"
                            )
                        }
                        .lensGlassButton(
                            prominent: true,
                            tint: viewModel.isLiveStreaming ? LensTheme.coral : LensTheme.sapphire
                        )

                        Button {
                            Task { await viewModel.scanLast15Minutes() }
                        } label: {
                            HStack(spacing: 5) {
                                if viewModel.isScanningHistory {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "clock.arrow.2.circlepath")
                                }
                                Text(tr("回溯最近 15 分钟日志", "Scan Last 15m Logs", lang: lang))
                            }
                        }
                        .lensGlassButton(prominent: false)
                        .disabled(viewModel.isScanningHistory || viewModel.targetDeviceMode == .usbIPhone)

                        Button {
                            viewModel.simulateSampleDiagnostics()
                        } label: {
                            Label(tr("载入典型故障演示", "Load Diagnostic Sample", lang: lang), systemImage: "waveform.path.ecg")
                        }
                        .lensGlassButton(prominent: false)
                    }

                    Spacer()

                    let otherBackgroundStreaming = viewModel.targetDeviceMode == .thisMac
                        ? viewModel.isIOSLiveStreaming
                        : viewModel.isMacLiveStreaming
                    if otherBackgroundStreaming {
                        MetaPill(
                            text: viewModel.targetDeviceMode == .thisMac
                                ? tr("iPhone 后台监听中", "iPhone Background Streaming", lang: lang)
                                : tr("Mac 后台监听中", "Mac Background Streaming", lang: lang)
                        )
                    }

                    if viewModel.isLiveStreaming {
                        HStack(spacing: 6) {
                            PulseIndicatorDot(color: LensTheme.emerald, isActive: true, size: 6)
                            Text(
                                viewModel.targetDeviceMode == .thisMac
                                    ? tr("Mac 监听中", "Mac Streaming", lang: lang)
                                    : tr("iPhone 监听中", "iPhone Streaming", lang: lang)
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LensTheme.emerald)
                        }
                    }
                }

                if viewModel.targetDeviceMode == .usbIPhone {
                    usbStatusBanner
                }

                if let err = viewModel.streamError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(LensTheme.coral)
                } else if let notice = viewModel.diagnosticsStatusNotice {
                    Label(notice, systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(LensTheme.sapphire)
                }
            }
        }
    }

    private var usbStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector")
                .foregroundStyle(LensTheme.sapphire)
            if let dev = viewModel.activeConnectedDevice {
                Text(tr(
                    "已锁定 USB 设备：\(dev.displayTitle) — 直接通过系统 MobileDevice 通道只读接收 syslog。",
                    "Target USB device: \(dev.displayTitle) — read-only syslog relay via system MobileDevice.",
                    lang: lang
                ))
                .font(.caption)
            } else if !viewModel.isUSBFrameworkAvailable {
                Text(tr(
                    "本机未加载 MobileDevice 私有框架，无法读取 USB iPhone 日志（可切换回 This Mac 或导入 .log 文件）。",
                    "MobileDevice framework unavailable on this host. Switch to This Mac or import a .log file.",
                    lang: lang
                ))
                .font(.caption)
                .foregroundStyle(LensTheme.amber)
            } else {
                Text(tr(
                    "未检测到已配对的 USB iPhone。请使用数据线连接 iPhone，并在 iPhone 上点击“信任此电脑”。",
                    "No paired USB iPhone detected. Connect via USB cable and tap 'Trust This Computer' on iPhone.",
                    lang: lang
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(LensTheme.sapphire.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LensTheme.sapphire.opacity(0.18), lineWidth: 0.75)
        )
    }

    // MARK: - Search & Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField(
                    tr("搜索进程、子系统或关键词（如 32033、QUIC、1009、CH、guzzoni）", "Search process, subsystem, or keywords (32033, QUIC, 1009, CH, guzzoni)", lang: lang),
                    text: $viewModel.logSearchQuery
                )
                .textFieldStyle(.plain)
                if !viewModel.logSearchQuery.isEmpty {
                    Button {
                        viewModel.logSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LensTheme.hairlineStrong, lineWidth: 0.75)
            )

            Picker("", selection: $viewModel.severityFilter) {
                Text(tr("全部级别", "All Severities", lang: lang)).tag(DiagnosticSeverity?.none)
                Text(DiagnosticSeverity.critical.label(lang: lang)).tag(Optional(DiagnosticSeverity.critical))
                Text(DiagnosticSeverity.warning.label(lang: lang)).tag(Optional(DiagnosticSeverity.warning))
                Text(DiagnosticSeverity.info.label(lang: lang)).tag(Optional(DiagnosticSeverity.info))
            }
            .frame(width: 154)
        }
    }

    // MARK: - Findings List

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: tr("自动识别并翻译的诊断结论 (\(viewModel.filteredFindings.count))", "Translated Diagnostic Findings (\(viewModel.filteredFindings.count))", lang: lang),
                icon: "stethoscope"
            )

            ForEach(viewModel.filteredFindings) { finding in
                findingCard(finding)
            }
        }
    }

    private func findingCard(_ finding: DiagnosticFinding) -> some View {
        let color = severityColor(finding.severity)
        return SurfaceCard(tint: color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    StatusBadge(
                        text: finding.severity.label(lang: lang),
                        color: color,
                        icon: finding.severity == .critical ? "xmark.octagon.fill" : (finding.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    )

                    Text(finding.title(lang: lang))
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    MetaPill(text: finding.processName)
                    Text(finding.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(finding.explanation(lang: lang))
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = finding.progressFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(LensTheme.sapphire)
                        Text(tr("端侧模型资产下载进度：\(Int(progress * 100))%", "On-device model asset download progress: \(Int(progress * 100))%", lang: lang))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        finding.severity == .info
                            ? tr("状态解读与查看位置：", "Status Note & Where to Check:", lang: lang)
                            : tr("建议修复方案：", "Recommended Remediation:", lang: lang)
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(finding.remediation(lang: lang))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LensTheme.emerald.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LensTheme.emerald.opacity(0.18), lineWidth: 0.75)
                )

                if let snippet = finding.copyableSnippet {
                    InsetCodeWell {
                        HStack(alignment: .top, spacing: 8) {
                            Text(snippet)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CopySnippetButton(text: snippet, lang: lang) {
                                viewModel.copyToPasteboard($0)
                            }
                        }
                    }
                }

                if let actionURL = finding.actionURL, let label = finding.actionLabel(lang: lang) {
                    Button {
                        viewModel.openExternalURL(actionURL)
                    } label: {
                        Label(label, systemImage: "arrow.up.right.square")
                    }
                    .lensGlassButton(prominent: false)
                    .controlSize(.small)
                }

                DisclosureGroup(tr("查看原始系统日志行", "View Raw Unified Log Line", lang: lang)) {
                    InsetCodeWell {
                        Text(finding.rawLine)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyFindingsCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("尚无命中的典型报错模式", "No Known Error Signatures Matched Yet", lang: lang))
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(tr(
                        "可点击「回溯最近 15 分钟日志」、「开启实时日志流」，或点击「载入典型故障演示」体验全套人话翻译引擎（Code=32033 / QUIC / 1009 / iOS 27.3 CH / guzzoni）。",
                        "Click 'Scan Last 15m Logs', 'Start Live Stream', or 'Load Diagnostic Sample' to inspect the plain-language translator.",
                        lang: lang
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Raw Log Console

    private var rawLogConsoleSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: tr("原始日志流缓冲 (\(viewModel.filteredRawEvents.count) 条)", "Raw Log Buffer (\(viewModel.filteredRawEvents.count) events)", lang: lang),
                    icon: "terminal"
                )

                if viewModel.filteredRawEvents.isEmpty {
                    Text(tr("暂无原始日志事件。", "No raw log events captured.", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    InsetCodeWell(maxHeight: 240) {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(viewModel.filteredRawEvents.prefix(150)) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .foregroundStyle(.tertiary)
                                    Text(event.processName)
                                        .foregroundStyle(event.isPCCSignal ? LensTheme.sapphire : (event.isOnDeviceInferenceSignal ? LensTheme.emerald : .secondary))
                                        .frame(width: 155, alignment: .leading)
                                        .lineLimit(1)
                                    Text(event.message)
                                        .foregroundStyle(.primary.opacity(0.9))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                }
            }
        }
    }

    private func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .critical: return LensTheme.coral
        case .warning: return LensTheme.amber
        case .info: return LensTheme.sapphire
        }
    }
}
