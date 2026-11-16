@testable import AppleLensCore
import Foundation
import XCTest

final class QualityHardeningTests: XCTestCase {
    // MARK: - RoutingProbeEngine & RoutingProbeFormatter

    func testParseCloudflareTraceParsesFieldsTrimsWhitespaceAndIgnoresMalformedLines() {
        let traceBody = """
        fl=29f123
        h=chatgpt.com
        ip=38.175.211.5
        ts=1731750000.123
        visit_scheme=https
        uag=Mozilla/5.0 (Macintosh; foo=bar)
        colo = LAX 

        line_without_equals
        =empty_key_ignored
        loc=US
        tls=TLSv1.3
        """

        let parsed = RoutingProbeEngine.parseCloudflareTrace(traceBody)
        XCTAssertEqual(parsed["fl"], "29f123")
        XCTAssertEqual(parsed["h"], "chatgpt.com")
        XCTAssertEqual(parsed["ip"], "38.175.211.5")
        XCTAssertEqual(parsed["uag"], "Mozilla/5.0 (Macintosh; foo=bar)")
        XCTAssertEqual(parsed["colo"], "LAX")
        XCTAssertEqual(parsed["loc"], "US")
        XCTAssertEqual(parsed["tls"], "TLSv1.3")
        XCTAssertNil(parsed["line_without_equals"])
        XCTAssertNil(parsed[""])

        XCTAssertTrue(RoutingProbeEngine.parseCloudflareTrace("").isEmpty)
    }

    func testTLSProbeTargetHostsHasNineCanonicalEndpoints() {
        let hosts = RoutingProbeEngine.tlsProbeTargetHosts
        XCTAssertEqual(hosts.count, 9)
        XCTAssertEqual(Set(hosts).count, 9)
        XCTAssertTrue(hosts.contains("inference.issuer.apple.com"))
        XCTAssertEqual(
            hosts,
            [
                "guzzoni.apple.com",
                "gspe1-ssl.ls.apple.com",
                "api.smoot.apple.com",
                "inference.issuer.apple.com",
                "mask-api.icloud.com",
                "ropes.apple.com",
                "apple-relay.cloudflare.com",
                "apple-relay.fastly-edge.com",
                "lens.google.com"
            ]
        )
    }

    func testRoutingProbeFormatterFormatRegionLabel() {
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "us", coloCode: "lax", lang: .en),
            "🇺🇸 United States · Los Angeles (LAX)"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "cn", coloCode: "sha", lang: .zhHans),
            "🇨🇳 中国大陆 · 上海 (SHA)"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "JP", coloCode: "XYZ", lang: .en),
            "🇯🇵 Japan (XYZ)"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "CN", coloCode: "", lang: .zhHans),
            "🇨🇳 中国大陆"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "br", coloCode: "gru", lang: .en),
            "🇧🇷 BR (GRU)"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "", coloCode: "LAX", lang: .zhHans),
            "未知区域"
        )
        XCTAssertEqual(
            RoutingProbeFormatter.formatRegionLabel(countryCode: "", coloCode: "LAX", lang: .en),
            "Unknown Region"
        )
    }

    func testRoutingProbeFormatterMaskIP() {
        XCTAssertEqual(RoutingProbeFormatter.maskIP("111.34.209.220", revealFull: false), "111.34.*.*")
        XCTAssertEqual(RoutingProbeFormatter.maskIP("111.34.209.220", revealFull: true), "111.34.209.220")

        XCTAssertEqual(RoutingProbeFormatter.maskIP("2606:4700:4700::1111", revealFull: false), "2606:4700:*:*")
        XCTAssertEqual(RoutingProbeFormatter.maskIP("2606:4700:4700::1111", revealFull: true), "2606:4700:4700::1111")

        XCTAssertEqual(RoutingProbeFormatter.maskIP("", revealFull: false), "—")
        XCTAssertEqual(RoutingProbeFormatter.maskIP("", revealFull: true), "—")
        XCTAssertEqual(RoutingProbeFormatter.maskIP("localhost", revealFull: false), "localhost")
    }

    // MARK: - UnifiedLogStreamService NDJSON & Timestamp Parsing

    func testUnifiedLogTimestampParserHandlesOffsetsFractionalSecondsAndUTC() throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        // Positive offset (+0800): 14:20:05.123456+0800 == 06:20:05.123456 UTC
        let plus8 = try XCTUnwrap(UnifiedLogStreamService.parseLogTimestamp("2026-11-16 14:20:05.123456+0800"))
        let c1 = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: plus8)
        XCTAssertEqual(c1.year, 2026)
        XCTAssertEqual(c1.month, 11)
        XCTAssertEqual(c1.day, 16)
        XCTAssertEqual(c1.hour, 6)
        XCTAssertEqual(c1.minute, 20)
        XCTAssertEqual(c1.second, 5)
        XCTAssertEqual(Double(try XCTUnwrap(c1.nanosecond)) / 1_000_000_000.0, 0.123456, accuracy: 0.001)

        // Negative offset (-0500): 23:10:00.500000-0500 on Nov 16 == 04:10:00.500000 UTC on Nov 17
        let minus5 = try XCTUnwrap(UnifiedLogStreamService.parseLogTimestamp("2026-11-16 23:10:00.500000-0500"))
        let c2 = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: minus5)
        XCTAssertEqual(c2.year, 2026)
        XCTAssertEqual(c2.month, 11)
        XCTAssertEqual(c2.day, 17)
        XCTAssertEqual(c2.hour, 4)
        XCTAssertEqual(c2.minute, 10)
        XCTAssertEqual(c2.second, 0)

        // Trailing Z UTC
        let utcZ = try XCTUnwrap(UnifiedLogStreamService.parseLogTimestamp("2026-11-16 06:20:05.123456Z"))
        XCTAssertEqual(utcZ.timeIntervalSince1970, plus8.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertNil(UnifiedLogStreamService.parseLogTimestamp(""))
        XCTAssertNil(UnifiedLogStreamService.parseLogTimestamp("not-a-timestamp"))
    }

    func testUnifiedLogStreamParseSingleNDJSONLineAndMalformedResilience() throws {
        let validJSON = #"""
        {"timestamp":"2026-11-16 14:20:05.250000+0800","processImagePath":"/System/Library/PrivateFrameworks/PrivateCloudCompute.framework/Versions/A/XPCServices/privatecloudcomputed","processID":4321,"subsystem":"com.apple.PrivateCloudCompute","category":"token","eventMessage":"Token request to inference.issuer.apple.com failed with Code=32033","eventType":"logEvent"}
        """#

        let event = try XCTUnwrap(
            UnifiedLogStreamService.parseSingleNDJSONLine(Data(validJSON.utf8), sourceDevice: "This Mac")
        )
        XCTAssertEqual(event.processName, "privatecloudcomputed")
        XCTAssertEqual(event.processID, 4321)
        XCTAssertEqual(event.subsystem, "com.apple.PrivateCloudCompute")
        XCTAssertEqual(event.category, "token")
        XCTAssertEqual(event.sourceDevice, "This Mac")
        XCTAssertTrue(event.isPCCSignal)

        let expectedDate = try XCTUnwrap(UnifiedLogStreamService.parseLogTimestamp("2026-11-16 14:20:05.250000+0800"))
        XCTAssertEqual(event.timestamp.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.001)

        // Missing processImagePath falls back to "unknown"
        let missingProc = #"{"eventMessage":"hello world","processID":77}"#
        let unknownEvent = try XCTUnwrap(UnifiedLogStreamService.parseSingleNDJSONLine(Data(missingProc.utf8)))
        XCTAssertEqual(unknownEvent.processName, "unknown")
        XCTAssertEqual(unknownEvent.processID, 77)

        // Empty / malformed / missing message lines return nil
        XCTAssertNil(UnifiedLogStreamService.parseSingleNDJSONLine(Data()))
        XCTAssertNil(UnifiedLogStreamService.parseSingleNDJSONLine(Data("plain text log line".utf8)))
        XCTAssertNil(UnifiedLogStreamService.parseSingleNDJSONLine(Data("{truncated json".utf8)))
        XCTAssertNil(UnifiedLogStreamService.parseSingleNDJSONLine(Data(#"{"eventType":"activityCreateEvent"}"#.utf8)))
        XCTAssertNil(UnifiedLogStreamService.parseSingleNDJSONLine(Data(#"{"eventMessage":""}"#.utf8)))
    }

    func testUnifiedLogStreamParseNDJSONDataFiltersInvalidChunks() {
        let ndjson = """

        not-json-preamble
        {"timestamp":"2026-11-16 14:20:05.100000+0800","processImagePath":"/usr/libexec/assistantd","processID":101,"subsystem":"com.apple.siri","eventMessage":"ADConnection ready"}
        {broken-json-line
        {"eventType":"signpostEvent","processID":102}
        {"timestamp":"2026-11-16 14:20:06.200000+0800","processImagePath":"/usr/libexec/modelmanagerd","processID":202,"subsystem":"com.apple.UnifiedAssetFramework","eventMessage":"Downloading UAF asset 50.0%"}

        """

        let events = UnifiedLogStreamService.parseNDJSONData(Data(ndjson.utf8), sourceDevice: "This Mac")
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].processName, "assistantd")
        XCTAssertEqual(events[1].processName, "modelmanagerd")
        XCTAssertEqual(events[1].processID, 202)
        XCTAssertTrue(UnifiedLogStreamService.parseNDJSONData(Data()).isEmpty)
    }

    // MARK: - USBiPhoneLogBridge Structured Noise Filtering

    func testUSBiPhoneLogBridgeRejectsBareKeywordNoiseAndKeepsGenuineSignals() throws {
        // Noise lines with incidental bare keywords must be filtered out
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:00:00 iPhone backupd(CloudDocs)[999] <Notice>: syncing photos library metadata",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:00:01 iPhone Preferences(Settings)[812] <Notice>: toggling siri suggestions display",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:00:02 iPhone SpringBoard[34] <Notice>: rendering generative wallpaper thumbnail",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:00:03 iPhone kernel(AppleH16ANEInterface)[0] <Notice>: ANE0: CleanupRTBuddyEndpoints",
                sourceDevice: "USB iPhone"
            )
        )

        // Genuine signals must pass
        let cleanUp = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:01:00 iPhone MobileSlideShow(PhotoImaging)[4102] <Notice>: Starting Photos CleanUp generative inpaint segmentation",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertEqual(cleanUp.cleanProcessName, "MobileSlideShow")
        XCTAssertEqual(cleanUp.subsystem, "PhotoImaging")
        XCTAssertTrue(cleanUp.isPhotosCleanUpSignal)

        let assistant = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:01:01 iPhone assistantd[188] <Notice>: ADConnection error connecting to guzzoni.apple.com via 198.18.4.22 (connection reset by proxy)",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertEqual(assistant.cleanProcessName, "assistantd")
        XCTAssertEqual(DiagnosticTranslator.translate(event: assistant)?.code, .siriGuzzoniProxyMisroute)

        let pcc32033 = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:01:02 iPhone privatecloudcomputed[512] <Error>: Token request to inference.issuer.apple.com failed with PrivateCloudComputeError Code=32033",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertTrue(pcc32033.isPCCSignal)
        XCTAssertEqual(DiagnosticTranslator.translate(event: pcc32033)?.code, .code32033BlindTokenLeak)

        let guzzoniLine = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:01:03 iPhone nsurlsessiond[215] <Notice>: Connecting to guzzoni.apple.com:443",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertEqual(guzzoniLine.cleanProcessName, "nsurlsessiond")

        let claudeLine = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 12:01:04 iPhone Claude(CFNetwork)[20411] <Notice>: Connection 1: TLS handshake complete on utun9",
                sourceDevice: "USB iPhone"
            )
        )
        XCTAssertEqual(claudeLine.cleanProcessName, "Claude")
        XCTAssertEqual(claudeLine.subsystem, "CFNetwork")
        XCTAssertEqual(claudeLine.processID, 20411)
    }

    func testUSBiPhoneLogBridgeImportLogTextFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("applelens-test-\(UUID().uuidString).log")
        let content = """
        Nov 16 12:00:00 privatecloudcomputed[11] Code=32033 issuer.apple.com

           
        Nov 16 12:00:05 assistantd[22] ADConnection error guzzoni.apple.com
        """
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let events = try USBiPhoneLogBridge.importLogTextFile(url: tempURL)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].processName, "ImportedLog")
        XCTAssertEqual(events[0].subsystem, "file.import")
        XCTAssertEqual(events[0].sourceDevice, "Imported (\(tempURL.lastPathComponent))")
        XCTAssertTrue(events[1].message.contains("guzzoni.apple.com"))
    }

    // MARK: - ProcessSocketScanner Cache Cap & SystemProxyInfo

    func testProcessSocketScannerMetadataCacheIsBoundedAt512Entries() {
        let scanner = ProcessSocketScanner()
        XCTAssertEqual(scanner.cachedMetadataCount, 0)

        for index in 0..<650 {
            let meta = scanner.resolveBundleMetadata(executablePath: "/usr/local/bin/synthetic-tool-\(index)")
            XCTAssertEqual(meta.executableName, "synthetic-tool-\(index)")
        }

        XCTAssertGreaterThan(scanner.cachedMetadataCount, 0)
        XCTAssertLessThanOrEqual(scanner.cachedMetadataCount, 512)
    }

    func testSystemProxyInfoIsLoopbackAndActiveLocalProxyPorts() {
        XCTAssertTrue(SystemProxyInfo.isLoopback("127.0.0.1"))
        XCTAssertTrue(SystemProxyInfo.isLoopback("::1"))
        XCTAssertTrue(SystemProxyInfo.isLoopback("localhost"))
        XCTAssertTrue(SystemProxyInfo.isLoopback("LOCALHOST"))

        XCTAssertFalse(SystemProxyInfo.isLoopback("192.168.1.10"))
        XCTAssertFalse(SystemProxyInfo.isLoopback("198.18.0.1"))
        XCTAssertFalse(SystemProxyInfo.isLoopback("0.0.0.0"))
        XCTAssertFalse(SystemProxyInfo.isLoopback(""))

        let info = SystemProxyInfo(
            httpEnabled: true,
            httpHost: "127.0.0.1",
            httpPort: 6152,
            httpsEnabled: true,
            httpsHost: "localhost",
            httpsPort: 6152,
            socksEnabled: true,
            socksHost: "192.168.1.50",
            socksPort: 6153,
            exceptionsList: ["guzzoni.apple.com"]
        )
        XCTAssertEqual(info.activeLocalProxyPorts, Set([6152]))

        let ipv6AndDisabled = SystemProxyInfo(
            httpEnabled: false,
            httpHost: "127.0.0.1",
            httpPort: 8080,
            httpsEnabled: true,
            httpsHost: "::1",
            httpsPort: 0,
            socksEnabled: true,
            socksHost: "::1",
            socksPort: 7891,
            exceptionsList: []
        )
        XCTAssertEqual(ipv6AndDisabled.activeLocalProxyPorts, Set([7891]))
    }

    // MARK: - LanguageManager Thread Safety & Isolated Persistence

    func testLanguageManagerIsolatedUserDefaultsRoundTrip() throws {
        let suiteName = "com.kianuni.AppleLensTests.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.en.rawValue, forKey: "applelens.language")
        let manager = LanguageManager(defaults: defaults)
        XCTAssertEqual(manager.current, .en)
        XCTAssertEqual(manager.text("中文标题", "English Title"), "English Title")

        manager.toggle()
        XCTAssertEqual(manager.current, .zhHans)
        XCTAssertEqual(manager.text("中文标题", "English Title"), "中文标题")

        // Reload with a second manager sharing the isolated suite to confirm persistence
        let reloaded = LanguageManager(defaults: defaults)
        XCTAssertEqual(reloaded.current, .zhHans)

        reloaded.toggle()
        XCTAssertEqual(reloaded.current, .en)

        let reloadedAgain = LanguageManager(defaults: defaults)
        XCTAssertEqual(reloadedAgain.current, .en)
    }

    func testLanguageManagerConcurrentReadsAndTogglesAreDataRaceFree() async throws {
        let suiteName = "com.kianuni.AppleLensTests.language.concurrent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.zhHans.rawValue, forKey: "applelens.language")
        let manager = LanguageManager(defaults: defaults)

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<24 {
                group.addTask {
                    for step in 0..<25 {
                        if (idx + step).isMultiple(of: 3) {
                            manager.toggle()
                        } else {
                            let label = manager.text("测试", "Test")
                            XCTAssertTrue(label == "测试" || label == "Test")
                            let lang = manager.current
                            XCTAssertTrue(lang == .zhHans || lang == .en)
                        }
                    }
                }
            }
        }

        let finalLang = manager.current
        let reloaded = LanguageManager(defaults: defaults)
        XCTAssertEqual(reloaded.current, finalLang)
    }

    // MARK: - Additional Catalog & Probe Verdict Hardening

    func testLLMEndpointCatalogCloudflareAnycastAndProcessNormalization() {
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("104.16.0.1"))
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("104.31.255.254"))
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("172.64.0.1"))
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("172.71.255.1"))
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("162.159.135.42"))
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast("188.114.96.1"))

        XCTAssertFalse(LLMEndpointCatalog.isSharedCloudflareAnycast("104.15.255.254"))
        XCTAssertFalse(LLMEndpointCatalog.isSharedCloudflareAnycast("104.32.0.1"))
        XCTAssertFalse(LLMEndpointCatalog.isSharedCloudflareAnycast("172.72.0.1"))
        XCTAssertFalse(LLMEndpointCatalog.isSharedCloudflareAnycast("1.1.1.1"))

        XCTAssertEqual(LLMEndpointCatalog.normalizeProcessName("Claude(CFNetwork)"), "Claude")
        XCTAssertEqual(LLMEndpointCatalog.normalizeProcessName("  assistantd  "), "assistantd")
        XCTAssertTrue(LLMEndpointCatalog.isKnownAIClient(executableName: "python3.12", bundleID: nil))
        XCTAssertTrue(LLMEndpointCatalog.isKnownAIClient(executableName: "Helper", bundleID: "com.google.antigravity"))
    }

    func testFullProbeReportRejectsMitMOnGuzzoniAndPCCRelays() {
        let report = FullProbeReport(
            ranAt: Date(),
            exitLanes: [
                ExitRegionLaneResult(
                    id: "direct", titleZh: "", titleEn: "", reachable: true, latencyMs: 50,
                    countryCode: "CN", coloCode: "SHA", ipAddress: "111.34.1.1", probedHost: "www.visa.cn",
                    verdictLevel: .pass, verdictZh: "", verdictEn: ""
                )
            ],
            siriAudit: SiriDNSAuditResult(
                guzzoniResolvedIPs: ["198.18.14.68"],
                siriResolvedIPs: ["17.1.1.1"],
                isGuzzoniFakeIP: true,
                isSiriFakeIP: false,
                systemProxyEnabled: true,
                exceptionsIncludeGuzzoni: true
            ),
            endpointProbes: [
                EndpointTLSProbeResult(
                    id: "guzzoni.apple.com", host: "guzzoni.apple.com", roleZh: "", roleEn: "",
                    expectDirect: true, pinningSensitive: true, reachable: true, httpStatus: 200,
                    latencyMs: 100, leafSubject: "guzzoni.apple.com", issuerSummary: "Surge MitM CA",
                    rootSubject: "Surge MitM Root", isMitMDetected: true, mitmReason: "MitM CA", errorDescription: nil
                ),
                EndpointTLSProbeResult(
                    id: "mask-api.icloud.com", host: "mask-api.icloud.com", roleZh: "", roleEn: "",
                    expectDirect: false, pinningSensitive: true, reachable: true, httpStatus: 200,
                    latencyMs: 150, leafSubject: "mask-api.icloud.com", issuerSummary: "Apple",
                    rootSubject: "Apple", isMitMDetected: false, mitmReason: nil, errorDescription: nil
                )
            ],
            quicProbes: [
                QUICProbeResult(id: "cp4.cloudflare.com:443", host: "cp4.cloudflare.com", port: 443, succeeded: true, latencyMs: 40, detailZh: "", detailEn: "")
            ]
        )

        XCTAssertEqual(report.mitmDetectedCount, 1)
        XCTAssertTrue(report.quicAllPassed)
        XCTAssertFalse(report.isGuzzoniCleanTLS)
        XCTAssertFalse(report.isSiriVIFDirectHealthy)
        XCTAssertFalse(report.isSiriEffectivelyHealthy)
        XCTAssertFalse(report.pccTCPFallbackHealthy)
        XCTAssertFalse(report.isQUICUsingTCPFallback)
    }
}
