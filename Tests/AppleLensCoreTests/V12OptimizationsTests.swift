import AppleLensCore
import CryptoKit
import Foundation
import Security
import XCTest

final class V12OptimizationsTests: XCTestCase {
    // MARK: - Pure Swift DER X.509 Certificate Helper

    private static func makeTestDERCertificate(
        issuerCN: String,
        issuerOrg: String = "Test Issuing Org",
        subjectCN: String,
        subjectOrg: String = "Test Subject Org",
        notBeforeUTC: String = "260101000000Z",
        notAfterUTC: String = "281231235959Z"
    ) -> Data {
        func tlv(_ tag: UInt8, _ bytes: [UInt8]) -> [UInt8] {
            let len = bytes.count
            let lenBytes: [UInt8]
            if len < 128 {
                lenBytes = [UInt8(len)]
            } else if len < 256 {
                lenBytes = [0x81, UInt8(len)]
            } else {
                lenBytes = [0x82, UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]
            }
            return [tag] + lenBytes + bytes
        }

        func seq(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
        func set(_ parts: [UInt8]...) -> [UInt8] { tlv(0x31, parts.flatMap { $0 }) }
        func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }
        func utc(_ s: String) -> [UInt8] { tlv(0x17, Array(s.utf8)) }
        func oid(_ b: [UInt8]) -> [UInt8] { tlv(0x06, b) }
        func rdn(cn: String, org: String) -> [UInt8] {
            seq(
                set(seq(oid([0x55, 0x04, 0x0A]), utf8(org))),
                set(seq(oid([0x55, 0x04, 0x03]), utf8(cn)))
            )
        }

        // ecdsa-with-SHA256 (1.2.840.10045.4.3.2)
        let sigAlg = seq(oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        let key = P256.Signing.PrivateKey()
        // ecPublicKey (1.2.840.10045.2.1) + prime256v1 (1.2.840.10045.3.1.7)
        let spki = seq(
            seq(
                oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]),
                oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
            ),
            tlv(0x03, [0x00] + Array(key.publicKey.x963Representation))
        )

        let tbs = seq(
            tlv(0xA0, tlv(0x02, [0x02])), // X.509 v3
            tlv(0x02, [0x01, 0x02, 0x03, 0x04]),
            sigAlg,
            rdn(cn: issuerCN, org: issuerOrg),
            seq(utc(notBeforeUTC), utc(notAfterUTC)),
            rdn(cn: subjectCN, org: subjectOrg),
            spki
        )
        let sig = (try? key.signature(for: Data(tbs)).derRepresentation) ?? Data()
        return Data(seq(tbs, sigAlg, tlv(0x03, [0x00] + Array(sig))))
    }

    private static func makeTestSecCertificate(
        issuerCN: String,
        issuerOrg: String = "Test Issuing Org",
        subjectCN: String,
        subjectOrg: String = "Test Subject Org"
    ) throws -> SecCertificate {
        let der = makeTestDERCertificate(
            issuerCN: issuerCN,
            issuerOrg: issuerOrg,
            subjectCN: subjectCN,
            subjectOrg: subjectOrg
        )
        return try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData))
    }

    // MARK: - Certificate Chain MitM Audit Tests

    func testAuditCertificateChainDetectsSurgeMitMOnAppleHost() throws {
        let surgeCert = try Self.makeTestSecCertificate(
            issuerCN: "Surge Generated CA",
            issuerOrg: "NSSurge",
            subjectCN: "Surge Generated CA",
            subjectOrg: "NSSurge"
        )
        let singleAudit = RoutingProbeEngine.auditCertificateChain([surgeCert], host: "guzzoni.apple.com")
        XCTAssertTrue(singleAudit.isMitMDetected)
        XCTAssertNotNil(singleAudit.mitmReason)
        XCTAssertEqual(singleAudit.leafSubject, "Surge Generated CA")

        let leafCert = try Self.makeTestSecCertificate(
            issuerCN: "Surge Generated CA",
            issuerOrg: "NSSurge",
            subjectCN: "guzzoni.apple.com",
            subjectOrg: "NSSurge"
        )
        let chainAudit = RoutingProbeEngine.auditCertificateChain([leafCert, surgeCert], host: "guzzoni.apple.com")
        XCTAssertTrue(chainAudit.isMitMDetected)
        XCTAssertEqual(chainAudit.leafSubject, "guzzoni.apple.com")
        XCTAssertEqual(chainAudit.rootSubject, "Surge Generated CA")
        XCTAssertEqual(chainAudit.issuerSummary, "Surge Generated CA")
    }

    func testAuditCertificateChainCleanNonMitMCertOnExternalHost() throws {
        let cleanCert = try Self.makeTestSecCertificate(
            issuerCN: "Example WebPKI Intermediate",
            issuerOrg: "DigiCert Inc",
            subjectCN: "api.example.org",
            subjectOrg: "Example Services"
        )
        let audit = RoutingProbeEngine.auditCertificateChain([cleanCert], host: "api.example.org")
        XCTAssertFalse(audit.isMitMDetected)
        XCTAssertNil(audit.mitmReason)
        XCTAssertEqual(audit.leafSubject, "api.example.org")
        XCTAssertEqual(audit.rootSubject, "api.example.org")
    }

    func testAuditCertificateChainAppleHostUnexpectedIssuerAndEmptyChain() throws {
        let emptyAudit = RoutingProbeEngine.auditCertificateChain([], host: "guzzoni.apple.com")
        XCTAssertFalse(emptyAudit.isMitMDetected)
        XCTAssertNil(emptyAudit.leafSubject)
        XCTAssertNil(emptyAudit.rootSubject)

        let rogueCert = try Self.makeTestSecCertificate(
            issuerCN: "Corp Inspection Root",
            issuerOrg: "Corp IT",
            subjectCN: "ropes.apple.com",
            subjectOrg: "Corp IT"
        )
        let rogueAudit = RoutingProbeEngine.auditCertificateChain([rogueCert], host: "ropes.apple.com")
        XCTAssertTrue(rogueAudit.isMitMDetected)
        XCTAssertNotNil(rogueAudit.mitmReason)

        let appleLeaf = try Self.makeTestSecCertificate(
            issuerCN: "Apple Public EV Server RSA CA",
            issuerOrg: "Apple Inc.",
            subjectCN: "guzzoni.apple.com",
            subjectOrg: "Apple Inc."
        )
        let appleRoot = try Self.makeTestSecCertificate(
            issuerCN: "Apple Root CA",
            issuerOrg: "Apple Inc.",
            subjectCN: "Apple Root CA",
            subjectOrg: "Apple Inc."
        )
        let cleanAppleAudit = RoutingProbeEngine.auditCertificateChain([appleLeaf, appleRoot], host: "guzzoni.apple.com")
        XCTAssertFalse(cleanAppleAudit.isMitMDetected)
        XCTAssertNil(cleanAppleAudit.mitmReason)
    }

    // MARK: - CustomProxyConfig Tests

    func testCustomProxyConfigParseValidInputsAndDisplayString() throws {
        let bareHTTP = try XCTUnwrap(CustomProxyConfig.parse("127.0.0.1:6152"))
        XCTAssertEqual(bareHTTP.scheme, .http)
        XCTAssertEqual(bareHTTP.host, "127.0.0.1")
        XCTAssertEqual(bareHTTP.port, 6152)
        XCTAssertEqual(bareHTTP.displayString, "http://127.0.0.1:6152")

        let bareSOCKS = try XCTUnwrap(CustomProxyConfig.parse("127.0.0.1:1080", defaultScheme: .socks5))
        XCTAssertEqual(bareSOCKS.scheme, .socks5)
        XCTAssertEqual(bareSOCKS.host, "127.0.0.1")
        XCTAssertEqual(bareSOCKS.port, 1080)
        XCTAssertEqual(bareSOCKS.displayString, "socks5://127.0.0.1:1080")

        let explicitHTTP = try XCTUnwrap(CustomProxyConfig.parse("  http://192.168.1.5:7890  "))
        XCTAssertEqual(explicitHTTP.scheme, .http)
        XCTAssertEqual(explicitHTTP.host, "192.168.1.5")
        XCTAssertEqual(explicitHTTP.port, 7890)
        XCTAssertEqual(explicitHTTP.displayString, "http://192.168.1.5:7890")

        let explicitHTTPS = try XCTUnwrap(CustomProxyConfig.parse("https://127.0.0.1:8888/"))
        XCTAssertEqual(explicitHTTPS.scheme, .http)
        XCTAssertEqual(explicitHTTPS.host, "127.0.0.1")
        XCTAssertEqual(explicitHTTPS.port, 8888)

        let explicitSOCKS = try XCTUnwrap(CustomProxyConfig.parse("socks5://localhost:1080"))
        XCTAssertEqual(explicitSOCKS.scheme, .socks5)
        XCTAssertEqual(explicitSOCKS.host, "localhost")
        XCTAssertEqual(explicitSOCKS.port, 1080)
        XCTAssertEqual(explicitSOCKS.displayString, "socks5://localhost:1080")

        let ipv6Proxy = try XCTUnwrap(CustomProxyConfig.parse("[::1]:6153"))
        XCTAssertEqual(ipv6Proxy.scheme, .http)
        XCTAssertEqual(ipv6Proxy.host, "::1")
        XCTAssertEqual(ipv6Proxy.port, 6153)
        XCTAssertEqual(ipv6Proxy.displayString, "http://[::1]:6153")
    }

    func testCustomProxyConfigParseInvalidInputsReturnNil() {
        let invalidCases = [
            "",
            "   ",
            "127.0.0.1",
            "127.0.0.1:0",
            "127.0.0.1:65536",
            "127.0.0.1:-1",
            "127.0.0.1:abc",
            ":6152",
            "ftp://127.0.0.1:21",
            "http://:6152",
            "http://127.0.0.1:6152/path",
            "http://user@127.0.0.1:6152",
            "http://127.0.0.1 :6152"
        ]
        for raw in invalidCases {
            XCTAssertNil(CustomProxyConfig.parse(raw), "Expected nil for invalid proxy input '\(raw)'")
        }
    }

    func testCustomProxyConfigCodableRoundTrip() throws {
        let original = CustomProxyConfig(scheme: .socks5, host: "127.0.0.1", port: 6153)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomProxyConfig.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Cryptographic PCC Certificate Chain Verification Tests

    func testVerifyDERCertificateChainEmptyAndInvalidBytes() {
        let emptyResult = CloudAttestationInspector.verifyDERCertificateChain([])
        XCTAssertFalse(emptyResult.verified)
        XCTAssertFalse(emptyResult.statusZh.isEmpty)
        XCTAssertFalse(emptyResult.statusEn.isEmpty)

        let invalidResult = CloudAttestationInspector.verifyDERCertificateChain([Data([0x30, 0x01, 0xFF, 0x00])])
        XCTAssertFalse(invalidResult.verified)
        XCTAssertFalse(invalidResult.statusZh.isEmpty)
        XCTAssertFalse(invalidResult.statusEn.isEmpty)
    }

    func testVerifyDERCertificateChainUntrustedSelfSignedCert() {
        let der = Self.makeTestDERCertificate(
            issuerCN: "Synthetic Self-Signed CA",
            issuerOrg: "Synthetic Org",
            subjectCN: "pcc-test-node.example.com",
            subjectOrg: "Synthetic Org"
        )
        let result = CloudAttestationInspector.verifyDERCertificateChain([der])
        XCTAssertFalse(result.verified)
        XCTAssertFalse(result.statusZh.isEmpty)
        XCTAssertFalse(result.statusEn.isEmpty)
        XCTAssertTrue(
            result.statusEn.lowercased().contains("self-signed") || result.statusEn.lowercased().contains("untrusted"),
            "Expected descriptive untrusted status, got: \(result.statusEn)"
        )
    }

    func testSampleReportFixtureAttestationSignatureStatus() throws {
        let data = SampleReportFixture.sampleReportJSONData()
        let report = try IntelligenceReportDecoder.decode(data: data, fileName: "Sample.json")
        let attestation = try XCTUnwrap(report.requests.first?.pccRequests.first?.attestation)

        XCTAssertFalse(attestation.signatureChainVerified)
        XCTAssertFalse(attestation.signatureStatus(lang: .zhHans).isEmpty)
        XCTAssertFalse(attestation.signatureStatus(lang: .en).isEmpty)
        XCTAssertNotEqual(attestation.signatureStatus(lang: .zhHans), attestation.signatureStatus(lang: .en))
    }

    // MARK: - DiagnosticReportFormatter Redaction & Markdown Tests

    func testDiagnosticReportFormatterRedactSensitiveText() {
        let sample = """
        Device: Alex's iPhone and 张三的 iPhone (also Alex’s iPad)
        UDID40: e41f3900112244558899aabbccddeeff00112233
        UDIDChip: A1B2C3D4-001234567890001E
        PublicIPv4: 111.34.209.220
        LoopbackIPv4: 127.0.0.1
        PublicIPv6: 2606:4700:4700::1111
        LoopbackIPv6: ::1
        Code: PCC_32033_BLIND_TOKEN_LEAK
        """
        let redacted = DiagnosticReportFormatter.redactSensitiveText(sample)

        XCTAssertTrue(redacted.contains("111.34.*.*"))
        XCTAssertFalse(redacted.contains("111.34.209.220"))

        XCTAssertTrue(redacted.contains("2606:4700:*:*"))
        XCTAssertFalse(redacted.contains("2606:4700:4700::1111"))

        XCTAssertTrue(redacted.contains("<REDACTED-UDID>"))
        XCTAssertFalse(redacted.contains("e41f3900112244558899aabbccddeeff00112233"))
        XCTAssertFalse(redacted.contains("A1B2C3D4-001234567890001E"))

        XCTAssertTrue(redacted.contains("USB iPhone"))
        XCTAssertFalse(redacted.contains("Alex's iPhone"))
        XCTAssertFalse(redacted.contains("张三的 iPhone"))
        XCTAssertFalse(redacted.contains("Alex’s iPad"))

        XCTAssertTrue(redacted.contains("127.0.0.1"))
        XCTAssertTrue(redacted.contains("::1"))
        XCTAssertTrue(redacted.contains("PCC_32033_BLIND_TOKEN_LEAK"))
    }

    func testDiagnosticReportFormatterFormatProbeMarkdown() {
        let report = FullProbeReport(
            ranAt: Date(timeIntervalSince1970: 1_763_217_819),
            exitLanes: [
                ExitRegionLaneResult(
                    id: "direct",
                    titleZh: "国内直连通道",
                    titleEn: "Domestic Direct Lane",
                    reachable: true,
                    latencyMs: 42,
                    countryCode: "CN",
                    coloCode: "SHA",
                    ipAddress: "111.34.209.220",
                    probedHost: "www.visa.cn",
                    verdictLevel: .pass,
                    verdictZh: "直连正常",
                    verdictEn: "Healthy DIRECT"
                ),
                ExitRegionLaneResult(
                    id: "openai",
                    titleZh: "OpenAI 出口",
                    titleEn: "OpenAI Exit",
                    reachable: true,
                    latencyMs: 180,
                    countryCode: "US",
                    coloCode: "LAX",
                    ipAddress: "2606:4700:4700::1111",
                    probedHost: "chatgpt.com",
                    verdictLevel: .pass,
                    verdictZh: "美区节点",
                    verdictEn: "US exit"
                )
            ],
            siriAudit: SiriDNSAuditResult(
                guzzoniResolvedIPs: ["17.253.14.125"],
                siriResolvedIPs: ["17.253.14.126"],
                isGuzzoniFakeIP: false,
                isSiriFakeIP: false,
                systemProxyEnabled: true,
                exceptionsIncludeGuzzoni: true
            ),
            endpointProbes: [
                EndpointTLSProbeResult(
                    id: "guzzoni.apple.com",
                    host: "guzzoni.apple.com",
                    roleZh: "中文 Siri 核心",
                    roleEn: "Mandarin Siri Core",
                    expectDirect: true,
                    pinningSensitive: true,
                    reachable: true,
                    httpStatus: 200,
                    latencyMs: 55,
                    leafSubject: "guzzoni.apple.com",
                    issuerSummary: "Apple Public EV",
                    rootSubject: "Apple Root CA",
                    isMitMDetected: false,
                    mitmReason: nil,
                    errorDescription: nil
                )
            ],
            quicProbes: [
                QUICProbeResult(
                    id: "cp4.cloudflare.com:443",
                    host: "cp4.cloudflare.com",
                    port: 443,
                    succeeded: true,
                    latencyMs: 65,
                    detailZh: "QUIC 畅通",
                    detailEn: "QUIC healthy"
                )
            ]
        )

        let mdEn = DiagnosticReportFormatter.formatProbeMarkdown(
            report,
            customProxySummary: "http://127.0.0.1:6152",
            lang: .en
        )
        XCTAssertTrue(mdEn.contains("# AppleLens Redacted Routing & TLS Probe Report"))
        XCTAssertTrue(mdEn.contains("http://127.0.0.1:6152"))
        XCTAssertTrue(mdEn.contains("111.34.*.*"))
        XCTAssertFalse(mdEn.contains("111.34.209.220"))
        XCTAssertTrue(mdEn.contains("2606:4700:*:*"))
        XCTAssertFalse(mdEn.contains("2606:4700:4700::1111"))
        XCTAssertTrue(mdEn.contains("17.253.*.*"))
        XCTAssertFalse(mdEn.contains("17.253.14.125"))
        XCTAssertTrue(mdEn.contains("guzzoni.apple.com"))
        XCTAssertTrue(mdEn.contains("cp4.cloudflare.com"))

        let mdZh = DiagnosticReportFormatter.formatProbeMarkdown(
            report,
            customProxySummary: nil,
            lang: .zhHans
        )
        XCTAssertTrue(mdZh.contains("# AppleLens 路由与证书脱敏探测报告"))
        XCTAssertTrue(mdZh.contains("111.34.*.*"))
    }

    func testDiagnosticReportFormatterFormatDiagnosticsMarkdown() throws {
        let finding = try XCTUnwrap(
            DiagnosticTranslator.translate(
                line: "Token request to inference.issuer.apple.com from 111.34.209.220 (Alex's iPhone, udid=e41f3900112244558899aabbccddeeff00112233) failed with Code=32033",
                process: "privatecloudcomputed",
                subsystem: "com.apple.PrivateCloudCompute",
                sourceDevice: "Alex's iPhone"
            )
        )

        let md = DiagnosticReportFormatter.formatDiagnosticsMarkdown(
            findings: [finding],
            targetLabel: "张三的 iPhone",
            lang: .en
        )
        XCTAssertTrue(md.contains("PCC_32033_BLIND_TOKEN_LEAK"))
        XCTAssertTrue(md.contains("111.34.*.*"))
        XCTAssertTrue(md.contains("<REDACTED-UDID>"))
        XCTAssertTrue(md.contains("USB iPhone"))
        XCTAssertFalse(md.contains("111.34.209.220"))
        XCTAssertFalse(md.contains("e41f3900112244558899aabbccddeeff00112233"))
        XCTAssertFalse(md.contains("Alex's iPhone"))
        XCTAssertFalse(md.contains("张三的 iPhone"))

        let emptyMD = DiagnosticReportFormatter.formatDiagnosticsMarkdown(
            findings: [],
            targetLabel: "This Mac",
            lang: .zhHans
        )
        XCTAssertTrue(emptyMD.contains("AppleLens 脱敏日志诊断单"))
    }

    // MARK: - TriStateRadarCoordinator v1.2.0 State & Adaptive Polling Tests

    @MainActor
    func testTriStateRadarCoordinatorTrustAndUntrustProcess() throws {
        let suiteName = "com.kianuni.AppleLensTests.radarTrust.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tracker = FirstSeenProcessTracker(defaults: defaults)
        let radar = TriStateRadarCoordinator(tracker: tracker)
        XCTAssertTrue(radar.trustedProcessKeys.isEmpty)

        radar.trustProcess(identityKey: "com.example.Beta")
        radar.trustProcess(identityKey: "com.example.Alpha")
        XCTAssertEqual(radar.trustedProcessKeys, ["com.example.Alpha", "com.example.Beta"])

        radar.untrustProcess(identityKey: "com.example.Alpha")
        XCTAssertEqual(radar.trustedProcessKeys, ["com.example.Beta"])

        let reloadedTracker = FirstSeenProcessTracker(defaults: defaults)
        let reloadedRadar = TriStateRadarCoordinator(tracker: reloadedTracker)
        XCTAssertEqual(reloadedRadar.trustedProcessKeys, ["com.example.Beta"])
    }

    @MainActor
    func testTriStateRadarCoordinatorSystemSleepAndWake() async throws {
        let suiteName = "com.kianuni.AppleLensTests.radarSleep.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let radar = TriStateRadarCoordinator(tracker: FirstSeenProcessTracker(defaults: defaults))
        XCTAssertFalse(radar.isPausedForSystemSleep)
        XCTAssertEqual(radar.currentPollIntervalSeconds, 1.5, accuracy: 0.001)

        radar.setSystemSleeping(true)
        XCTAssertTrue(radar.isPausedForSystemSleep)

        radar.setSystemSleeping(false)
        XCTAssertFalse(radar.isPausedForSystemSleep)
        XCTAssertEqual(radar.currentPollIntervalSeconds, 1.5, accuracy: 0.001)
        await Task.yield()
    }

    @MainActor
    func testTriStateRadarCoordinatorUIVisibilityAndIntervalReset() throws {
        let suiteName = "com.kianuni.AppleLensTests.radarVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let radar = TriStateRadarCoordinator(tracker: FirstSeenProcessTracker(defaults: defaults))
        XCTAssertEqual(radar.currentPollIntervalSeconds, 1.5, accuracy: 0.001)

        // Hiding UI does not immediately back off before the 60s continuous-idle threshold.
        radar.setUIVisible(false)
        XCTAssertEqual(radar.currentPollIntervalSeconds, 1.5, accuracy: 0.001)

        // Showing UI always resets back to the active polling interval.
        radar.setUIVisible(true)
        XCTAssertEqual(radar.currentPollIntervalSeconds, 1.5, accuracy: 0.001)
    }

    // MARK: - Lock-Free UserDefaults Persistence Round-Trip Tests

    func testFirstSeenProcessTrackerLockFreePersistenceRoundTrip() async throws {
        let suiteName = "com.kianuni.AppleLensTests.trackerLockFree.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tracker = FirstSeenProcessTracker(defaults: defaults)

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<16 {
                group.addTask {
                    let key = "com.example.worker.\(idx % 4)"
                    tracker.trust(key)
                    if idx.isMultiple(of: 2) {
                        tracker.untrust(key)
                    }
                    _ = tracker.isTrusted(key)
                }
            }
        }

        tracker.trust("com.example.FinalTrusted")
        tracker.trust("com.example.Transient")
        tracker.untrust("com.example.Transient")

        let expected = tracker.allTrustedKeys()
        XCTAssertTrue(expected.contains("com.example.FinalTrusted"))
        XCTAssertFalse(expected.contains("com.example.Transient"))

        let reloaded = FirstSeenProcessTracker(defaults: defaults)
        XCTAssertEqual(reloaded.allTrustedKeys(), expected)
        XCTAssertTrue(reloaded.isTrusted("com.example.FinalTrusted"))
        XCTAssertFalse(reloaded.isTrusted("com.example.Transient"))
    }

    func testLanguageManagerLockFreePersistenceRoundTrip() async throws {
        let suiteName = "com.kianuni.AppleLensTests.langLockFree.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = LanguageManager(defaults: defaults)
        manager.current = .en
        XCTAssertEqual(LanguageManager(defaults: defaults).current, .en)

        manager.current = .zhHans
        XCTAssertEqual(LanguageManager(defaults: defaults).current, .zhHans)

        manager.toggle()
        XCTAssertEqual(manager.current, .en)
        XCTAssertEqual(LanguageManager(defaults: defaults).current, .en)

        await withTaskGroup(of: Void.self) { group in
            for idx in 0..<16 {
                group.addTask {
                    if idx.isMultiple(of: 2) {
                        manager.current = (idx % 4 == 0) ? .zhHans : .en
                    } else {
                        manager.toggle()
                    }
                }
            }
        }

        let finalLang = manager.current
        let reloaded = LanguageManager(defaults: defaults)
        XCTAssertEqual(reloaded.current, finalLang)
    }

    // MARK: - UnifiedLogStreamService Chunked Streaming Test

    func testUnifiedLogStreamServiceParseNDJSONStreamBoundedTailWindow() throws {
        let pipe = Pipe()
        let writeHandle = pipe.fileHandleForWriting
        let readHandle = pipe.fileHandleForReading

        var lines: [String] = []
        for idx in 1...8 {
            lines.append(#"{"timestamp":"2026-11-16 14:20:0\#(idx).000000+0800","processImagePath":"/usr/libexec/assistantd","processID":\#(idx),"subsystem":"com.apple.siri","eventMessage":"Event \#(idx)"}"#)
            if idx == 3 {
                lines.append("{malformed-json-chunk")
            }
        }
        let payload = Data((lines.joined(separator: "\n") + "\n").utf8)
        try writeHandle.write(contentsOf: payload)
        try writeHandle.close()

        let events = try UnifiedLogStreamService.parseNDJSONStream(
            from: readHandle,
            sourceDevice: "This Mac",
            maxEvents: 3,
            chunkSize: 19
        )
        try readHandle.close()

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.processID), [6, 7, 8])
        XCTAssertEqual(events.map(\.message), ["Event 6", "Event 7", "Event 8"])
    }
}
