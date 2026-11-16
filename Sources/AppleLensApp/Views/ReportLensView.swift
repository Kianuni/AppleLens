import AppleLensCore
import SwiftUI

struct ReportLensView: View {
    @Bindable var viewModel: AppViewModel
    @State private var isSummaryExpanded: Bool = true

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        Group {
            if let report = viewModel.currentReport {
                reportWorkspace(report)
            } else {
                emptyState
            }
        }
        .onAppear {
            viewModel.refreshLatestDownloadsReport()
        }
        .onChange(of: viewModel.currentReport?.parsedAt) { _, _ in
            isSummaryExpanded = true
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassHeaderBar(
                title: tr("Apple_Intelligence_Report.json 透明透视镜", "Apple_Intelligence_Report.json Lens", lang: lang),
                subtitle: tr(
                    "零外部依赖原生解码：隐藏 System Prompt、Silent Thinking、Tool Calling、PCC AttestationBundle 与 X.509 证书链",
                    "Zero-dependency native decoder: hidden System Prompts, Tool Calling, PCC AttestationBundle & X.509 chains",
                    lang: lang
                )
            ) {
                if viewModel.currentReport != nil {
                    closeReportButton
                    headerButton(tr("系统设置导出入口", "Report Settings", lang: lang), icon: "gearshape") {
                        viewModel.openMacIntelligenceReportSettings()
                    }
                } else {
                    headerButton(tr("一键直达系统设置", "Open Report Settings", lang: lang), icon: "gearshape") {
                        viewModel.openMacIntelligenceReportSettings()
                    }
                    headerButton(tr("载入内置样板", "Load Sample Report", lang: lang), icon: "doc.viewfinder") {
                        viewModel.loadDemoReport()
                    }
                }
                headerButton(tr("选择 JSON 报告…", "Open Report JSON…", lang: lang), icon: "folder", prominent: true) {
                    viewModel.openOpenPanelForReportJSON()
                }
            }
        }
    }

    private var closeReportButton: some View {
        headerButton(
            viewModel.isShowingDemoReport ? tr("退出样板", "Exit Sample", lang: lang) : tr("关闭报告", "Close Report", lang: lang),
            icon: "xmark.circle"
        ) {
            viewModel.closeCurrentReport()
        }
    }

    private func headerButton(_ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .lensGlassButton(prominent: prominent)
        .controlSize(.small)
    }

    // MARK: - Empty Drop Zone

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let err = viewModel.reportError {
                    SurfaceCard(tint: LensTheme.coral) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(LensTheme.coral)
                            Text(err).font(.caption)
                            Spacer()
                        }
                    }
                }

                if let recentURL = viewModel.latestDownloadsReportURL {
                    recentReportCard(recentURL)
                }

                SurfaceCard(padding: 32, cornerRadius: 18) {
                    VStack(spacing: 14) {
                        MiniPrismEmblem(size: 56)

                        Text(tr("将 Apple_Intelligence_Report.json 直接拖入窗口", "Drag & Drop Apple_Intelligence_Report.json Here", lang: lang))
                            .font(.system(size: 16, weight: .semibold))

                        Text(tr(
                            "支持从本机 Mac 或 iPhone 导出的 Apple_Intelligence_Report.json。全部提示词、AttestationBundle 与证书链解析均在本地离线完成，不上传任何数据。",
                            "Supports Apple_Intelligence_Report.json exported from Mac or iPhone. 100% offline native decoding with zero external telemetry.",
                            lang: lang
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)

                        LensActionCluster(spacing: 10) {
                            Button {
                                viewModel.openMacIntelligenceReportSettings()
                            } label: {
                                Label(tr("一键直达：系统设置 → Apple 智能报告", "Open Settings -> Apple Intelligence Report", lang: lang), systemImage: "gearshape.fill")
                            }
                            .lensGlassButton(prominent: true)

                            Button {
                                viewModel.openOpenPanelForReportJSON()
                            } label: {
                                Label(tr("选择 JSON 文件（默认打开下载目录）", "Choose JSON File (Downloads)…", lang: lang), systemImage: "folder")
                            }
                            .lensGlassButton(prominent: false)

                            Button {
                                viewModel.loadDemoReport()
                            } label: {
                                Label(tr("载入内置 PCC 演示样板", "Load Built-In PCC Demo Sample", lang: lang), systemImage: "doc.viewfinder")
                            }
                            .lensGlassButton(prominent: false)
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                }

                exportGuideSection
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
    }

    private func recentReportCard(_ url: URL) -> some View {
        let modifiedDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return SurfaceCard(tint: LensTheme.emerald, padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LensTheme.emerald.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LensTheme.emerald)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tr("发现最近导出的报告", "Recent Exported Report Detected", lang: lang))
                            .font(.system(size: 13.5, weight: .semibold))
                        MetaPill(text: "~/Downloads")
                    }
                    HStack(spacing: 8) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let modifiedDate {
                            Text(modifiedDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                Button {
                    viewModel.openLatestDownloadsReport()
                } label: {
                    Label(tr("一键打开最近报告", "Open Recent Exported Report", lang: lang), systemImage: "arrow.right.circle.fill")
                }
                .lensGlassButton(prominent: true, tint: LensTheme.emerald)
                .controlSize(.small)
            }
        }
    }

    private var exportGuideSection: some View {
        HStack(alignment: .top, spacing: 14) {
            exportGuideCard(
                tint: LensTheme.sapphire,
                icon: "laptopcomputer",
                title: tr("本机 Mac 获取步骤（一键直达）", "Where to Export on This Mac", lang: lang),
                steps: [
                    tr("点击上方「一键直达：系统设置 → Apple 智能报告」（路径：系统设置 → 隐私与安全性 → Apple 智能报告）。", "Click \"Open Settings -> Apple Intelligence Report\" above (System Settings -> Privacy & Security -> Apple Intelligence Report).", lang: lang),
                    tr("开启报告记录（可选「15 分钟」或「7 天」），然后在本机触发一次 Siri、写作工具或照片 AI 请求。", "Enable Report Duration (15 Minutes or 7 Days), then trigger a Siri, Writing Tools, or Photos AI request.", lang: lang),
                    tr("点击底部的「导出活动 (Export Activity)…」，将生成的 Apple_Intelligence_Report.json 保存到「下载」文件夹并拖入本窗口。", "Click \"Export Activity…\", save Apple_Intelligence_Report.json to Downloads, then drop or select it here.", lang: lang)
                ],
                buttonTitle: tr("直达系统设置「Apple 智能报告」", "Jump to Report Settings", lang: lang),
                buttonIcon: "arrow.up.right.square",
                action: { viewModel.openMacIntelligenceReportSettings() }
            )

            exportGuideCard(
                tint: LensTheme.emerald,
                icon: "iphone",
                title: tr("iPhone 获取步骤（隔空投送至 Mac）", "Where to Export on iPhone (AirDrop)", lang: lang),
                steps: [
                    tr("在 iPhone 打开：设置 → 隐私与安全性 → Apple 智能报告，确认已开启记录（建议选「过去 15 分钟」）。", "On iPhone open Settings -> Privacy & Security -> Apple Intelligence Report and ensure logging is enabled.", lang: lang),
                    tr("触发一次「相册高质量消除」「写作工具」或 PCC 对话，再滑到底部点击「导出活动 (Export Activity)」。", "Run Photos Clean Up, Writing Tools, or PCC Siri, then tap \"Export Activity\" at the bottom.", lang: lang),
                    tr("在分享页选择「隔空投送 (AirDrop)」到这台 Mac；文件会默认保存在 Mac 的 ~/Downloads（下载）目录下（Apple_Intelligence_Report.json）。", "Choose AirDrop to this Mac; macOS saves Apple_Intelligence_Report.json into ~/Downloads.", lang: lang)
                ],
                buttonTitle: tr("在访达打开「下载」文件夹", "Open Downloads in Finder", lang: lang),
                buttonIcon: "arrow.down.circle",
                action: { viewModel.openDownloadsFolderInFinder() }
            )
        }
    }

    private func exportGuideCard(
        tint: Color,
        icon: String,
        title: String,
        steps: [String],
        buttonTitle: String,
        buttonIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        SurfaceCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, text in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .frame(width: 18, height: 18)
                            .background(tint.opacity(0.14), in: Circle())
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Spacer()
                    Button(action: action) { Label(buttonTitle, systemImage: buttonIcon) }
                        .lensGlassButton(prominent: false, tint: tint)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Decoded Report Workspace

    private func reportWorkspace(_ report: ParsedAppleIntelligenceReport) -> some View {
        VStack(spacing: 0) {
            summaryHeaderBar(report)
            executiveSummarySection(report)

            HStack(spacing: 0) {
                requestListPane(report)
                    .frame(width: 296)
                Rectangle()
                    .fill(LensTheme.hairline)
                    .frame(width: 0.75)
                inspectorPane(report)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func executiveSummarySection(_ report: ParsedAppleIntelligenceReport) -> some View {
        let summary = ReportInsightEngine.summarize(report: report)
        let style = verdictStyle(summary.tone)
        let features = summary.detectedFeatures(lang: lang)

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: style.icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(style.color)
                    StatusBadge(text: summary.badge(lang: lang), color: style.color)
                    Text(summary.headline(lang: lang))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { isSummaryExpanded.toggle() }
                    } label: {
                        Label(
                            isSummaryExpanded ? tr("收起结论", "Hide Summary", lang: lang) : tr("展开解读", "Show Summary", lang: lang),
                            systemImage: isSummaryExpanded ? "chevron.up" : "chevron.down"
                        )
                    }
                    .lensGlassButton(prominent: false, tint: style.color)
                    .controlSize(.small)
                }

                if isSummaryExpanded {
                    Text(summary.subheadline(lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !features.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text(tr("识别能力：", "Capabilities:", lang: lang))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(features, id: \.self) { MetaPill(text: $0) }
                            }
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(minimum: 220), spacing: 10), GridItem(.flexible(minimum: 220), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(summary.bullets) { bullet in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: bullet.icon)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(style.color)
                                    Text(bullet.title(lang: lang))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                Text(bullet.detail(lang: lang))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(style.color.opacity(0.18), lineWidth: 0.75))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(style.color.opacity(0.045))
                }
            }

            Rectangle().fill(LensTheme.hairline).frame(height: 0.75)
        }
    }

    private func summaryHeaderBar(_ report: ParsedAppleIntelligenceReport) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(report.sourceFileName, systemImage: "doc.text.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                if viewModel.isShowingDemoReport {
                    StatusBadge(text: tr("演示样板", "Demo Sample", lang: lang), color: LensTheme.amber)
                }

                MetaPill(text: tr("总请求 \(report.requests.count)", "\(report.requests.count) Requests", lang: lang))
                StatusBadge(text: tr("端侧 \(report.onDeviceRequestCount)", "On-Device \(report.onDeviceRequestCount)", lang: lang), color: LensTheme.emerald)
                StatusBadge(text: tr("PCC \(report.pccRequestCount)", "PCC \(report.pccRequestCount)", lang: lang), color: LensTheme.sapphire)
                MetaPill(text: tr("Attestation \(report.attestationCount)", "\(report.attestationCount) Attestations", lang: lang))
                Spacer()
                closeReportButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)

            Rectangle().fill(LensTheme.hairline).frame(height: 0.75)
        }
    }

    private func requestListPane(_ report: ParsedAppleIntelligenceReport) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(report.requests) { req in
                    let isSelected = viewModel.selectedRequestID == req.id
                    let accent = req.executionTarget == .privateCloudCompute ? LensTheme.sapphire : LensTheme.emerald
                    Button {
                        viewModel.selectedRequestID = req.id
                    } label: {
                        requestListCardContent(req, accent: accent)
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.11))
                                } else {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.035))
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(isSelected ? accent.opacity(0.38) : LensTheme.hairline, lineWidth: 0.75)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
    }

    private func requestListCardContent(_ req: ParsedModelRequestItem, accent: Color) -> some View {
        let interp = ReportInsightEngine.interpret(request: req)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                PulseIndicatorDot(color: accent, isActive: true, size: 5)
                StatusBadge(text: req.executionTarget.label(lang: lang), color: accent)
                Spacer()
                if let ts = req.timestamp {
                    Text(ts.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Label(interp.featureTitle(lang: lang), systemImage: interp.categoryIcon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(req.useCase)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let model = req.modelIdentifier {
                    Text(model)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if !req.toolCalls.isEmpty || !req.pccRequests.isEmpty {
                HStack(spacing: 6) {
                    if !req.toolCalls.isEmpty {
                        MetaPill(text: "\(req.toolCalls.count) tool")
                    }
                    let attCount = req.pccRequests.filter { $0.attestation != nil }.count
                    if attCount > 0 {
                        MetaPill(text: tr("证明 \(attCount)", "\(attCount) att", lang: lang))
                    }
                }
            }
        }
    }

    private func inspectorPane(_ report: ParsedAppleIntelligenceReport) -> some View {
        Group {
            if let req = viewModel.selectedRequest {
                ScrollView {
                    ReportInspectorTabsView(viewModel: viewModel, request: req, assets: report.assets)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
            } else {
                Text(tr("在左侧选择一次 AI 请求记录进行透视", "Select a request on the left to inspect", lang: lang))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func verdictStyle(_ tone: ReportVerdictTone) -> (color: Color, icon: String) {
        switch tone {
        case .onDevicePure: return (LensTheme.emerald, "cpu.fill")
        case .pccCloudVerified: return (LensTheme.sapphire, "checkmark.shield.fill")
        case .hybridSynergy: return (LensTheme.plum, "sparkles")
        case .emptyReport: return (LensTheme.amber, "exclamationmark.circle.fill")
        }
    }
}
