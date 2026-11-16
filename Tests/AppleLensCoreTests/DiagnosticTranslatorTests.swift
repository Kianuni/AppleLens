import AppleLensCore
import XCTest

final class DiagnosticTranslatorTests: XCTestCase {
    func testSampleFaultLogLinesAllTranslateToNonNilFindings() {
        let samples = DiagnosticTranslator.sampleFaultLogLines
        XCTAssertEqual(samples.count, 6)

        let findings = samples.compactMap { sample in
            DiagnosticTranslator.translate(
                line: sample.message,
                process: sample.process,
                subsystem: sample.subsystem
            )
        }

        XCTAssertEqual(findings.count, samples.count, "Every sampleFaultLogLines entry should produce a non-nil DiagnosticFinding")

        let expectedCodes: [DiagnosticCode] = [
            .code32033BlindTokenLeak,
            .quicUDP443Blocked,
            .code1009LocalCooldown,
            .ios27_3CHRegionPolicyLock,
            .siriGuzzoniProxyMisroute,
            .modelAssetDownloadProgress
        ]
        XCTAssertEqual(findings.map(\.code), expectedCodes)
    }

    func testCode32033BlindTokenLeak() {
        let finding = DiagnosticTranslator.translate(
            line: "Token request to inference.issuer.apple.com failed with PrivateCloudComputeError Code=32033",
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute"
        )

        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.code, .code32033BlindTokenLeak)
        XCTAssertEqual(finding?.severity, .critical)
        XCTAssertEqual(finding?.actionURL, DiagnosticTranslator.appleFlowURL)
        XCTAssertNotNil(finding?.copyableSnippet)
        XCTAssertTrue(finding?.copyableSnippet?.contains("issuer.apple.com") == true)
        XCTAssertFalse(finding?.title(lang: .zhHans).isEmpty ?? true)
        XCTAssertFalse(finding?.title(lang: .en).isEmpty ?? true)
    }

    func testQuicUDP443Blocked() {
        let finding = DiagnosticTranslator.translate(
            line: "OHTTP QUIC handshake to apple-relay.cloudflare.com:443 timed out over UDP (QUIC-BLOCK suspected)",
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute"
        )

        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.code, .quicUDP443Blocked)
        XCTAssertEqual(finding?.severity, .warning)
        XCTAssertEqual(finding?.actionURL, DiagnosticTranslator.appleFlowURL)
    }

    func testCode1009LocalCooldownWithRetryAfterVsServerQuotaWithoutRetryAfter() {
        let localCooldown = DiagnosticTranslator.translate(
            line: "PrivateCloudComputeError Code=1009 \"Rate-limited for token issuer based on retry-after header\"",
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute"
        )

        XCTAssertNotNil(localCooldown)
        XCTAssertEqual(localCooldown?.code, .code1009LocalCooldown)
        XCTAssertEqual(localCooldown?.severity, .warning)
        XCTAssertTrue(localCooldown?.titleEn.contains("retry-after") == true)

        let serverQuota = DiagnosticTranslator.translate(
            line: "PrivateCloudComputeError Code=1009 \"Rate-limited for token issuer\"",
            process: "privatecloudcomputed",
            subsystem: "com.apple.PrivateCloudCompute"
        )

        XCTAssertNotNil(serverQuota)
        XCTAssertEqual(serverQuota?.code, .code1009ServerQuota)
        XCTAssertEqual(serverQuota?.severity, .warning)
        XCTAssertFalse(serverQuota?.titleEn.contains("retry-after") ?? true)
    }

    func testIOS27_3CHRegionPolicyLock() {
        let finding = DiagnosticTranslator.translate(
            line: "[GenerativeFunctionsFoundation:Eligibility] Eligibility returned no CN region policy on a CH region code device",
            process: "Photos",
            subsystem: "com.apple.GenerativeFunctionsFoundation"
        )

        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.code, .ios27_3CHRegionPolicyLock)
        XCTAssertEqual(finding?.severity, .critical)
        XCTAssertEqual(finding?.actionURL, DiagnosticTranslator.erosionURL)
        XCTAssertNil(finding?.copyableSnippet)
    }

    func testSiriGuzzoniProxyMisroute() {
        let finding = DiagnosticTranslator.translate(
            line: "ADConnection error connecting to guzzoni.apple.com via 198.18.4.22 (connection reset by proxy)",
            process: "assistantd",
            subsystem: "com.apple.siri"
        )

        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.code, .siriGuzzoniProxyMisroute)
        XCTAssertEqual(finding?.severity, .critical)
        XCTAssertEqual(finding?.actionURL, DiagnosticTranslator.appleFlowURL)
        XCTAssertTrue(finding?.copyableSnippet?.contains("guzzoni.apple.com") == true)
        XCTAssertTrue(finding?.copyableSnippet?.contains("always-real-ip") == true)
    }

    func testModelAssetDownloadProgressPercentageAndRatio() throws {
        let pctFinding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "UAF model asset download progress for com.apple.if.generative: 68.5% downloaded",
                process: "modelmanagerd",
                subsystem: "com.apple.UnifiedAssetFramework"
            )
        )
        XCTAssertEqual(pctFinding.code, .modelAssetDownloadProgress)
        XCTAssertEqual(pctFinding.severity, .info)
        XCTAssertEqual(try XCTUnwrap(pctFinding.progressFraction), 0.685, accuracy: 0.0001)

        let ratioFinding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "MobileAsset downloaded: 1048576 / 2097152 bytes",
                process: "modelmanagerd",
                subsystem: "com.apple.MobileAsset"
            )
        )
        XCTAssertEqual(ratioFinding.code, .modelAssetDownloadProgress)
        XCTAssertEqual(try XCTUnwrap(ratioFinding.progressFraction), 0.5, accuracy: 0.0001)
    }

    func testADAssetManagerStatusParsing() throws {
        let partialFinding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "Retrieved asset status ASR: 1, NL: 0, Morphun: 1, Attention: 0, NLRouter: 0, IF: 0, TB: 0 (lang:zh-CN, uod:1, hybrid:0)",
                process: "assistantd",
                subsystem: "com.apple.siri"
            )
        )
        XCTAssertEqual(partialFinding.code, .modelAssetDownloadProgress)
        XCTAssertEqual(partialFinding.severity, .info)
        XCTAssertNil(partialFinding.progressFraction)
        XCTAssertTrue(partialFinding.titleEn.contains("zh-CN"))
        XCTAssertTrue(partialFinding.explanationEn.contains("ASR=Ready"))
        XCTAssertTrue(partialFinding.explanationEn.contains("NLRouter=Missing"))

        let zhReadyFinding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "Retrieved asset status ASR: 1, NL: 0, Morphun: 1, Attention: 0, NLRouter: 1, IF: 0, TB: 0 (lang:zh-CN, uod:1, hybrid:0)",
                process: "assistantd",
                subsystem: "com.apple.siri"
            )
        )
        XCTAssertEqual(zhReadyFinding.code, .modelAssetDownloadProgress)
        XCTAssertNil(zhReadyFinding.progressFraction)
        XCTAssertTrue(zhReadyFinding.titleEn.contains("Ready"))
        XCTAssertTrue(zhReadyFinding.titleEn.contains("zh-CN"))
        XCTAssertTrue(zhReadyFinding.explanationEn.contains("normal in zh-CN"))

        let readyFinding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "Retrieved asset status ASR: 1, NL: 1, Morphun: 1, Attention: 1, NLRouter: 1, IF: 1, TB: 1 (lang:en-US, uod:1, hybrid:0)",
                process: "assistantd",
                subsystem: "com.apple.siri"
            )
        )
        XCTAssertEqual(readyFinding.code, .modelAssetDownloadProgress)
        XCTAssertNil(readyFinding.progressFraction)
        XCTAssertTrue(readyFinding.titleEn.contains("Ready"))
        XCTAssertTrue(readyFinding.explanationEn.contains("Legacy IF=1"))
    }

    func testSlot266InstantAbort() {
        let slotFinding = DiagnosticTranslator.translate(
            line: "CacheData slot #266 Personal Translator check failed: aborting immediately",
            process: "generativeexperiencesd",
            subsystem: "com.apple.GenerativeModels"
        )
        XCTAssertNotNil(slotFinding)
        XCTAssertEqual(slotFinding?.code, .slot266InstantAbort)
        XCTAssertEqual(slotFinding?.severity, .critical)
        XCTAssertEqual(slotFinding?.actionURL, DiagnosticTranslator.erosionURL)

        let catalogFinding = DiagnosticTranslator.translate(
            line: "ModelCatalog unavailable error during preflight check",
            process: "TGOnDeviceInferenceProviderService",
            subsystem: "ModelCatalog"
        )
        XCTAssertNil(catalogFinding)
    }

    func testUnrelatedLogLineReturnsNil() {
        let finding = DiagnosticTranslator.translate(
            line: "WindowServer compositor frame committed in 4.2ms",
            process: "WindowServer",
            subsystem: "com.apple.SkyLight"
        )
        XCTAssertNil(finding)
    }

    func testPhotosCleanUpAndPCCSignalRecognition() {
        let onDeviceCleanUp = UnifiedLogEvent(
            processName: "MobileSlideShow",
            processID: 21001,
            subsystem: "com.apple.photos",
            message: "Starting Photos CleanUp generative inpaint segmentation on ANE",
            sourceDevice: "USB iPhone"
        )
        XCTAssertTrue(onDeviceCleanUp.isPhotosCleanUpSignal)
        XCTAssertTrue(onDeviceCleanUp.isOnDeviceInferenceSignal)
        XCTAssertFalse(onDeviceCleanUp.isPCCSignal)
        XCTAssertEqual(onDeviceCleanUp.recognizedFeatureTitle?.en, "Photos Clean Up")

        let pccCleanUp = UnifiedLogEvent(
            processName: "MobileSlideShow",
            processID: 21001,
            subsystem: "com.apple.photos",
            message: "Submitting remote inpaint request via ss-cleanup-proxy OHTTP",
            sourceDevice: "USB iPhone"
        )
        XCTAssertTrue(pccCleanUp.isPhotosCleanUpSignal)
        XCTAssertTrue(pccCleanUp.isPCCSignal)
        XCTAssertEqual(pccCleanUp.recognizedFeatureTitle?.en, "Photos Clean Up")

        let visualIntelEvent = UnifiedLogEvent(
            processName: "CameraOverlayAngel",
            processID: 22100,
            subsystem: "com.apple.VisualIntelligence",
            message: "VisualIntelligence session started for camera control search",
            sourceDevice: "iPhone"
        )
        XCTAssertTrue(visualIntelEvent.isVisualIntelligenceSignal)
        XCTAssertTrue(visualIntelEvent.isOnDeviceInferenceSignal)
        XCTAssertEqual(visualIntelEvent.recognizedFeatureTitle?.en, "Visual Intelligence")

        XCTAssertEqual(
            LLMEndpointCatalog.matchIOSApp(bundleID: "com.openai.chat.IntentsExtension", processName: "IntentsExtension")?.id,
            "openai"
        )
    }

    func testNoFalsePositivesOnBackboardd1009OrNSP32033OrBenignSuccessLogs() throws {
        XCTAssertNil(
            DiagnosticTranslator.translate(
                line: "Nov 16 15:30:27 iPhone backboardd[70] <Notice>: Display digitizer touch event 1009 completed",
                process: "backboardd",
                subsystem: "ios.syslog_relay"
            )
        )
        XCTAssertNil(
            DiagnosticTranslator.translate(
                line: "Nov 16 15:30:25 iPhone networkserviceproxy[112] <Notice>: Flow 32033 stats reported",
                process: "networkserviceproxy",
                subsystem: "ios.syslog_relay"
            )
        )
        XCTAssertNil(
            DiagnosticTranslator.translate(
                line: "Token request to inference.issuer.apple.com completed successfully, error=(null)",
                process: "privatecloudcomputed",
                subsystem: "com.apple.PrivateCloudCompute"
            )
        )
        XCTAssertNil(
            DiagnosticTranslator.translate(
                line: "nw_connection [C12 quic, udp] reporting state ready",
                process: "privatecloudcomputed",
                subsystem: "com.apple.PrivateCloudCompute"
            )
        )
        XCTAssertNil(
            DiagnosticTranslator.translate(
                line: "downloadConnection timeout=60 for asset",
                process: "NRDUpdated",
                subsystem: "MobileAsset"
            )
        )

        let tcpFallbackNotice = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "OHTTP QUIC connection refused on apple-relay.cloudflare.com:443, falling back to TCP",
                process: "privatecloudcomputed",
                subsystem: "com.apple.PrivateCloudCompute"
            )
        )
        XCTAssertEqual(tcpFallbackNotice.code, .quicUDP443Blocked)
        XCTAssertEqual(tcpFallbackNotice.severity, .info)
    }

    func testRetailIOSRedactedDaemonsAndPhotosFrameworks() {
        let redactedSiriInf = UnifiedLogEvent(
            processName: "siriinferenced",
            processID: 6028,
            subsystem: "ios.syslog_relay",
            message: "Nov 16 15:41:08 iPhone siriinferenced[6028] <Notice>: <private>",
            sourceDevice: "iPhone"
        )
        XCTAssertTrue(redactedSiriInf.isOnDeviceInferenceSignal)

        let bookmarkNoise = UnifiedLogEvent(
            processName: "modelmanagerd",
            processID: 1095,
            subsystem: "CoreServicesInternal",
            message: "CFURLResolveBookmarkData",
            sourceDevice: "This Mac"
        )
        XCTAssertFalse(bookmarkNoise.isOnDeviceInferenceSignal)

        let visualPhotos = UnifiedLogEvent(
            processName: "MobileSlideShow",
            processID: 21100,
            subsystem: "VisualIntelligence",
            message: "<private>",
            sourceDevice: "iPhone"
        )
        XCTAssertTrue(visualPhotos.isPhotosCleanUpSignal)
        XCTAssertTrue(visualPhotos.isOnDeviceInferenceSignal)
    }
}
