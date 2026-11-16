import AppleLensCore
import Darwin
import Foundation

@main
struct AppleLensCLI {
    private static let cliVersion = "1.2.0"

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        let rest = Array(args.dropFirst())

        if command == "--help" || command == "-h" || command == "help" {
            printUsage()
            return
        }

        if command == "--version" || command == "-v" {
            print("AppleLens \(cliVersion)")
            return
        }

        switch command {
        case "radar":
            await runRadar(args: rest)
        case "probe":
            await runProbe(args: rest)
        case "report":
            runReport(args: rest)
        case "diagnose":
            await runDiagnose(args: rest)
        default:
            printError("未知子命令 / Unknown command: '\(command)'")
            printUsage()
            Darwin.exit(1)
        }
    }

    // MARK: - Subcommand: radar

    @MainActor
    private static func runRadar(args: [String]) async {
        var jsonOutput = false
        for arg in args {
            switch arg {
            case "--once":
                break
            case "--json":
                jsonOutput = true
            case "--help", "-h":
                printUsage()
                return
            default:
                printError("radar 不支持的参数 / Unsupported radar flag: '\(arg)'")
                printUsage()
                Darwin.exit(1)
            }
        }

        let coordinator = TriStateRadarCoordinator()
        let logService = UnifiedLogStreamService()

        let dnsMapper = coordinator.dnsMapper
        await dnsMapper.refreshMappings()
        let recentEvents = await logService.scanRecentHistory(minutes: 2)
        let signalEvents = recentEvents.filter { $0.isOnDeviceInferenceSignal || $0.isPCCSignal }
        for event in signalEvents.suffix(40) {
            coordinator.ingestUnifiedLogEvent(event)
        }

        let snapshot = await coordinator.performSingleScan()

        let state = coordinator.overallState
        let isOnDevice = coordinator.isOnDeviceActive
        let isPCC = coordinator.isPCCActive
        let onDeviceDetail = coordinator.lastOnDeviceDetail
        let pccDetail = coordinator.lastPCCDetail
        let connections = snapshot.activeLLMConnections
        let timeline = coordinator.recentTimeline

        if jsonOutput {
            let payload = RadarJSONOutput(
                scannedAt: snapshot.scannedAt,
                overallState: state.rawValue,
                overallLabelZh: state.label(lang: .zhHans),
                overallLabelEn: state.label(lang: .en),
                isOnDeviceActive: isOnDevice,
                isPCCActive: isPCC,
                lastOnDeviceDetail: onDeviceDetail,
                lastPCCDetail: pccDetail,
                pccSocketCount: snapshot.pccSocketCount,
                mappedDomainsCount: snapshot.mappedDomainsCount,
                activeProxyPorts: snapshot.activeProxyPorts,
                recentLogEventsScanned: recentEvents.count,
                recentSignalEventsMatched: signalEvents.count,
                activeLLMConnections: connections.map { conn in
                    RadarConnectionJSON(
                        pid: conn.pid,
                        appName: conn.appName,
                        executableName: conn.executableName,
                        bundleID: conn.bundleID,
                        appBundlePath: conn.appBundlePath,
                        identityKey: conn.identityKey,
                        providerId: conn.provider.id,
                        providerNameZh: conn.provider.nameZh,
                        providerNameEn: conn.provider.nameEn,
                        category: conn.provider.category.rawValue,
                        matchedDomain: conn.matchedDomain,
                        remoteIP: conn.remoteIP,
                        confidence: conn.confidence.rawValue,
                        isFakeIP: conn.isFakeIP,
                        isTrusted: conn.isTrusted,
                        firstSeenAt: conn.firstSeenAt
                    )
                },
                recentTimeline: timeline
            )
            emitJSON(payload)
            return
        }

        printSectionHeader("AppleLens Tri-State Radar / 三态雷达扫描")
        print("Timestamp / 时间        : \(formatDate(snapshot.scannedAt))")
        print("Tri-State / 当前状态    : \(stateIcon(state)) \(state.label(lang: .zhHans)) | \(state.label(lang: .en)) [\(state.rawValue)]")
        print("On-Device ANE / 端侧推理: \(isOnDevice ? "ACTIVE / 活跃" : "IDLE / 静默")\(onDeviceDetail.isEmpty ? "" : " — \(onDeviceDetail)")")
        print("Apple PCC / 苹果私有云  : \(isPCC ? "ACTIVE / 活跃" : "IDLE / 静默") (sockets: \(snapshot.pccSocketCount))\(pccDetail.isEmpty ? "" : " — \(pccDetail)")")
        print("Unified Logs (2m) / 日志: scanned \(recentEvents.count) events, matched \(signalEvents.count) AI/PCC signal(s)")
        print("Mapped IPs / 域名映射表 : \(snapshot.mappedDomainsCount) IP record(s)")
        let portsText = snapshot.activeProxyPorts.isEmpty
            ? "none / 无"
            : snapshot.activeProxyPorts.map(String.init).joined(separator: ", ")
        print("Proxy Ports / 本地代理口: \(portsText)")

        print("")
        print("External LLM Processes / 外部大模型外连进程 (\(connections.count)):")
        if connections.isEmpty {
            print("  (none detected / 当前未检测到第三方大模型外连)")
        } else {
            for (idx, conn) in connections.enumerated() {
                let ipKind = conn.isFakeIP ? "Fake-IP" : "Real-IP"
                let trustLabel = conn.isTrusted ? "Trusted / 已信任" : "First-Seen / 首次发现"
                print("  [\(idx + 1)] \(conn.appName) (exec: \(conn.executableName), pid: \(conn.pid))")
                if let bundleID = conn.bundleID {
                    print("      Bundle ID  : \(bundleID)")
                }
                print("      Provider   : \(conn.provider.nameZh) / \(conn.provider.nameEn) [\(conn.provider.category.label(lang: .en))]")
                print("      Endpoint   : \(conn.matchedDomain) -> \(conn.remoteIP) (\(ipKind), \(conn.confidence.label(lang: .en)))")
                print("      Trust      : \(trustLabel)")
            }
        }

        if !timeline.isEmpty {
            print("")
            print("Recent Signals / 最近信号时间线:")
            for entry in timeline.prefix(10) {
                print("  \(entry)")
            }
        }
    }

    // MARK: - Subcommand: probe

    private static func runProbe(args: [String]) async {
        var jsonOutput = false
        var markdownOutput = false
        var rawProxyArg: String?

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--json":
                jsonOutput = true
            case "--markdown":
                markdownOutput = true
            case "--proxy":
                index += 1
                guard index < args.count else {
                    printError("缺少 --proxy 参数值 / Missing value for --proxy (expected host:port, http://..., or socks5://...)")
                    printUsage()
                    Darwin.exit(1)
                }
                let value = args[index]
                guard !value.hasPrefix("-") else {
                    printError("无效的 --proxy 参数值 / Invalid value for --proxy: '\(value)'")
                    printUsage()
                    Darwin.exit(1)
                }
                rawProxyArg = value
            case let flag where flag.hasPrefix("--proxy="):
                rawProxyArg = String(flag.dropFirst("--proxy=".count))
            case "--help", "-h":
                printUsage()
                return
            default:
                printError("probe 不支持的参数 / Unsupported probe flag: '\(arg)'")
                printUsage()
                Darwin.exit(1)
            }
            index += 1
        }

        if jsonOutput && markdownOutput {
            printError("请勿同时指定 --json 与 --markdown / Cannot combine --json and --markdown")
            Darwin.exit(1)
        }

        var customProxy: CustomProxyConfig?
        if let rawProxyArg {
            guard let parsed = CustomProxyConfig.parse(rawProxyArg) else {
                printError("无效的代理地址 / Invalid proxy address '\(rawProxyArg)'. Expected host:port, http://host:port, or socks5://host:port")
                Darwin.exit(1)
            }
            customProxy = parsed
        }

        let engine = RoutingProbeEngine()
        let report = await engine.runFullProbe(customProxy: customProxy)

        if jsonOutput {
            let payload = ProbeJSONOutput(
                ranAt: report.ranAt,
                customProxy: customProxy?.displayString,
                mitmDetectedCount: report.mitmDetectedCount,
                quicAllPassed: report.quicAllPassed,
                exitLanes: report.exitLanes,
                siriAudit: report.siriAudit,
                quicProbes: report.quicProbes,
                endpointProbes: report.endpointProbes
            )
            emitJSON(payload)
            return
        }

        if markdownOutput {
            let markdown = DiagnosticReportFormatter.formatProbeMarkdown(
                report,
                customProxySummary: customProxy?.displayString,
                lang: LanguageManager.shared.current
            )
            print(markdown)
            return
        }

        printSectionHeader("AppleLens Routing & Anti-MitM Probe / 路由与防中间人预检探针")
        print("Timestamp / 时间: \(formatDate(report.ranAt))")
        if let customProxy {
            print("Custom Proxy / 自定义代理: \(customProxy.displayString)")
        }

        print("")
        print("1. Exit Lanes / 出口分流通道 (\(report.exitLanes.count)):")
        for lane in report.exitLanes {
            let badge = verdictBadge(lane.verdictLevel)
            if lane.reachable {
                let regionEn = RoutingProbeFormatter.formatRegionLabel(
                    countryCode: lane.countryCode,
                    coloCode: lane.coloCode,
                    lang: .en
                )
                print("  \(badge) \(lane.titleZh) | \(lane.titleEn)")
                print("      Region : \(regionEn) | IP: \(lane.ipAddress.isEmpty ? "—" : lane.ipAddress) | \(lane.latencyMs) ms | Host: \(lane.probedHost)")
                print("      Verdict: \(lane.verdictZh) / \(lane.verdictEn)")
            } else {
                print("  \(badge) \(lane.titleZh) | \(lane.titleEn)")
                print("      Status : Unreachable (\(lane.probedHost))")
                print("      Verdict: \(lane.verdictZh) / \(lane.verdictEn)")
            }
        }

        print("")
        print("2. Siri Real-IP & System Proxy Audit / 中文 Siri 真实 IP 与系统代理审计:")
        let siri = report.siriAudit
        let siriStatusText: String = {
            if report.isSiriVIFDirectHealthy {
                return "[PASS] Healthy via Surge VIF DIRECT / VIF 规则直连健康"
            }
            return report.isSiriEffectivelyHealthy
                ? "[PASS] Healthy / 正常"
                : "[WARN] Risk Detected / 存在被代理或 Fake-IP 风险"
        }()
        print("  Health / 健康状态       : \(siriStatusText)")
        print("  guzzoni.apple.com IPs   : \(siri.guzzoniResolvedIPs.isEmpty ? "unresolved" : siri.guzzoniResolvedIPs.joined(separator: ", ")) (Fake-IP: \(siri.isGuzzoniFakeIP ? "YES" : "NO"))")
        print("  siri.apple.com IPs      : \(siri.siriResolvedIPs.isEmpty ? "unresolved" : siri.siriResolvedIPs.joined(separator: ", ")) (Fake-IP: \(siri.isSiriFakeIP ? "YES" : "NO"))")
        print("  System Proxy / 系统代理 : \(siri.systemProxyEnabled ? "Enabled / 已开启" : "Disabled / 未开启")")
        print("  Proxy Exceptions / 绕过 : guzzoni included = \(siri.exceptionsIncludeGuzzoni ? "YES" : "NO")")

        print("")
        let quicSummary = report.quicAllPassed
            ? "ALL PASS"
            : (report.isQUICUsingTCPFallback ? "TCP H2 FALLBACK HEALTHY" : "CHECK NEEDED")
        print("3. QUIC UDP 443 (HTTP/3) Probes / OHTTP QUIC 通道探测 (\(quicSummary)):")
        for quic in report.quicProbes {
            let badge = quic.succeeded ? "[PASS]" : (report.isQUICUsingTCPFallback ? "[TCP-FB]" : "[FAIL]")
            print("  \(badge) \(quic.host):\(quic.port) (\(quic.latencyMs) ms)")
            print("      \(quic.detailZh) | \(quic.detailEn)")
        }

        print("")
        print("4. Endpoint TLS & Anti-MitM Inspection / 端点 TLS 证书链与防 MitM 检测 (MitM hits: \(report.mitmDetectedCount)):")
        for ep in report.endpointProbes {
            let badge: String
            if ep.isMitMDetected {
                badge = "[MITM!]"
            } else if ep.reachable {
                badge = "[OK]"
            } else {
                badge = "[ERR]"
            }
            let statusStr = ep.httpStatus.map { "HTTP \($0)" } ?? (ep.errorDescription ?? "Unreachable")
            print("  \(badge) \(ep.host) — \(statusStr), \(ep.latencyMs) ms (expectDirect=\(ep.expectDirect), pinningSensitive=\(ep.pinningSensitive))")
            print("      Role  : \(ep.roleZh) | \(ep.roleEn)")
            if let leaf = ep.leafSubject {
                print("      Leaf  : \(leaf)")
            }
            if let issuer = ep.issuerSummary {
                print("      Issuer: \(issuer)")
            }
            if let root = ep.rootSubject {
                print("      Root  : \(root)")
            }
            if ep.isMitMDetected {
                print("      ALERT : \(ep.mitmReason ?? "Unexpected TLS MitM CA detected")")
            }
        }
    }

    // MARK: - Subcommand: report

    private static func runReport(args: [String]) {
        var useDemo = false
        var jsonOutput = false
        var filePath: String?

        for arg in args {
            switch arg {
            case "--demo":
                useDemo = true
            case "--json":
                jsonOutput = true
            case "--help", "-h":
                printUsage()
                return
            default:
                if arg.hasPrefix("-") {
                    printError("report 不支持的参数 / Unsupported report flag: '\(arg)'")
                    printUsage()
                    Darwin.exit(1)
                } else if filePath == nil {
                    filePath = arg
                } else {
                    printError("多余的文件参数 / Unexpected extra argument: '\(arg)'")
                    printUsage()
                    Darwin.exit(1)
                }
            }
        }

        if useDemo && filePath != nil {
            printError("请勿同时指定文件路径和 --demo / Cannot specify both <path> and --demo")
            Darwin.exit(1)
        }
        if !useDemo && filePath == nil {
            printError("请提供报告 JSON 路径或使用 --demo / Provide <path> to Apple_Intelligence_Report.json or pass --demo")
            printUsage()
            Darwin.exit(1)
        }

        let report: ParsedAppleIntelligenceReport
        do {
            if useDemo {
                let data = SampleReportFixture.sampleReportJSONData()
                report = try IntelligenceReportDecoder.decode(
                    data: data,
                    fileName: "Sample_Apple_Intelligence_Report.json"
                )
            } else if let rawPath = filePath {
                let expanded = (rawPath as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                let data = try Data(contentsOf: url)
                report = try IntelligenceReportDecoder.decode(data: data, fileName: url.lastPathComponent)
            } else {
                Darwin.exit(1)
            }
        } catch {
            printError("解码报告失败 / Failed to decode Apple Intelligence report: \(error.localizedDescription)")
            Darwin.exit(1)
        }

        if jsonOutput {
            let payload = ReportJSONOutput(
                sourceFileName: report.sourceFileName,
                parsedAt: report.parsedAt,
                pccRequestCount: report.pccRequestCount,
                onDeviceRequestCount: report.onDeviceRequestCount,
                attestationCount: report.attestationCount,
                topLevelKeys: report.topLevelKeys,
                requests: report.requests,
                assets: report.assets
            )
            emitJSON(payload)
            return
        }

        printSectionHeader("AppleLens Report Lens / Apple 智能透明报告解析")
        print("Source / 文件名      : \(report.sourceFileName)")
        print("Requests / 请求数    : \(report.requests.count) (PCC: \(report.pccRequestCount), On-Device: \(report.onDeviceRequestCount))")
        print("Attestations / 证明  : \(report.attestationCount)")
        print("Assets / 模型资产    : \(report.assets.count)")
        print("Top Keys / 顶层键    : \(report.topLevelKeys.joined(separator: ", "))")

        if !report.assets.isEmpty {
            print("")
            print("Model Assets / 模型资产:")
            for asset in report.assets {
                print("  - \(asset.assetID) (version: \(asset.version ?? "—"), status: \(asset.status ?? "—"))")
            }
        }

        for (reqIdx, req) in report.requests.enumerated() {
            print("")
            print("── Request [\(reqIdx + 1)/\(report.requests.count)] \(req.id) ──")
            print("  UseCase / 场景 : \(req.useCase)")
            print("  Target / 载体  : \(req.executionTarget.label(lang: .zhHans)) | \(req.executionTarget.label(lang: .en))")
            print("  Model / 模型   : \(req.modelIdentifier ?? "—")")
            print("  Time / 时间    : \(req.timestamp.map(formatDate) ?? "—")")

            print("  Prompt Blocks (<ctrl99>) / 提示词切片 (\(req.promptBlocks.count)):")
            for block in req.promptBlocks {
                let budgetTag = block.silentTokenBudget.map { " [SilentTokenBudget: \($0)]" } ?? ""
                print("    • <ctrl99>\(block.role.rawValue) (\(block.role.label(lang: .en)))\(budgetTag)")
                print(indented(block.content, prefix: "      "))
            }

            if !req.toolCalls.isEmpty {
                print("  Tool Calls / 工具调用 (\(req.toolCalls.count)):")
                for tool in req.toolCalls {
                    print("    • \(tool.name)")
                    print("      args  : \(singleLineOrIndented(tool.argumentsJSON, indent: "      "))")
                    if let res = tool.resultPreview {
                        print("      result: \(singleLineOrIndented(res, indent: "      "))")
                    }
                }
            }

            if let responseText = req.responseText, !responseText.isEmpty {
                print("  Response / 模型响应:")
                print(indented(responseText, prefix: "    "))
            }

            if !req.pccRequests.isEmpty {
                print("  PCC Sub-Requests & CloudAttestation (\(req.pccRequests.count)):")
                for pcc in req.pccRequests {
                    let bytesStr = pcc.payloadBytes.map { "\($0) bytes" } ?? "—"
                    print("    • SubRequest \(pcc.id) | endpoint: \(pcc.endpoint ?? "—") | state: \(pcc.requestState ?? "—") | payload: \(bytesStr)")
                    if let att = pcc.attestation {
                        print("      Node Role        : \(att.nodeRoleLabelZh) / \(att.nodeRoleLabelEn)")
                        print("      Bundle Bytes     : \(att.rawBundleByteCount) bytes")
                        print("      SEP Attestation  : \(att.sepAttestationBytes) bytes (SHA-256: \(att.sepAttestationSHA256 ?? "—"))")
                        print("      AP Ticket (IM4M) : \(att.apTicketBytes) bytes, IM4M magic=\(att.apTicketHasIM4MMagic ? "YES" : "NO") (SHA-256: \(att.apTicketSHA256 ?? "—"))")
                        print("      AppData          : domain=\(att.appDataDomain ?? "—"), name=\(att.appDataName ?? "—"), version=\(att.appDataVersion.map(String.init) ?? "—")")
                        print("      Key Expiration   : \(att.keyExpiration.map(formatDate) ?? "—")")
                        print("      Transparency     : hasProof=\(att.hasTransparencyProof), \(att.transparencyProofBytes) bytes (SHA-256: \(att.transparencyProofSHA256 ?? "—"))")

                        print("      X.509 Certificate Chain (\(att.certificateChain.count)):")
                        for cert in att.certificateChain {
                            print("        [\(cert.indexInChain)] Subject: \(cert.subjectSummary) (CN=\(cert.commonName), Org=\(cert.organization.isEmpty ? "—" : cert.organization))")
                            print("            Issuer : \(cert.issuerSummary) | Alg: \(cert.publicKeyAlgorithm) | AppleAnchored: \(cert.isAppleAnchored)")
                            print("            Valid  : \(cert.notBefore.map(formatDate) ?? "—") -> \(cert.notAfter.map(formatDate) ?? "—") (currentlyValid=\(cert.isCurrentlyValid))")
                            print("            SHA-256: \(cert.sha256Fingerprint)")
                        }

                        print("      SealedHashLedger Slots (\(att.sealedHashSlots.count)):")
                        for slot in att.sealedHashSlots {
                            print("        * Slot '\(slot.slotName)' [\(slot.hashAlgorithm)] entries=\(slot.entryCount), cryptexManifests=\(slot.cryptexManifestCount)")
                            for digest in slot.entryDigestsHex {
                                print("          Digest: \(digest)")
                            }
                            for (scIdx, scJSON) in slot.secureConfigsJSON.enumerated() {
                                print("          SecureConfig #\(scIdx + 1):")
                                print(indented(scJSON, prefix: "            "))
                            }
                        }

                        if !att.parseNotes.isEmpty {
                            print("      Notes            : \(att.parseNotes.joined(separator: "; "))")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subcommand: diagnose

    private static func runDiagnose(args: [String]) async {
        var useDemo = false
        var explicitLast15m = false
        var jsonOutput = false

        for arg in args {
            switch arg {
            case "--demo":
                useDemo = true
            case "--last-15m":
                explicitLast15m = true
            case "--json":
                jsonOutput = true
            case "--help", "-h":
                printUsage()
                return
            default:
                printError("diagnose 不支持的参数 / Unsupported diagnose flag: '\(arg)'")
                printUsage()
                Darwin.exit(1)
            }
        }

        if useDemo && explicitLast15m {
            printError("请勿同时指定 --last-15m 与 --demo / Cannot combine --last-15m and --demo")
            Darwin.exit(1)
        }

        let mode: String
        let scannedCount: Int
        let findings: [DiagnosticFinding]

        if useDemo {
            mode = "demo"
            scannedCount = DiagnosticTranslator.sampleFaultLogLines.count
            findings = DiagnosticTranslator.sampleFaultLogLines.compactMap { sample in
                DiagnosticTranslator.translate(
                    line: sample.message,
                    process: sample.process,
                    subsystem: sample.subsystem,
                    sourceDevice: "Demo Fault Fixture"
                )
            }
        } else {
            mode = "last-15m"
            let logService = UnifiedLogStreamService()
            let events = await logService.scanRecentHistory(minutes: 15)
            scannedCount = events.count
            findings = events.compactMap { DiagnosticTranslator.translate(event: $0) }
        }

        if jsonOutput {
            let payload = DiagnoseJSONOutput(
                mode: mode,
                scannedEventsCount: scannedCount,
                findingsCount: findings.count,
                findings: findings
            )
            emitJSON(payload)
            return
        }

        printSectionHeader("AppleLens Unified Log Diagnostics / 系统日志排障翻译器")
        print("Mode / 模式    : \(useDemo ? "Demo Sample Faults (--demo)" : "Live macOS Unified Log (--last-15m)")")
        print("Scanned / 扫描 : \(scannedCount) event(s)")
        print("Findings / 命中: \(findings.count) diagnostic finding(s)")

        if findings.isEmpty {
            print("")
            print("未检测到已知 AI / PCC 错误模式。")
            print("No known Apple Intelligence / PCC fault patterns detected in the last 15 minutes.")
            print("Tip: run `applelens diagnose --demo` to inspect all built-in fault translations.")
            return
        }

        for (idx, finding) in findings.enumerated() {
            print("")
            print("[\(idx + 1)] [\(finding.severity.label(lang: .en)) / \(finding.severity.label(lang: .zhHans))] \(finding.code.rawValue)")
            print("    Process / 进程 : \(finding.processName) (\(finding.sourceDevice)) @ \(formatDate(finding.timestamp))")
            print("    Title (ZH)     : \(finding.titleZh)")
            print("    Title (EN)     : \(finding.titleEn)")
            print("    Explain (ZH)   : \(finding.explanationZh)")
            print("    Explain (EN)   : \(finding.explanationEn)")
            print("    Fix (ZH)       : \(singleLineOrIndented(finding.remediationZh, indent: "                     "))")
            print("    Fix (EN)       : \(singleLineOrIndented(finding.remediationEn, indent: "                     "))")
            if let progress = finding.progressFraction {
                let pct = String(format: "%.1f%%", progress * 100.0)
                print("    Progress / 进度: \(pct)")
            }
            if let url = finding.actionURL {
                let label = finding.actionLabelEn ?? url
                print("    Action / 参考  : \(label) -> \(url)")
            }
            if let snippet = finding.copyableSnippet {
                print("    Rule Snippet   :")
                print(indented(snippet, prefix: "      "))
            }
            print("    Raw Log        : \(finding.rawLine)")
        }
    }

    // MARK: - Usage & Formatting Helpers

    private static func printUsage() {
        let usage = """
        AppleLens CLI (v\(cliVersion)) — Zero-MitM Read-Only Diagnostics for Apple Intelligence & macOS LLM Traffic
        AppleLens 命令行工具 — 零 MitM 纯只读 Apple 智能与桌面大模型流量诊断套件

        USAGE / 用法:
          applelens <subcommand> [options]

        SUBCOMMANDS / 子命令:
          radar [--once] [--json]
              Refresh DNSFakeIPMapper, run TriStateRadarCoordinator + 2m Unified Log ingestion,
              and print tri-state status, mapped IP count, proxy ports, and active LLM processes.
              刷新域名/Fake-IP 映射表，执行三态雷达扫描与近 2 分钟系统日志融合，输出活跃 AI 进程。

          probe [--proxy <host:port>] [--markdown] [--json]
              Run RoutingProbeEngine (4 Exit Lanes, Siri Real-IP DNS audit, QUIC UDP 443, and TLS Anti-MitM).
              Supports optional --proxy (host:port / http://... / socks5://...) and --markdown redacted export.
              运行网络分流与防中间人预检探针（4 条出口通道、Siri 真实 IP 审计、QUIC UDP 443、TLS 证书链）。
              支持通过 --proxy 指定 HTTP/SOCKS5 代理端口测试，以及 --markdown 输出脱敏 Markdown 报告。

          report [<path> | --demo] [--json]
              Decode an Apple_Intelligence_Report.json file or built-in demo fixture (<ctrl99> blocks,
              silentTokenBudget, toolCalls, CloudAttestation X.509 chain, and SealedHashLedger JSON).
              解析 Apple 智能透明报告 JSON 或内置演示样本（提示词切片、工具调用、X.509 证书链与哈希账本）。

          diagnose [--last-15m | --demo] [--json]
              Scan last 15m macOS Unified Logs (default) or built-in sample faults and print bilingual findings.
              扫描近 15 分钟 macOS 统一日志（默认）或演示故障样本，输出中英双语排障结论与修复建议。

          --version, -v
              Show CLI version (AppleLens \(cliVersion)). / 显示当前 CLI 版本信息。

          --help, -h
              Show this bilingual usage guide. / 显示本双语帮助信息。

        EXAMPLES / 示例:
          applelens --version
          applelens radar --once
          applelens probe --json
          applelens probe --proxy 127.0.0.1:6152 --markdown
          applelens report --demo
          applelens report ~/Desktop/Apple_Intelligence_Report.json
          applelens diagnose --demo
          applelens diagnose --last-15m

        Kianuni Trilogy:
          AppleFlow (Rules): \(DiagnosticTranslator.appleFlowURL)
          Erosion-CN (Unlock): \(DiagnosticTranslator.erosionURL)
        """
        print(usage)
    }

    private static func printSectionHeader(_ title: String) {
        print("================================================================================")
        print(title)
        print("================================================================================")
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data(("Error: \(message)\n").utf8))
    }

    private static func emitJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {
            printError("JSON 编码失败 / Failed to encode JSON: \(error.localizedDescription)")
            Darwin.exit(1)
        }
    }

    private static func stateIcon(_ state: RadarOverallState) -> String {
        switch state {
        case .idle: return "⚪"
        case .onDevice: return "🟢"
        case .applePCC: return "🔵"
        case .externalLLM: return "🟠"
        case .hybrid: return "🟣"
        }
    }

    private static func verdictBadge(_ level: ProbeVerdictLevel) -> String {
        switch level {
        case .pass: return "[PASS]"
        case .warn: return "[WARN]"
        case .error: return "[FAIL]"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func indented(_ text: String, prefix: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(prefix)\($0)" }
            .joined(separator: "\n")
    }

    private static func singleLineOrIndented(_ text: String, indent: String) -> String {
        if !text.contains("\n") { return text }
        return "\n" + indented(text, prefix: indent)
    }
}

// MARK: - JSON Output Models

private struct RadarConnectionJSON: Encodable, Sendable {
    let pid: Int32
    let appName: String
    let executableName: String
    let bundleID: String?
    let appBundlePath: String?
    let identityKey: String
    let providerId: String
    let providerNameZh: String
    let providerNameEn: String
    let category: String
    let matchedDomain: String
    let remoteIP: String
    let confidence: String
    let isFakeIP: Bool
    let isTrusted: Bool
    let firstSeenAt: Date
}

private struct RadarJSONOutput: Encodable, Sendable {
    let scannedAt: Date
    let overallState: String
    let overallLabelZh: String
    let overallLabelEn: String
    let isOnDeviceActive: Bool
    let isPCCActive: Bool
    let lastOnDeviceDetail: String
    let lastPCCDetail: String
    let pccSocketCount: Int
    let mappedDomainsCount: Int
    let activeProxyPorts: [UInt16]
    let recentLogEventsScanned: Int
    let recentSignalEventsMatched: Int
    let activeLLMConnections: [RadarConnectionJSON]
    let recentTimeline: [String]
}

private struct ProbeJSONOutput: Encodable, Sendable {
    let ranAt: Date
    let customProxy: String?
    let mitmDetectedCount: Int
    let quicAllPassed: Bool
    let exitLanes: [ExitRegionLaneResult]
    let siriAudit: SiriDNSAuditResult
    let quicProbes: [QUICProbeResult]
    let endpointProbes: [EndpointTLSProbeResult]
}

private struct ReportJSONOutput: Encodable, Sendable {
    let sourceFileName: String
    let parsedAt: Date
    let pccRequestCount: Int
    let onDeviceRequestCount: Int
    let attestationCount: Int
    let topLevelKeys: [String]
    let requests: [ParsedModelRequestItem]
    let assets: [ParsedModelAssetItem]
}

private struct DiagnoseJSONOutput: Encodable, Sendable {
    let mode: String
    let scannedEventsCount: Int
    let findingsCount: Int
    let findings: [DiagnosticFinding]
}
