import AppleLensCore
import XCTest

final class ReportAndAttestationTests: XCTestCase {
    func testSampleReportDecodingAndCloudAttestation() throws {
        let data = SampleReportFixture.sampleReportJSONData()
        XCTAssertFalse(data.isEmpty)

        let report = try IntelligenceReportDecoder.decode(
            data: data,
            fileName: "Sample_Apple_Intelligence_Report.json"
        )

        XCTAssertEqual(report.requests.count, 2)
        XCTAssertEqual(report.pccRequestCount, 1)
        XCTAssertEqual(report.onDeviceRequestCount, 1)
        XCTAssertEqual(report.attestationCount, 1)
        XCTAssertEqual(report.assets.count, 2)

        // Request 0: Private Cloud Compute
        let pccReq = try XCTUnwrap(report.requests.first { $0.executionTarget == .privateCloudCompute })
        XCTAssertEqual(pccReq.useCase, "Siri.AppIntents.WritingTools")

        let roles = pccReq.promptBlocks.map(\.role)
        XCTAssertTrue(roles.contains(.system))
        XCTAssertTrue(roles.contains(.developer))
        XCTAssertTrue(roles.contains(.thought))
        XCTAssertTrue(roles.contains(.user))
        XCTAssertTrue(roles.contains(.tool))

        let systemBlock = try XCTUnwrap(pccReq.promptBlocks.first { $0.role == .system })
        XCTAssertEqual(systemBlock.silentTokenBudget, 64)

        let calendarCall = try XCTUnwrap(pccReq.toolCalls.first { $0.name == "CalendarAppIntent.fetchEvents" })
        XCTAssertTrue(calendarCall.argumentsJSON.contains("windowHours"))
        XCTAssertNotNil(calendarCall.resultPreview)

        XCTAssertEqual(pccReq.pccRequests.count, 1)
        let pccSub = pccReq.pccRequests[0]
        XCTAssertEqual(pccSub.endpoint, "tie-cloudboard.apple.com")

        let attestation = try XCTUnwrap(pccSub.attestation)
        XCTAssertTrue(attestation.apTicketHasIM4MMagic)
        XCTAssertGreaterThan(attestation.apTicketBytes, 4)
        XCTAssertGreaterThan(attestation.sepAttestationBytes, 0)
        XCTAssertNotNil(attestation.sepAttestationSHA256)

        XCTAssertEqual(attestation.certificateChain.count, 2)
        XCTAssertEqual(attestation.certificateChain[0].commonName, "pcc-compute-us-west-02.apple.com")
        XCTAssertTrue(attestation.certificateChain[0].subjectSummary.contains("pcc-compute-us-west-02.apple.com"))
        XCTAssertTrue(attestation.certificateChain[0].isAppleAnchored)
        XCTAssertEqual(attestation.certificateChain[1].commonName, "Apple PCC Provisioning Intermediate CA")

        XCTAssertEqual(attestation.appDataDomain, "com.apple.PrivateCloudCompute")
        XCTAssertEqual(attestation.appDataName, "tie-cloudboard-apple-com")
        XCTAssertEqual(attestation.appDataVersion, 1)
        XCTAssertNotNil(attestation.keyExpiration)

        let darwinInitSlot = try XCTUnwrap(attestation.sealedHashSlots.first { $0.slotName.contains("darwin-init") })
        XCTAssertEqual(darwinInitSlot.hashAlgorithm, "SHA-256")
        XCTAssertFalse(darwinInitSlot.secureConfigsJSON.isEmpty)
        let secureConfig = darwinInitSlot.secureConfigsJSON.joined(separator: "\n")
        XCTAssertTrue(secureConfig.contains("PCC-27.2"))
        XCTAssertTrue(secureConfig.contains("network_egress"))
        XCTAssertTrue(secureConfig.contains("disabled"))

        XCTAssertTrue(attestation.hasTransparencyProof)
        XCTAssertGreaterThan(attestation.transparencyProofBytes, 0)
        XCTAssertNotNil(attestation.transparencyProofSHA256)

        // Request 1: On-Device
        let onDeviceReq = try XCTUnwrap(report.requests.first { $0.executionTarget == .onDevice })
        XCTAssertTrue(onDeviceReq.pccRequests.isEmpty)
        let onDeviceSysBlock = try XCTUnwrap(onDeviceReq.promptBlocks.first { $0.role == .system })
        XCTAssertEqual(onDeviceSysBlock.silentTokenBudget, 32)
    }

    func testDualEpochParseTimestamp() throws {
        // 1970 Unix epoch (> 1_500_000_000)
        let unixSeconds: Double = 1_763_217_819.5
        let parsedUnix = try XCTUnwrap(IntelligenceReportDecoder.parseTimestamp(unixSeconds))
        XCTAssertEqual(parsedUnix.timeIntervalSince1970, unixSeconds, accuracy: 0.001)

        let unixInt: Int = 1_700_000_000
        let parsedUnixInt = try XCTUnwrap(IntelligenceReportDecoder.parseTimestamp(unixInt))
        XCTAssertEqual(parsedUnixInt.timeIntervalSince1970, Double(unixInt), accuracy: 0.001)

        // 2001 Apple Reference Date / CFAbsoluteTime (> 400_000_000 and <= 1_500_000_000)
        let cfSeconds: Double = 784_910_619.25
        let parsedCF = try XCTUnwrap(IntelligenceReportDecoder.parseTimestamp(cfSeconds))
        XCTAssertEqual(parsedCF.timeIntervalSinceReferenceDate, cfSeconds, accuracy: 0.001)
        XCTAssertEqual(
            parsedCF.timeIntervalSince1970,
            Date.timeIntervalBetween1970AndReferenceDate + cfSeconds,
            accuracy: 0.001
        )

        let cfInt: Int = 750_000_000
        let parsedCFInt = try XCTUnwrap(IntelligenceReportDecoder.parseTimestamp(cfInt))
        XCTAssertEqual(parsedCFInt.timeIntervalSinceReferenceDate, Double(cfInt), accuracy: 0.001)

        // ISO-8601 string and invalid inputs
        let isoDate = IntelligenceReportDecoder.parseTimestamp("2026-11-15T14:43:39Z")
        XCTAssertNotNil(isoDate)
        XCTAssertNil(IntelligenceReportDecoder.parseTimestamp(123.0))
        XCTAssertNil(IntelligenceReportDecoder.parseTimestamp(nil))
    }

    func testPhotosCleanUpServerDiffusionCorrelationAndInsightSummary() throws {
        let nowUnix = Date().timeIntervalSince1970
        let sampleAttB64 = SampleReportFixture.buildSampleAttestationBundleBase64()
        let reportDict: [String: Any] = [
            "modelRequests": [
                [
                    "timestamp": nowUnix - 2.0,
                    "identifier": "E41F3900-1122-4455-8899-AABBCCDDEEFF",
                    "useCase": "VisualGeneration.PhotosEdit.Infill.1p",
                    "model": "com.apple.fm.visual.server_diffusion_v2",
                    "clientIdentifier": "com.apple.mobileslideshow"
                ]
            ],
            "privateCloudComputeRequests": [
                [
                    "timestamp": nowUnix - 1.5,
                    "requestId": "PCC-REQ-PHOTOS-01",
                    "pipelineKind": "tie-cloudboard-apple-com",
                    "requestState": "completed",
                    "attestations": [sampleAttB64]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: reportDict, options: [])
        let report = try IntelligenceReportDecoder.decode(data: data, fileName: "Apple_Intelligence_Report.json")

        XCTAssertEqual(report.requests.count, 1, "Top-level privateCloudComputeRequests should correlate into the single VisualGeneration request")
        let req = try XCTUnwrap(report.requests.first)
        XCTAssertEqual(req.executionTarget, .privateCloudCompute)
        XCTAssertEqual(report.pccRequestCount, 1)
        XCTAssertEqual(report.onDeviceRequestCount, 0)
        XCTAssertEqual(report.attestationCount, 1)
        XCTAssertEqual(req.pipelineKind, "tie-cloudboard-apple-com")

        let summary = ReportInsightEngine.summarize(report: report)
        XCTAssertEqual(summary.tone, .pccCloudVerified)
        XCTAssertTrue(summary.detectedFeaturesZh.contains(where: { $0.contains("消除") || $0.contains("Clean Up") }))
        XCTAssertFalse(summary.headlineZh.isEmpty)
        XCTAssertFalse(summary.headlineEn.isEmpty)
        XCTAssertEqual(summary.bullets.count, 4)

        let interp = ReportInsightEngine.interpret(request: req)
        XCTAssertTrue(interp.isVisualOrNonTextTask)
        XCTAssertTrue(interp.featureTitleZh.contains("消除"))
        XCTAssertFalse(interp.narrativeZh.isEmpty)
        XCTAssertFalse(interp.narrativeEn.isEmpty)
        XCTAssertFalse(interp.emptyPromptExplanationZh.isEmpty)
        XCTAssertFalse(interp.privacyGuaranteeZh.isEmpty)
        XCTAssertEqual(interp.clientAppEn, "Photos")
    }

    func testOnDeviceOnlyAndEmptyReportSummaries() throws {
        let onDeviceDict: [String: Any] = [
            "modelRequests": [
                [
                    "timestamp": Date().timeIntervalSince1970,
                    "identifier": "LOCAL-01",
                    "useCase": "WritingTools.Rewrite",
                    "model": "com.apple.fm.ondevice.3b"
                ]
            ],
            "privateCloudComputeRequests": []
        ]
        let onDeviceData = try JSONSerialization.data(withJSONObject: onDeviceDict, options: [])
        let onDeviceReport = try IntelligenceReportDecoder.decode(data: onDeviceData, fileName: "Local.json")
        let onDeviceSummary = ReportInsightEngine.summarize(report: onDeviceReport)
        XCTAssertEqual(onDeviceSummary.tone, .onDevicePure)
        XCTAssertEqual(onDeviceReport.onDeviceRequestCount, 1)
        XCTAssertEqual(onDeviceReport.pccRequestCount, 0)

        let emptyDict: [String: Any] = [
            "modelRequests": [],
            "privateCloudComputeRequests": []
        ]
        let emptyData = try JSONSerialization.data(withJSONObject: emptyDict, options: [])
        let emptyReport = try IntelligenceReportDecoder.decode(data: emptyData, fileName: "Empty.json")
        let emptySummary = ReportInsightEngine.summarize(report: emptyReport)
        XCTAssertEqual(emptySummary.tone, .emptyReport)
        XCTAssertTrue(emptyReport.requests.isEmpty)
    }
}
