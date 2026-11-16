import AppleLensCore
import SwiftUI

struct ProbeView: View {
    @Bindable var viewModel: AppViewModel

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.targetDeviceMode == .usbIPhone {
                    usbModeProbeBanner
                }

                customProxyStrip

                if viewModel.isProbing && viewModel.probeReport == nil {
                    loadingCard
                } else if let report = viewModel.probeReport {
                    summaryStrip(report)
                    exitLanesSection(report)
                    siriAndQuicSection(report)
                    endpointTlsSection(report)
                } else {
                    emptyCard
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassHeaderBar(
                title: tr("代理分流与防 MitM 误伤预检探针", "Routing Split & Anti-MitM Pre-Flight Probe", lang: lang),
                subtitle: tr(
                    "并发实测 Siri 直连、地区准入、PCC 盲签网关、QUIC UDP 443 与 TLS 证书链（含 Fake-IP / 代理例外核查）",
                    "Concurrently tests Siri directness, eligibility region, PCC blind-token gateways, UDP 443 QUIC & TLS pinning",
                    lang: lang
                )
            ) {
                Toggle(isOn: $viewModel.revealFullIPs) {
                    Text(tr("显示完整 IP", "Full IPs", lang: lang))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                if viewModel.probeReport != nil {
                    CopyActionButton(
                        title: tr("复制脱敏报告", "Copy Redacted Report", lang: lang),
                        copiedTitle: tr("已复制脱敏报告", "Copied Redacted", lang: lang),
                        useGlassStyle: true
                    ) {
                        viewModel.copyRedactedProbeMarkdown()
                    }
                }

                Button {
                    Task { await viewModel.runProbe() }
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.isProbing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(tr("执行四路并发预检", "Run Full Probe", lang: lang))
                    }
                }
                .lensGlassButton(prominent: true)
                .controlSize(.small)
                .disabled(viewModel.isProbing)
            }
        }
    }

    private var customProxyStrip: some View {
        SurfaceCard(padding: 12, cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LensTheme.sapphire)

                    Text(tr("自定义代理端口测试", "Custom Proxy", lang: lang))
                        .font(.system(size: 12.5, weight: .semibold))

                    Picker("", selection: $viewModel.customProxyScheme) {
                        ForEach(CustomProxyConfig.ProxyScheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue).tag(scheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 132)

                    HStack(spacing: 6) {
                        TextField(
                            tr("可选，如 127.0.0.1:6152（留空使用系统代理）", "Optional, e.g. 127.0.0.1:6152 (blank = system proxy)", lang: lang),
                            text: $viewModel.customProxyInput
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            Task { await viewModel.runProbe() }
                        }
                        .onChange(of: viewModel.customProxyInput) { _, _ in
                            viewModel.customProxyValidationError = nil
                        }

                        if !viewModel.customProxyInput.isEmpty {
                            Button {
                                viewModel.customProxyInput = ""
                                viewModel.customProxyValidationError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(tr("清除自定义代理", "Clear custom proxy", lang: lang))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                viewModel.customProxyValidationError != nil ? LensTheme.coral.opacity(0.6) : LensTheme.hairlineStrong,
                                lineWidth: 0.75
                            )
                    )

                    if let proxySummary = viewModel.lastProbeCustomProxySummary {
                        MetaPill(text: tr("上次: \(proxySummary)", "Last: \(proxySummary)", lang: lang))
                    }
                }

                if let err = viewModel.customProxyValidationError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(LensTheme.coral)
                }
            }
        }
    }

    private var usbModeProbeBanner: some View {
        SurfaceCard(tint: LensTheme.sapphire, padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(LensTheme.sapphire)
                Text(tr(
                    "主动网络探针仅测试当前这台 Mac 本机的代理分流与 TLS 证书链；如需在 iPhone 本机实测分流与延迟，请使用 iPhone 版 AppleFlow。",
                    "Active network probes run on this Mac's network stack. To probe directly on iPhone, use AppleFlow on iOS.",
                    lang: lang
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.openExternalURL(DiagnosticTranslator.appleFlowURL)
                } label: {
                    Label("AppleFlow", systemImage: "arrow.up.right.square")
                }
                .lensGlassButton(prominent: false)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Summary KPI Strip

    private func summaryStrip(_ report: FullProbeReport) -> some View {
        let siriHealthy = report.isSiriEffectivelyHealthy
        let siriValue: String = {
            if report.isSiriVIFDirectHealthy {
                return tr("直连健康 (VIF)", "Healthy (VIF)", lang: lang)
            }
            return siriHealthy ? tr("直连健康", "Healthy", lang: lang) : tr("存在风险", "Attention", lang: lang)
        }()

        let quicValue: String = {
            if report.quicAllPassed {
                return tr("畅通", "Passed", lang: lang)
            }
            if report.isQUICUsingTCPFallback {
                return tr("TCP 回退正常", "TCP H2 Fallback", lang: lang)
            }
            return tr("受阻", "Blocked", lang: lang)
        }()
        let quicColor: Color = report.quicAllPassed
            ? LensTheme.emerald
            : (report.isQUICUsingTCPFallback ? LensTheme.sapphire : LensTheme.coral)

        return HStack(spacing: 12) {
            kpiCard(
                title: tr("Siri & 区域通道", "Siri & Region", lang: lang),
                value: siriValue,
                color: siriHealthy ? LensTheme.emerald : LensTheme.amber,
                icon: siriHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            kpiCard(
                title: tr("QUIC UDP 443", "QUIC UDP 443", lang: lang),
                value: quicValue,
                color: quicColor,
                icon: "bolt.horizontal.icloud.fill"
            )
            kpiCard(
                title: tr("MitM 注入检测", "MitM Inspection", lang: lang),
                value: report.mitmDetectedCount == 0
                    ? tr("0 异常", "Clean (0)", lang: lang)
                    : tr("发现 \(report.mitmDetectedCount) 处", "\(report.mitmDetectedCount) Detected", lang: lang),
                color: report.mitmDetectedCount == 0 ? LensTheme.emerald : LensTheme.coral,
                icon: "lock.shield.fill"
            )
            kpiCard(
                title: tr("上次探针时间", "Last Probed", lang: lang),
                value: report.ranAt.formatted(date: .omitted, time: .standard),
                color: LensTheme.sapphire,
                icon: "clock"
            )
        }
    }

    private func kpiCard(title: String, value: String, color: Color, icon: String) -> some View {
        SurfaceCard(tint: color, padding: 13) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Exit Region Lanes

    private func exitLanesSection(_ report: FullProbeReport) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: tr("三路出口地区与 CDN Trace 实测", "Multi-Lane Egress Region Audit", lang: lang),
                    subtitle: tr("对比系统默认出口、Apple 生态域与 Cloudflare/AI 外连出口归属地", "Compares default route, Apple services vs. AI API exit regions", lang: lang),
                    icon: "globe.asia.australia"
                )

                HStack(alignment: .top, spacing: 12) {
                    ForEach(report.exitLanes) { lane in
                        exitLaneCard(lane)
                    }
                }

                let highLatencyAI = report.exitLanes.contains { ($0.id == "openai" || $0.id == "pccAndClaude") && $0.reachable && $0.latencyMs >= 550 }
                if highLatencyAI {
                    Text(tr(
                        "提示：当前 Mac 端部分 AI / PCC 通道延迟较高（≥550ms），建议检查本机代理策略组是否优先选用了低延迟 CN2 GIA 美区节点（如 DMIT）。",
                        "Tip: AI/PCC lane latency on this Mac is ≥550ms; selecting a lower-latency US node (e.g. CN2 GIA) in your proxy group can speed up responses.",
                        lang: lang
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exitLaneCard(_ lane: ExitRegionLaneResult) -> some View {
        let color = verdictColor(lane.verdictLevel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PulseIndicatorDot(color: color, isActive: lane.reachable, size: 5.5)
                Text(lane.title(lang: lang))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if lane.reachable {
                    MetaPill(text: "\(lane.latencyMs) ms")
                }
            }

            if lane.reachable {
                Text(RoutingProbeFormatter.formatRegionLabel(countryCode: lane.countryCode, coloCode: lane.coloCode, lang: lang))
                    .font(.system(size: 14, weight: .semibold))
                Text("\(lane.probedHost) · \(RoutingProbeFormatter.maskIP(lane.ipAddress, revealFull: viewModel.revealFullIPs))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(tr("探针超时或无法连通", "Unreachable / Timed Out", lang: lang))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LensTheme.coral)
            }

            Text(lane.verdict(lang: lang))
                .font(.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(color.opacity(0.20), lineWidth: 0.75)
        )
    }

    // MARK: - Siri Audit & QUIC

    private func siriAndQuicSection(_ report: FullProbeReport) -> some View {
        let siriHealthy = report.isSiriEffectivelyHealthy
        let quicColor = report.quicAllPassed
            ? LensTheme.emerald
            : (report.isQUICUsingTCPFallback ? LensTheme.sapphire : LensTheme.coral)

        return HStack(alignment: .top, spacing: 14) {
            SurfaceCard(tint: siriHealthy ? LensTheme.emerald : LensTheme.amber) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(
                        title: tr("Siri 直连与 Fake-IP 核查", "Siri Directness & Fake-IP Audit", lang: lang),
                        icon: "waveform"
                    )

                    HStack(spacing: 8) {
                        Text("guzzoni.apple.com:")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        let ips = report.siriAudit.guzzoniResolvedIPs
                            .prefix(2)
                            .map { RoutingProbeFormatter.maskIP($0, revealFull: viewModel.revealFullIPs) }
                            .joined(separator: ", ")
                        Text(ips.isEmpty ? tr("未解析", "Unresolved", lang: lang) : ips)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        if report.isSiriVIFDirectHealthy {
                            StatusBadge(text: tr("VIF 规则直连", "VIF DIRECT", lang: lang), color: LensTheme.emerald)
                        } else if report.siriAudit.isGuzzoniFakeIP {
                            StatusBadge(text: tr("命中 Fake-IP!", "Fake-IP!", lang: lang), color: LensTheme.coral)
                        } else {
                            StatusBadge(text: tr("真实 IP", "Real IP", lang: lang), color: LensTheme.emerald)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(tr("系统代理例外列表：", "Proxy Bypass List:", lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if report.siriAudit.systemProxyEnabled {
                            StatusBadge(
                                text: report.siriAudit.exceptionsIncludeGuzzoni
                                    ? tr("已豁免 guzzoni", "guzzoni bypassed", lang: lang)
                                    : tr("缺少 Apple 豁免", "Missing bypass", lang: lang),
                                color: report.siriAudit.exceptionsIncludeGuzzoni ? LensTheme.emerald : LensTheme.amber
                            )
                        } else {
                            MetaPill(text: tr("系统全局代理未开启", "System proxy off", lang: lang))
                        }
                        if let cname = report.siriAudit.guzzoniCanonicalName {
                            MetaPill(text: "CNAME: \(cname)")
                        }
                    }

                    Text(
                        report.siriAudit.isHealthy
                            ? tr("中文 Siri / guzzoni 直连通道正常，未落入 Fake-IP 劫持池。", "Siri / guzzoni resolution is healthy with no Fake-IP hijacking detected.", lang: lang)
                            : (report.isSiriVIFDirectHealthy
                                ? tr("当前处于 Surge 增强模式 (VIF)：本地 DNS 因 CNAME 返回了 198.18 虚拟池，但国内直连通道与 guzzoni 原生 TLS 均健康，规则已实际直连。如需消除本地 Fake-IP 显示，可在配置 `always-real-ip` 补充 `*.v.aaplimg.com`。", "Surge Enhanced Mode (VIF) returns a 198.18 virtual IP via CNAME, while DIRECT routing and guzzoni TLS are healthy. Optionally add `*.v.aaplimg.com` to `always-real-ip`.", lang: lang)
                                : tr("警告：guzzoni.apple.com 落入 Fake-IP 或缺少系统代理例外，可能导致中文 Siri 断连。建议配置 AppleFlow `DOMAIN-SUFFIX,guzzoni.apple.com,DIRECT`。", "Warning: guzzoni.apple.com hits Fake-IP or lacks proxy bypass. Add `DOMAIN-SUFFIX,guzzoni.apple.com,DIRECT`.", lang: lang))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            SurfaceCard(tint: quicColor) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(
                        title: tr("QUIC / UDP 443 真实握手测试", "QUIC / UDP 443 Handshake Probe", lang: lang),
                        icon: "bolt.horizontal.icloud"
                    )

                    ForEach(report.quicProbes) { quic in
                        HStack(spacing: 8) {
                            PulseIndicatorDot(
                                color: quic.succeeded ? LensTheme.emerald : quicColor,
                                isActive: true,
                                size: 6
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(quic.host):\(quic.port)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                Text(quic.detail(lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            MetaPill(text: "\(quic.latencyMs) ms")
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
                        )
                    }

                    if report.isQUICUsingTCPFallback {
                        Text(tr(
                            "Snell / UDP REJECT 策略生效中：UDP 443 默认不转发，但上方所有 Apple PCC 中继节点均已通过 TCP HTTP/2 正常握手，不会影响 PCC 使用。",
                            "UDP 443 is dropped by policy (expected with Snell / UDP REJECT), and all PCC relays succeeded over TCP HTTP/2.",
                            lang: lang
                        ))
                        .font(.caption)
                        .foregroundStyle(LensTheme.sapphire)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - TLS & MitM Pinning Table

    private func endpointTlsSection(_ report: FullProbeReport) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: tr("核心端点 TLS 证书链与防 MitM 误伤审计", "Core Endpoint TLS Chain & MitM Audit", lang: lang),
                    subtitle: tr("检测 Surge / Clash / Charles HTTPS 解密是否误伤 Apple 证书固定 (Pinning) 域名", "Detects whether local proxy HTTPS decryption breaks Apple pinned hosts", lang: lang),
                    icon: "lock.shield"
                )

                VStack(spacing: 8) {
                    ForEach(report.endpointProbes) { item in
                        endpointRow(item)
                    }
                }
            }
        }
    }

    private func endpointRow(_ item: EndpointTLSProbeResult) -> some View {
        let rowColor: Color? = item.isMitMDetected ? LensTheme.coral : (!item.reachable ? LensTheme.amber : nil)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.host)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    MetaPill(text: item.role(lang: lang))
                }

                if let issuer = item.issuerSummary, !issuer.isEmpty {
                    Text(tr("签发链路：", "Issuer Chain: ", lang: lang) + issuer)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let err = item.errorDescription {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(LensTheme.coral)
                        .lineLimit(1)
                }

                if item.isMitMDetected, let reason = item.mitmReason {
                    Text(tr("检测到非官方根证书 / MitM：", "Proxy MitM / Custom CA detected: ", lang: lang) + reason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LensTheme.coral)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                MetaPill(text: item.expectDirect ? tr("应直连", "Direct", lang: lang) : tr("可代理", "Proxy OK", lang: lang))
                if item.pinningSensitive {
                    MetaPill(text: "Pinned")
                }

                if item.isMitMDetected {
                    StatusBadge(text: tr("MitM 拦截", "MitM", lang: lang), color: LensTheme.coral, icon: "xmark.shield.fill")
                } else if !item.reachable {
                    StatusBadge(text: tr("不通", "Unreachable", lang: lang), color: LensTheme.amber)
                } else {
                    StatusBadge(text: tr("原生链 (\(item.latencyMs)ms)", "Clean (\(item.latencyMs)ms)", lang: lang), color: LensTheme.emerald)
                }
            }
        }
        .padding(10)
        .background(
            (rowColor?.opacity(0.065) ?? Color.primary.opacity(0.032)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowColor?.opacity(0.24) ?? LensTheme.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Loading & Empty States

    private var loadingCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("正在执行四路并发探针…", "Running Concurrent Multi-Lane Probe…", lang: lang))
                        .font(.system(size: 14, weight: .semibold))
                    Text(tr("正在测试 DNS Fake-IP、CDN 出口地域、TLS 证书固定链以及 UDP 443 QUIC 握手。", "Testing DNS Fake-IP, egress geography, TLS certificate pinning chains & UDP 443 QUIC.", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var emptyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("点击「执行四路并发预检」开始体检", "Click 'Run Full Probe' to Start Pre-Flight Verification", lang: lang))
                    .font(.system(size: 14, weight: .semibold))
                Text(tr(
                    "探针将同时核验：gspe1-ssl 准入通道、guzzoni/siri 直连、apple-relay / thrombin / aether / publisher TLS 证书防 MitM 误伤，以及 UDP 443 QUIC 可用性。",
                    "Verifies gspe1-ssl eligibility lane, guzzoni/siri directness, PCC gateway pinning against MitM, and QUIC UDP 443 health.",
                    lang: lang
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func verdictColor(_ level: ProbeVerdictLevel) -> Color {
        switch level {
        case .pass: return LensTheme.emerald
        case .warn: return LensTheme.amber
        case .error: return LensTheme.coral
        }
    }
}
