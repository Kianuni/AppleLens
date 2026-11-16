import Foundation

/// Privacy-redacting Markdown formatter for routing probe reports and unified diagnostic findings.
public enum DiagnosticReportFormatter {
    private static let ipv4Regex = try? NSRegularExpression(
        pattern: #"(?<![\d.])(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}(?![\d.])"#
    )
    private static let ipv6Regex = try? NSRegularExpression(
        pattern: #"(?<![0-9A-Fa-f:])(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?:(?::[0-9A-Fa-f]{1,4}){1,7}|:))(?:%[A-Za-z0-9_.-]+)?(?![0-9A-Fa-f:])"#
    )
    private static let udidRegex = try? NSRegularExpression(
        pattern: #"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{24,40})(?![0-9A-Fa-f])"#
    )
    private static let possessiveDeviceRegex = try? NSRegularExpression(
        pattern: #"[^\s:：,，;；()（）\[\]【】"'“”‘’=<>\/]+(?:\s*['’]s\s+|\s*的\s*)(?:iPhone|iPad)\b"#,
        options: [.caseInsensitive]
    )

    /// Masks public and Fake-IP IPv4/IPv6 addresses (preserving `127.0.0.1` / `::1` loopback),
    /// scrubs 24–40 char hex/UUID UDIDs, and scrubs possessive device names (e.g. `Alex's iPhone`, `张三的 iPhone`).
    public static func redactSensitiveText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var output = text
        output = replaceMatches(of: possessiveDeviceRegex, in: output) { _ in
            "USB iPhone"
        }
        output = replaceMatches(of: udidRegex, in: output) { _ in
            "<REDACTED-UDID>"
        }
        output = replaceMatches(of: ipv6Regex, in: output) { matched in
            let bare = matched.split(separator: "%", maxSplits: 1).first.map(String.init) ?? matched
            if bare == "::1" || bare == "::" {
                return bare
            }
            let parts = bare.split(separator: ":")
            if parts.count >= 2 {
                return "\(parts[0]):\(parts[1]):*:*"
            }
            if parts.count == 1 {
                return "\(parts[0]):*:*:*"
            }
            return matched
        }
        output = replaceMatches(of: ipv4Regex, in: output) { matched in
            if matched == "127.0.0.1" {
                return matched
            }
            let parts = matched.split(separator: ".")
            guard parts.count == 4 else { return matched }
            return "\(parts[0]).\(parts[1]).*.*"
        }
        return output
    }

    /// Formats a `FullProbeReport` into a redacted, shareable Markdown summary.
    public static func formatProbeMarkdown(
        _ report: FullProbeReport,
        customProxySummary: String? = nil,
        lang: AppLanguage
    ) -> String {
        var lines: [String] = []
        let timestampText = formatTimestamp(report.ranAt)

        lines.append(tr("# AppleLens 路由与证书脱敏探测报告", "# AppleLens Redacted Routing & TLS Probe Report", lang: lang))
        lines.append("")
        lines.append("- **\(tr("探测时间", "Timestamp", lang: lang))**: \(timestampText)")
        if let proxy = customProxySummary?.trimmingCharacters(in: .whitespacesAndNewlines), !proxy.isEmpty {
            lines.append("- **\(tr("自定义代理测试", "Custom Proxy Override", lang: lang))**: `\(redactSensitiveText(proxy))`")
        }

        let siriSummary: String
        if report.isSiriVIFDirectHealthy {
            siriSummary = tr("✅ 健康（Surge VIF 直连生效）", "✅ Healthy (Surge VIF Direct)", lang: lang)
        } else if report.isSiriEffectivelyHealthy {
            siriSummary = tr("✅ 健康", "✅ Healthy", lang: lang)
        } else {
            siriSummary = tr("❌ 存在代理或 Fake-IP 风险", "❌ Proxy / Fake-IP Misroute Detected", lang: lang)
        }
        let mitmSummary = report.mitmDetectedCount == 0
            ? tr("✅ 0 处 MitM 劫持", "✅ 0 MitM Interceptions", lang: lang)
            : tr("🚨 发现 \(report.mitmDetectedCount) 处 MitM 风险", "🚨 \(report.mitmDetectedCount) MitM Risk(s) Detected", lang: lang)
        let quicSummary: String
        if report.quicAllPassed {
            quicSummary = tr("✅ UDP 443 QUIC 畅通", "✅ UDP 443 QUIC Healthy", lang: lang)
        } else if report.isQUICUsingTCPFallback {
            quicSummary = tr("⚠️ UDP 443 受限（TCP HTTP/2 回退健康）", "⚠️ UDP 443 Restricted (TCP HTTP/2 Fallback Healthy)", lang: lang)
        } else {
            quicSummary = tr("⚠️ UDP 443 QUIC 部分失败", "⚠️ UDP 443 QUIC Degraded", lang: lang)
        }

        lines.append("- **Siri / VIF**: \(siriSummary)")
        lines.append("- **TLS Anti-MitM**: \(mitmSummary)")
        lines.append("- **QUIC / PCC Relay**: \(quicSummary)")
        lines.append("")

        // 1. Exit Lanes
        lines.append(tr("## 1. 出口分流通道 (Exit Lanes)", "## 1. Exit Region Lanes", lang: lang))
        lines.append("")
        if report.exitLanes.isEmpty {
            lines.append(tr("_无出口探测数据。_", "_No exit lane results._", lang: lang))
        } else {
            lines.append(tr(
                "| 通道 | 状态 | 出口地区 | 脱敏 IP | 延迟 | 探测目标 | 结论 |",
                "| Lane | Status | Region | Masked IP | Latency | Host | Verdict |",
                lang: lang
            ))
            lines.append("| --- | --- | --- | --- | --- | --- | --- |")
            for lane in report.exitLanes {
                let statusIcon: String
                switch lane.verdictLevel {
                case .pass: statusIcon = "✅ PASS"
                case .warn: statusIcon = "⚠️ WARN"
                case .error: statusIcon = "❌ FAIL"
                }
                let region = RoutingProbeFormatter.formatRegionLabel(
                    countryCode: lane.countryCode,
                    coloCode: lane.coloCode,
                    lang: lang
                )
                let maskedIP = lane.ipAddress.isEmpty ? "—" : redactSensitiveText(RoutingProbeFormatter.maskIP(lane.ipAddress, revealFull: false))
                let latency = lane.reachable ? "\(lane.latencyMs) ms" : "—"
                let row = [
                    lane.title(lang: lang),
                    statusIcon,
                    region,
                    "`\(maskedIP)`",
                    latency,
                    "`\(lane.probedHost)`",
                    lane.verdict(lang: lang)
                ].map { escapeMarkdownCell(redactSensitiveText($0)) }
                lines.append("| \(row.joined(separator: " | ")) |")
            }
        }
        lines.append("")

        // 2. Siri & VIF Audit
        lines.append(tr("## 2. 中文 Siri 与代理/VIF 审计", "## 2. Siri & VIF Direct Audit", lang: lang))
        lines.append("")
        let siri = report.siriAudit
        let guzzoniIPs = formatRedactedIPList(siri.guzzoniResolvedIPs)
        let siriIPs = formatRedactedIPList(siri.siriResolvedIPs)
        lines.append("- **guzzoni.apple.com**: \(guzzoniIPs) (Fake-IP: `\(siri.isGuzzoniFakeIP)`)")
        lines.append("- **siri.apple.com**: \(siriIPs) (Fake-IP: `\(siri.isSiriFakeIP)`)")
        if let cname = siri.guzzoniCanonicalName, !cname.isEmpty {
            lines.append("- **guzzoni CNAME**: `\(redactSensitiveText(cname))`")
        }
        lines.append("- **\(tr("系统代理开启", "System Proxy Enabled", lang: lang))**: `\(siri.systemProxyEnabled)` · **\(tr("skip-proxy 包含 guzzoni", "Bypass Includes guzzoni", lang: lang))**: `\(siri.exceptionsIncludeGuzzoni)`")
        lines.append("- **\(tr("VIF 直连协同健康", "VIF Direct Healthy", lang: lang))**: `\(report.isSiriVIFDirectHealthy)`")
        lines.append("")

        // 3. QUIC UDP 443
        lines.append(tr("## 3. QUIC (UDP 443) 握手探测", "## 3. QUIC (UDP 443) Probes", lang: lang))
        lines.append("")
        if report.quicProbes.isEmpty {
            lines.append(tr("_无 QUIC 探测结果。_", "_No QUIC probe results._", lang: lang))
        } else {
            lines.append(tr(
                "| 节点 | 端口 | 状态 | 延迟 | 详情 |",
                "| Endpoint | Port | Status | Latency | Detail |",
                lang: lang
            ))
            lines.append("| --- | --- | --- | --- | --- |")
            for probe in report.quicProbes {
                let status = probe.succeeded ? "✅ OK" : "⚠️ FAIL"
                let latency = probe.succeeded ? "\(probe.latencyMs) ms" : "—"
                let row = [
                    "`\(probe.host)`",
                    "\(probe.port)",
                    status,
                    latency,
                    probe.detail(lang: lang)
                ].map { escapeMarkdownCell(redactSensitiveText($0)) }
                lines.append("| \(row.joined(separator: " | ")) |")
            }
        }
        lines.append("")

        // 4. TLS Endpoints
        lines.append(tr("## 4. TLS 证书链与防 MitM 探测", "## 4. TLS Endpoints & Anti-MitM Audit", lang: lang))
        lines.append("")
        if report.endpointProbes.isEmpty {
            lines.append(tr("_无 TLS 端点探测结果。_", "_No TLS endpoint probe results._", lang: lang))
        } else {
            lines.append(tr(
                "| 域名 | 用途 | 预期路由 | 状态 | 延迟 | 根证书 / 签发机构 | MitM 检测 | 说明 |",
                "| Host | Role | Route | HTTP | Latency | Root / Issuer | MitM | Detail |",
                lang: lang
            ))
            lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
            for ep in report.endpointProbes {
                let statusText = ep.httpStatus.map(String.init) ?? (ep.reachable ? "TLS OK" : "ERR")
                let latency = ep.reachable ? "\(ep.latencyMs) ms" : "—"
                let rootOrIssuer = ep.rootSubject ?? ep.issuerSummary ?? "—"
                let mitmText = ep.isMitMDetected ? "🚨 MitM" : "✅ Clean"
                let detail = ep.mitmReason ?? ep.errorDescription ?? (ep.reachable ? "OK" : "Unreachable")
                let row = [
                    "`\(ep.host)`",
                    ep.role(lang: lang),
                    ep.expectDirect ? "DIRECT" : "PROXY",
                    statusText,
                    latency,
                    rootOrIssuer,
                    mitmText,
                    detail
                ].map { escapeMarkdownCell(redactSensitiveText($0)) }
                lines.append("| \(row.joined(separator: " | ")) |")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Formats unified diagnostic findings and their raw log snippets into redacted Markdown.
    public static func formatDiagnosticsMarkdown(
        findings: [DiagnosticFinding],
        targetLabel: String,
        lang: AppLanguage
    ) -> String {
        var lines: [String] = []
        let redactedTarget = redactSensitiveText(targetLabel)
        let criticalCount = findings.filter { $0.severity == .critical }.count
        let warningCount = findings.filter { $0.severity == .warning }.count
        let infoCount = findings.filter { $0.severity == .info }.count

        lines.append(tr("# AppleLens 脱敏日志诊断单", "# AppleLens Redacted Diagnostics Report", lang: lang))
        lines.append("")
        lines.append("- **\(tr("目标设备", "Target", lang: lang))**: \(redactedTarget)")
        lines.append("- **\(tr("生成时间", "Generated", lang: lang))**: \(formatTimestamp(Date()))")
        lines.append("- **\(tr("检出摘要", "Summary", lang: lang))**: \(findings.count) (\(tr("严重", "Critical", lang: lang)): \(criticalCount), \(tr("注意", "Warning", lang: lang)): \(warningCount), \(tr("状态", "Status", lang: lang)): \(infoCount))")
        lines.append("")

        guard !findings.isEmpty else {
            lines.append(tr("_未检测到已知故障特征。_", "_No known diagnostic faults detected._", lang: lang))
            return lines.joined(separator: "\n")
        }

        for (index, finding) in findings.enumerated() {
            let title = redactSensitiveText(finding.title(lang: lang))
            let severityLabel = finding.severity.label(lang: lang)
            lines.append("## \(index + 1). [\(severityLabel)] \(title)")
            lines.append("")
            lines.append("- **\(tr("诊断代码", "Code", lang: lang))**: `\(finding.code.rawValue)`")
            lines.append("- **\(tr("来源与进程", "Source / Process", lang: lang))**: \(redactSensitiveText(finding.sourceDevice)) · `\(redactSensitiveText(finding.processName))`")
            lines.append("- **\(tr("日志时间", "Timestamp", lang: lang))**: \(formatTimestamp(finding.timestamp))")
            if let fraction = finding.progressFraction {
                lines.append("- **\(tr("下载进度", "Progress", lang: lang))**: \(String(format: "%.1f%%", fraction * 100.0))")
            }
            lines.append("")
            lines.append("**\(tr("原因解析", "Diagnosis", lang: lang))**: \(redactSensitiveText(finding.explanation(lang: lang)))")
            lines.append("")
            lines.append("**\(tr("修复建议", "Remediation", lang: lang))**:")
            lines.append(redactSensitiveText(finding.remediation(lang: lang)))
            lines.append("")
            lines.append("**\(tr("脱敏原始日志", "Redacted Log Snippet", lang: lang))**:")
            lines.append("````text")
            lines.append(redactSensitiveText(finding.rawLine).replacingOccurrences(of: "````", with: "` ` ` `"))
            lines.append("````")
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func formatRedactedIPList(_ ips: [String]) -> String {
        guard !ips.isEmpty else { return "—" }
        return ips.map { "`\(redactSensitiveText($0))`" }.joined(separator: ", ")
    }

    private static func escapeMarkdownCell(_ cell: String) -> String {
        cell
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func replaceMatches(
        of regex: NSRegularExpression?,
        in text: String,
        transform: (String) -> String
    ) -> String {
        guard let regex else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let matched = nsText.substring(with: match.range)
            let replacement = transform(matched)
            mutable.replaceCharacters(in: match.range, with: replacement)
        }
        return String(mutable)
    }
}
