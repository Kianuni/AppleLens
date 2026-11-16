import AppleLensCore
import XCTest

final class RadarTests: XCTestCase {
    func testIsFakeIPRange() {
        XCTAssertTrue(LLMEndpointCatalog.isFakeIP("198.18.14.17"))
        XCTAssertTrue(LLMEndpointCatalog.isFakeIP("198.19.0.5"))
        XCTAssertTrue(LLMEndpointCatalog.isFakeIP("198.18.0.1"))
        XCTAssertTrue(LLMEndpointCatalog.isFakeIP("198.19.255.254"))

        XCTAssertFalse(LLMEndpointCatalog.isFakeIP("198.20.0.1"))
        XCTAssertFalse(LLMEndpointCatalog.isFakeIP("198.17.255.255"))
        XCTAssertFalse(LLMEndpointCatalog.isFakeIP("104.18.32.7"))
        XCTAssertFalse(LLMEndpointCatalog.isFakeIP("not.an.ip"))
    }

    func testOutermostAppBundlePath() {
        let nestedBinary = "/Applications/Antigravity.app/Contents/Resources/bin/language_server"
        XCTAssertEqual(
            ProcessSocketScanner.outermostAppBundlePath(for: nestedBinary),
            "/Applications/Antigravity.app"
        )

        let nestedHelperApp = "/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper (Renderer).app/Contents/MacOS/Antigravity Helper (Renderer)"
        XCTAssertEqual(
            ProcessSocketScanner.outermostAppBundlePath(for: nestedHelperApp),
            "/Applications/Antigravity.app"
        )

        let plainCLI = "/usr/local/bin/python3"
        XCTAssertNil(ProcessSocketScanner.outermostAppBundlePath(for: plainCLI))
    }

    func testIsExcludedProxyProcess() {
        XCTAssertTrue(
            LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: "Surge",
                bundleID: "com.nssurge.surge-mac",
                bundlePath: "/Applications/Surge.app"
            )
        )
        XCTAssertTrue(
            LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: "com.nssurge.surge-mac.ne",
                bundleID: "com.nssurge.surge-mac.ne",
                bundlePath: nil
            )
        )
        XCTAssertTrue(
            LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: "mihomo",
                bundleID: nil,
                bundlePath: nil
            )
        )

        XCTAssertFalse(
            LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: "Antigravity",
                bundleID: "com.google.antigravity",
                bundlePath: "/Applications/Antigravity.app"
            )
        )
        XCTAssertFalse(
            LLMEndpointCatalog.isExcludedProxyProcess(
                executableName: "language_server",
                bundleID: "com.google.antigravity",
                bundlePath: "/Applications/Antigravity.app"
            )
        )
    }

    func testDNSFakeIPMapperFakeIPVsSharedCloudflareRealIPClientGating() throws {
        let openai = try XCTUnwrap(LLMEndpointCatalog.providers.first { $0.id == "openai" })
        let applePCC = try XCTUnwrap(LLMEndpointCatalog.providers.first { $0.id == "apple-pcc" })
        let mapper = DNSFakeIPMapper()

        // 1. Fake-IP match works unambiguously regardless of client name
        mapper.seedMapping(ip: "198.18.14.17", provider: openai, domain: "api.openai.com")
        XCTAssertEqual(mapper.mappedEntryCount, 1)

        let fakeIPMatch = mapper.match(
            remoteIP: "198.18.14.17",
            executableName: "CustomResearchTool",
            bundleID: nil
        )
        XCTAssertNotNil(fakeIPMatch)
        XCTAssertEqual(fakeIPMatch?.provider.id, "openai")
        XCTAssertEqual(fakeIPMatch?.matchedDomain, "api.openai.com")
        XCTAssertEqual(fakeIPMatch?.confidence, .exactFakeIP)
        XCTAssertEqual(fakeIPMatch?.isFakeIP, true)

        // 2. Shared Cloudflare Real-IP gates out generic browsers, allows known AI clients
        let sharedCFIP = "104.18.32.7"
        XCTAssertTrue(LLMEndpointCatalog.isSharedCloudflareAnycast(sharedCFIP))
        mapper.seedMapping(ip: sharedCFIP, provider: openai, domain: "chatgpt.com")

        let genericBrowserMatch = mapper.match(
            remoteIP: sharedCFIP,
            executableName: "Safari",
            bundleID: "com.apple.Safari"
        )
        XCTAssertNil(genericBrowserMatch, "Non-AI client on shared Cloudflare IP must be gated out to prevent false positives")

        let knownClientMatch = mapper.match(
            remoteIP: sharedCFIP,
            executableName: "language_server",
            bundleID: "com.google.antigravity"
        )
        XCTAssertNotNil(knownClientMatch)
        XCTAssertEqual(knownClientMatch?.provider.id, "openai")
        XCTAssertEqual(knownClientMatch?.matchedDomain, "chatgpt.com")
        XCTAssertEqual(knownClientMatch?.confidence, .resolvedDomainKnownClient)
        XCTAssertEqual(knownClientMatch?.isFakeIP, false)

        // 3. Apple PCC Real-IP only attributes to known Apple PCC daemons
        mapper.seedMapping(ip: "17.248.0.10", provider: applePCC, domain: "inference.issuer.apple.com")
        XCTAssertNil(mapper.match(remoteIP: "17.248.0.10", executableName: "Safari", bundleID: "com.apple.Safari"))
        let pccMatch = mapper.match(remoteIP: "17.248.0.10", executableName: "privatecloudcomputed", bundleID: nil)
        XCTAssertEqual(pccMatch?.provider.id, "apple-pcc")
        XCTAssertEqual(pccMatch?.confidence, .resolvedDomainKnownClient)

        // 4. Dedicated static IPv4 prefix (Anthropic 160.79.104.*)
        let dedicatedMatch = mapper.match(remoteIP: "160.79.104.10", executableName: "CustomBinary", bundleID: nil)
        XCTAssertEqual(dedicatedMatch?.provider.id, "anthropic")
        XCTAssertEqual(dedicatedMatch?.confidence, .dedicatedIP)
        XCTAssertEqual(dedicatedMatch?.isFakeIP, false)
    }

    func testFirstSeenProcessTrackerIsolatedUserDefaults() throws {
        let suiteName = "com.kianuni.AppleLensTests.tracker.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "com.example.TestAIClient"
        let tracker = FirstSeenProcessTracker(defaults: defaults)

        XCTAssertFalse(tracker.isTrusted(key))
        XCTAssertTrue(tracker.allTrustedKeys().isEmpty)

        // First-seen check triggers once per session
        XCTAssertTrue(tracker.shouldNotifyFirstSeen(identityKey: key))
        XCTAssertFalse(tracker.shouldNotifyFirstSeen(identityKey: key))

        // Trusting persists into UserDefaults
        tracker.trust(key)
        XCTAssertTrue(tracker.isTrusted(key))
        XCTAssertEqual(tracker.allTrustedKeys(), [key])

        let reloadedTracker = FirstSeenProcessTracker(defaults: defaults)
        XCTAssertTrue(reloadedTracker.isTrusted(key))
        XCTAssertFalse(reloadedTracker.shouldNotifyFirstSeen(identityKey: key))

        // Untrusting removes persistence
        reloadedTracker.untrust(key)
        XCTAssertFalse(reloadedTracker.isTrusted(key))
        XCTAssertTrue(reloadedTracker.allTrustedKeys().isEmpty)

        let postUntrustTracker = FirstSeenProcessTracker(defaults: defaults)
        XCTAssertTrue(postUntrustTracker.shouldNotifyFirstSeen(identityKey: key))
    }

    func testIOSAppMatchingAndSyslogParsing() throws {
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: nil, processName: "Claude(CFNetwork)")?.id,
            "anthropic"
        )
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: "com.anthropic.claude", processName: "runningboardd")?.id,
            "anthropic"
        )
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: nil, processName: "ChatGPT")?.id,
            "openai"
        )

        let rawLine = "Nov 16 15:02:15 iPhone Claude(CFNetwork)[20411] <Notice>: Connection 1: TLS handshake complete on utun9"
        let parsed = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(rawLine, sourceDevice: "USB iPhone")
        )
        XCTAssertEqual(parsed.cleanProcessName, "Claude")
        XCTAssertEqual(parsed.processID, 20411)
        XCTAssertEqual(parsed.subsystem, "CFNetwork")
    }

    func testFullProbeReportVIFAndTCPFallbackVerdicts() {
        let report = FullProbeReport(
            ranAt: Date(),
            exitLanes: [
                ExitRegionLaneResult(
                    id: "direct",
                    titleZh: "Direct",
                    titleEn: "Direct",
                    reachable: true,
                    latencyMs: 95,
                    countryCode: "CN",
                    coloCode: "LYA",
                    ipAddress: "111.34.1.1",
                    probedHost: "www.visa.cn",
                    verdictLevel: .pass,
                    verdictZh: "OK",
                    verdictEn: "OK"
                )
            ],
            siriAudit: SiriDNSAuditResult(
                guzzoniResolvedIPs: ["198.18.14.68"],
                siriResolvedIPs: ["198.18.14.69"],
                isGuzzoniFakeIP: true,
                isSiriFakeIP: true,
                systemProxyEnabled: true,
                exceptionsIncludeGuzzoni: true,
                guzzoniCanonicalName: "guzzoni-apple-com.v.aaplimg.com"
            ),
            endpointProbes: [
                EndpointTLSProbeResult(
                    id: "guzzoni.apple.com", host: "guzzoni.apple.com", roleZh: "", roleEn: "",
                    expectDirect: true, pinningSensitive: true, reachable: true, httpStatus: 200,
                    latencyMs: 250, leafSubject: "guzzoni.apple.com", issuerSummary: "Apple Public EV",
                    rootSubject: "Apple Root CA", isMitMDetected: false, mitmReason: nil, errorDescription: nil
                ),
                EndpointTLSProbeResult(
                    id: "mask-api.icloud.com", host: "mask-api.icloud.com", roleZh: "", roleEn: "",
                    expectDirect: false, pinningSensitive: true, reachable: true, httpStatus: 200,
                    latencyMs: 380, leafSubject: "mask-api.icloud.com", issuerSummary: "Apple Public EV",
                    rootSubject: "Apple Root CA", isMitMDetected: false, mitmReason: nil, errorDescription: nil
                ),
                EndpointTLSProbeResult(
                    id: "apple-relay.cloudflare.com", host: "apple-relay.cloudflare.com", roleZh: "", roleEn: "",
                    expectDirect: false, pinningSensitive: false, reachable: true, httpStatus: 403,
                    latencyMs: 360, leafSubject: "apple-relay.cloudflare.com", issuerSummary: "WE1",
                    rootSubject: "Google Trust Services", isMitMDetected: false, mitmReason: nil, errorDescription: nil
                ),
                EndpointTLSProbeResult(
                    id: "apple-relay.fastly-edge.com", host: "apple-relay.fastly-edge.com", roleZh: "", roleEn: "",
                    expectDirect: false, pinningSensitive: false, reachable: true, httpStatus: 401,
                    latencyMs: 365, leafSubject: "apple-relay.fastly-edge.com", issuerSummary: "GlobalSign",
                    rootSubject: "GlobalSign", isMitMDetected: false, mitmReason: nil, errorDescription: nil
                )
            ],
            quicProbes: [
                QUICProbeResult(id: "cp4.cloudflare.com:443", host: "cp4.cloudflare.com", port: 443, succeeded: false, latencyMs: 2800, detailZh: "", detailEn: "")
            ]
        )

        XCTAssertTrue(report.isSiriVIFDirectHealthy)
        XCTAssertTrue(report.isSiriEffectivelyHealthy)
        XCTAssertTrue(report.pccTCPFallbackHealthy)
        XCTAssertTrue(report.isQUICUsingTCPFallback)
    }

    func testKernelNoiseFilteredAndRealIOSAppsMatched() throws {
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 15:41:07 iPhone kernel(AppleSARService)[0] <Notice>: SAR RFSensing Decision: Uplink Constraint",
                sourceDevice: "iPhone"
            )
        )
        XCTAssertNil(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 15:41:07 iPhone kernel(AppleH16ANEInterface)[0] <Notice>: ANE0: CleanupRTBuddyEndpoints",
                sourceDevice: "iPhone"
            )
        )

        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: nil, processName: "Grace(CFNetwork)")?.id,
            "doubao"
        )
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: "com.bot.doubao", processName: "runningboardd")?.id,
            "doubao"
        )
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: nil, processName: "GrokApp(Network)")?.id,
            "xai"
        )

        LLMEndpointCatalog.registerDynamicIOSApps([
            (bundleID: "com.deepseek.chat", executable: "DeepSeekApp", displayName: "DeepSeek"),
            (bundleID: "com.tencent.xin", executable: "WeChat", displayName: "WeChat")
        ])
        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: nil, processName: "DeepSeekApp(CFNetwork)")?.id,
            "deepseek"
        )
        XCTAssertNil(LLMEndpointCatalog.matchIOSApp(bundleID: "com.tencent.xin", processName: "WeChat"))

        let dynamicGrace = try XCTUnwrap(
            USBiPhoneLogBridge.parseSyslogRelayLine(
                "Nov 16 15:41:09 iPhone Grace(CFNetwork)[21044] <Notice>: Connection 3: TLS handshake complete",
                sourceDevice: "iPhone"
            )
        )
        XCTAssertEqual(dynamicGrace.cleanProcessName, "Grace")
        XCTAssertEqual(dynamicGrace.processID, 21044)
    }

    @MainActor
    func testClaudeForegroundRetentionSceneIDAndVisualIntelligencePriority() async throws {
        let radar = TriStateRadarCoordinator()
        radar.setTargetIOSMode(true)

        // 1. SpringBoard launches / activates existing Claude app via sceneID + runningboardd transition + CFNetwork socket teardown
        let springBoardEvent = UnifiedLogEvent(
            processName: "SpringBoard",
            processID: 34,
            subsystem: "com.apple.FrontBoard",
            message: "Now foregrounding sceneID:com.anthropic.claude-default (role: UserInteractiveFocal)",
            sourceDevice: "iPhone"
        )
        radar.ingestUnifiedLogEvent(springBoardEvent)

        let transitionEvent = UnifiedLogEvent(
            processName: "runningboardd",
            processID: 31,
            subsystem: "com.apple.runningboard",
            message: "Calculated state for app<com.anthropic.claude(11111111-2222-3333-4444-555555555555)>: from running-suspended to running-active (role: UserInteractiveFocal)",
            sourceDevice: "iPhone"
        )
        radar.ingestUnifiedLogEvent(transitionEvent)

        let socketCleanupEvent = UnifiedLogEvent(
            processName: "Claude(CFNetwork)",
            processID: 1204,
            subsystem: "CFNetwork",
            message: "Connection 9: shutdown sockets complete on old interface, opening fresh flow",
            sourceDevice: "iPhone"
        )
        radar.ingestUnifiedLogEvent(socketCleanupEvent)

        // 2. Camera Visual Intelligence + subsequent noisy/generic logs
        let visualIntelEvent = UnifiedLogEvent(
            processName: "CameraOverlayAngel",
            processID: 2300,
            subsystem: "com.apple.VisualIntelligence",
            message: "VisualIntelligence analysis started on camera overlay",
            sourceDevice: "iPhone"
        )
        radar.ingestUnifiedLogEvent(visualIntelEvent)

        let genericSiriEvent = UnifiedLogEvent(
            processName: "siriinferenced",
            processID: 180,
            subsystem: "com.apple.siri",
            message: "Background inference routine heartbeat",
            sourceDevice: "iPhone"
        )
        radar.ingestUnifiedLogEvent(genericSiriEvent)

        let xpcNoiseOnDevice = UnifiedLogEvent(
            processName: "TGOnDeviceInferenceProviderService",
            processID: 440,
            subsystem: "com.apple.GenerativeModels",
            message: "requesting resource bundle container for internal probe",
            sourceDevice: "iPhone"
        )
        XCTAssertFalse(xpcNoiseOnDevice.isOnDeviceInferenceSignal)
        radar.ingestUnifiedLogEvent(xpcNoiseOnDevice)

        let xpcNoisePCC = UnifiedLogEvent(
            processName: "privatecloudcomputed",
            processID: 550,
            subsystem: "com.apple.PrivateCloudCompute",
            message: "[0x740306a800] Re-initialization successful; calling out to event handler with XPC_ERROR_CONNECTION_INTERRUPTED",
            sourceDevice: "iPhone"
        )
        XCTAssertFalse(xpcNoisePCC.isPCCSignal)
        radar.ingestUnifiedLogEvent(xpcNoisePCC)

        let claudeSession = try XCTUnwrap(radar.iosActiveSessions.first { $0.provider.id == "anthropic" })
        XCTAssertFalse(claudeSession.isSuspended, "Foreground Claude must stay active across transition/socket-cleanup logs")
        XCTAssertTrue(radar.lastOnDeviceDetail.contains("视觉智能"), "Generic siriinferenced / XPC noise must not overwrite Visual Intelligence detail")
        XCTAssertFalse(radar.isPCCActive, "XPC_ERROR_CONNECTION_INTERRUPTED re-init boilerplate must not trigger PCC active state")
        XCTAssertEqual(radar.overallState, .hybrid)
    }
}
