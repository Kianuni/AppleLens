import CryptoKit
import Foundation
import Security

public struct X509CertificateSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String // SHA-256 fingerprint
    public let indexInChain: Int
    public let subjectSummary: String
    public let commonName: String
    public let organization: String
    public let issuerSummary: String
    public let notBefore: Date?
    public let notAfter: Date?
    public let publicKeyAlgorithm: String
    public let sha256Fingerprint: String

    public var isCurrentlyValid: Bool {
        let now = Date()
        if let nb = notBefore, now < nb { return false }
        if let na = notAfter, now > na { return false }
        return true
    }

    public var isAppleAnchored: Bool {
        let combined = "\(subjectSummary) \(organization) \(issuerSummary)".lowercased()
        return combined.contains("apple")
    }
}

public struct SealedHashSlotSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let slotName: String
    public let hashAlgorithm: String
    public let entryCount: Int
    public let entryDigestsHex: [String]
    public let cryptexManifestCount: Int
    public let secureConfigsJSON: [String]
}

public struct DecodedCloudAttestation: Hashable, Codable, Sendable {
    public let rawBundleByteCount: Int
    public let sepAttestationBytes: Int
    public let sepAttestationSHA256: String?
    public let apTicketBytes: Int
    public let apTicketHasIM4MMagic: Bool
    public let apTicketSHA256: String?
    public let sealedHashSlots: [SealedHashSlotSummary]
    public let certificateChain: [X509CertificateSummary]
    public let appDataVersion: UInt64?
    public let appDataDomain: String?
    public let appDataName: String?
    public let keyExpiration: Date?
    public let hasTransparencyProof: Bool
    public let transparencyProofBytes: Int
    public let transparencyProofSHA256: String?
    public let parseNotes: [String]
    public let signatureChainVerified: Bool
    public let signatureStatusZh: String
    public let signatureStatusEn: String

    public init(
        rawBundleByteCount: Int,
        sepAttestationBytes: Int,
        sepAttestationSHA256: String?,
        apTicketBytes: Int,
        apTicketHasIM4MMagic: Bool,
        apTicketSHA256: String?,
        sealedHashSlots: [SealedHashSlotSummary],
        certificateChain: [X509CertificateSummary],
        appDataVersion: UInt64?,
        appDataDomain: String?,
        appDataName: String?,
        keyExpiration: Date?,
        hasTransparencyProof: Bool,
        transparencyProofBytes: Int,
        transparencyProofSHA256: String?,
        parseNotes: [String],
        signatureChainVerified: Bool = false,
        signatureStatusZh: String = "未验证证书链",
        signatureStatusEn: String = "Certificate chain not verified"
    ) {
        self.rawBundleByteCount = rawBundleByteCount
        self.sepAttestationBytes = sepAttestationBytes
        self.sepAttestationSHA256 = sepAttestationSHA256
        self.apTicketBytes = apTicketBytes
        self.apTicketHasIM4MMagic = apTicketHasIM4MMagic
        self.apTicketSHA256 = apTicketSHA256
        self.sealedHashSlots = sealedHashSlots
        self.certificateChain = certificateChain
        self.appDataVersion = appDataVersion
        self.appDataDomain = appDataDomain
        self.appDataName = appDataName
        self.keyExpiration = keyExpiration
        self.hasTransparencyProof = hasTransparencyProof
        self.transparencyProofBytes = transparencyProofBytes
        self.transparencyProofSHA256 = transparencyProofSHA256
        self.parseNotes = parseNotes
        self.signatureChainVerified = signatureChainVerified
        self.signatureStatusZh = signatureStatusZh
        self.signatureStatusEn = signatureStatusEn
    }

    public func signatureStatus(lang: AppLanguage) -> String {
        tr(signatureStatusZh, signatureStatusEn, lang: lang)
    }

    public var nodeRoleLabelZh: String {
        let name = (appDataName ?? "").lowercased()
        if name.contains("tie") || name.contains("proxy") {
            return "PCC TIE 接入代理节点 (\(appDataName ?? ""))"
        } else if !name.isEmpty {
            return "PCC 推理计算节点 (\(appDataName ?? ""))"
        }
        return "PCC 安全 enclave 节点"
    }

    public var nodeRoleLabelEn: String {
        let name = (appDataName ?? "").lowercased()
        if name.contains("tie") || name.contains("proxy") {
            return "PCC TIE Proxy Node (\(appDataName ?? ""))"
        } else if !name.isEmpty {
            return "PCC Inference Node (\(appDataName ?? ""))"
        }
        return "PCC Secure Enclave Node"
    }
}

/// Zero-dependency native decoder for Apple PCC `AttestationBundle` Protobuf + X.509 certificate chains.
public enum CloudAttestationInspector {
    /// Decodes an arbitrary JSON value representing an attestation (Base64 Protobuf string, PEM/JSON wrapper dict, or nested bundle).
    public static func decodeAnyAttestation(_ value: Any) -> DecodedCloudAttestation? {
        if let str = value as? String {
            return decodeBase64Bundle(str)
        }
        if let dict = value as? [String: Any] {
            let nestedStringKeys = ["attestationBundle", "bundle", "attestation", "attestationData", "data", "rawBundle"]
            for key in nestedStringKeys {
                if let nestedStr = dict[key] as? String,
                   let decoded = decodeBase64Bundle(nestedStr) {
                    return decoded
                }
            }
            return decodeJSONAttestationDict(dict, rawByteCount: nil)
        }
        return nil
    }

    public static func decodeBase64Bundle(_ base64String: String) -> DecodedCloudAttestation? {
        guard let rawData = decodeBase64Data(base64String), !rawData.isEmpty else {
            return nil
        }

        // First check if the blob is JSON rather than Protobuf
        if rawData.first == UInt8(ascii: "{") {
            if let jsonDict = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                return decodeJSONAttestationDict(jsonDict, rawByteCount: rawData.count)
            }
            let emptySig = verifyDERCertificateChain([])
            return DecodedCloudAttestation(
                rawBundleByteCount: rawData.count,
                sepAttestationBytes: 0,
                sepAttestationSHA256: nil,
                apTicketBytes: 0,
                apTicketHasIM4MMagic: false,
                apTicketSHA256: nil,
                sealedHashSlots: [],
                certificateChain: [],
                appDataVersion: nil,
                appDataDomain: nil,
                appDataName: nil,
                keyExpiration: nil,
                hasTransparencyProof: false,
                transparencyProofBytes: 0,
                transparencyProofSHA256: nil,
                parseNotes: ["JSON-wrapped attestation blob (\(rawData.count) bytes)"],
                signatureChainVerified: emptySig.verified,
                signatureStatusZh: emptySig.statusZh,
                signatureStatusEn: emptySig.statusEn
            )
        }

        guard let fields = try? ProtobufWireDecoder.decodeFields(from: rawData) else {
            return nil
        }

        var sepBytes = 0
        var sepSHA: String?
        var apBytes = 0
        var apHasIM4M = false
        var apSHA: String?
        var slots: [SealedHashSlotSummary] = []
        var certs: [X509CertificateSummary] = []
        var derCerts: [Data] = []
        var appVersion: UInt64?
        var appDomain: String?
        var appName: String?
        var keyExpiration: Date?
        var tpBytes = 0
        var tpSHA: String?
        var notes: [String] = []

        for field in fields {
            switch field.number {
            case 1: // sep_attestation
                if let d = field.value.asData {
                    sepBytes = d.count
                    sepSHA = sha256Hex(d)
                }
            case 2: // ap_ticket (Image4 IM4M manifest)
                if let d = field.value.asData {
                    apBytes = d.count
                    apSHA = sha256Hex(d)
                    apHasIM4M = d.range(of: Data("IM4M".utf8)) != nil
                }
            case 3: // sealed_hashes (SealedHashLedger)
                if let ledgerFields = field.value.asSubmessageFields {
                    for entryField in ledgerFields where entryField.number == 1 {
                        if let parsedSlot = parseSealedHashMapEntry(entryField.value.asData) {
                            slots.append(parsedSlot)
                        }
                    }
                }
            case 4: // provisioning_certificate_chain (repeated DER X.509)
                if let der = field.value.asData {
                    derCerts.append(der)
                    let idx = certs.count
                    if let parsedCert = parseDERCertificate(der, index: idx) {
                        certs.append(parsedCert)
                    } else {
                        notes.append("Failed to parse DER cert #\(idx) (\(der.count) bytes)")
                    }
                }
            case 5: // app_data (AppData)
                if let appDataRaw = field.value.asData,
                   let appFields = try? ProtobufWireDecoder.decodeFields(from: appDataRaw) {
                    for af in appFields {
                        if af.number == 1 { appVersion = af.value.asUInt64 }
                        if af.number == 2 { appDomain = af.value.asString }
                        if af.number == 3 { appName = af.value.asString }
                    }
                }
            case 6: // key_expiration (google.protobuf.Timestamp)
                if let tsData = field.value.asData {
                    keyExpiration = ProtobufWireDecoder.decodeTimestamp(tsData)
                }
            case 8: // transparency_proofs (TransparencyProofs -> ATLogProofs)
                if let tpData = field.value.asData {
                    tpBytes = tpData.count
                    tpSHA = sha256Hex(tpData)
                }
            default:
                break
            }
        }

        let sigResult = verifyDERCertificateChain(derCerts)
        return DecodedCloudAttestation(
            rawBundleByteCount: rawData.count,
            sepAttestationBytes: sepBytes,
            sepAttestationSHA256: sepSHA,
            apTicketBytes: apBytes,
            apTicketHasIM4MMagic: apHasIM4M,
            apTicketSHA256: apSHA,
            sealedHashSlots: slots,
            certificateChain: certs,
            appDataVersion: appVersion,
            appDataDomain: appDomain,
            appDataName: appName,
            keyExpiration: keyExpiration,
            hasTransparencyProof: tpBytes > 0,
            transparencyProofBytes: tpBytes,
            transparencyProofSHA256: tpSHA,
            parseNotes: notes,
            signatureChainVerified: sigResult.verified,
            signatureStatusZh: sigResult.statusZh,
            signatureStatusEn: sigResult.statusEn
        )
    }

    private static func parseSealedHashMapEntry(_ data: Data?) -> SealedHashSlotSummary? {
        guard let data, let mapFields = try? ProtobufWireDecoder.decodeFields(from: data) else {
            return nil
        }
        var slotName = "slot"
        var hashAlg = "UNKNOWN"
        var digests: [String] = []
        var cryptexCount = 0
        var secureConfigs: [String] = []

        for mf in mapFields {
            if mf.number == 1, let s = mf.value.asString {
                slotName = s
            } else if mf.number == 2, let shFields = mf.value.asSubmessageFields {
                for shf in shFields {
                    if shf.number == 1, let alg = shf.value.asUInt64 {
                        hashAlg = alg == 1 ? "SHA-256" : (alg == 2 ? "SHA-384" : "Alg(\(alg))")
                    } else if shf.number == 2, let entryFields = shf.value.asSubmessageFields {
                        for ef in entryFields {
                            if ef.number == 2, let dig = ef.value.asData {
                                digests.append(dig.map { String(format: "%02x", $0) }.joined())
                            } else if ef.number == 3 {
                                cryptexCount += 1
                            } else if ef.number == 5, let scFields = ef.value.asSubmessageFields {
                                for scf in scFields where scf.number == 1 {
                                    if let jsonStr = scf.value.asString {
                                        secureConfigs.append(prettyPrintJSONIfPossible(jsonStr))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return SealedHashSlotSummary(
            id: "\(slotName)-\(digests.first ?? UUID().uuidString)",
            slotName: slotName,
            hashAlgorithm: hashAlg,
            entryCount: digests.count,
            entryDigestsHex: digests,
            cryptexManifestCount: cryptexCount,
            secureConfigsJSON: secureConfigs
        )
    }

    /// Performs real cryptographic X.509 signature-chain verification via macOS `SecTrust`,
    /// evaluating at `referenceDate` (or a date within the leaf certificate's validity window for
    /// historical exported reports) and requiring an Apple Root CA anchor.
    public static func verifyDERCertificateChain(
        _ derCerts: [Data],
        referenceDate: Date? = nil
    ) -> (verified: Bool, statusZh: String, statusEn: String) {
        guard !derCerts.isEmpty else {
            return (false, "无 X.509 证书链", "No X.509 certificate chain")
        }

        let secCerts = derCerts.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !secCerts.isEmpty else {
            return (false, "DER X.509 证书解析失败", "Failed to parse DER X.509 certificates")
        }

        let policy = SecPolicyCreateBasicX509()
        var optionalTrust: SecTrust?
        let createStatus = SecTrustCreateWithCertificates(secCerts as CFArray, policy, &optionalTrust)
        guard createStatus == errSecSuccess, let trust = optionalTrust else {
            return (
                false,
                "SecTrust 初始化失败 (OSStatus \(createStatus))",
                "Failed to initialize SecTrust (OSStatus \(createStatus))"
            )
        }

        if let verifyDate = referenceDate ?? historicalVerifyDate(forLeaf: secCerts[0]) {
            _ = SecTrustSetVerifyDate(trust, verifyDate as CFDate)
        }

        var cfError: CFError?
        let trustPassed = SecTrustEvaluateWithError(trust, &cfError)
        let evaluatedChain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? secCerts

        if trustPassed {
            if let root = evaluatedChain.last, isAppleRootCA(root) {
                let rootName = certificateCommonName(root)
                    ?? (SecCertificateCopySubjectSummary(root) as String?)
                    ?? "Apple Root CA"
                return (
                    true,
                    "SecTrust 加密签名链已验证（锚定 \(rootName)）",
                    "Cryptographic signature chain verified (anchored to \(rootName))"
                )
            }
            let rootName = evaluatedChain.last.flatMap {
                certificateCommonName($0) ?? (SecCertificateCopySubjectSummary($0) as String?)
            } ?? "Unknown Root"
            return (
                false,
                "证书链虽受系统信任但根证书非 Apple Root CA（\(rootName)）",
                "Chain trusted by system, but root anchor is not an Apple Root CA (\(rootName))"
            )
        }

        let errDesc = cfError.map { ($0 as Error).localizedDescription } ?? ""
        let errCode = cfError.map { CFErrorGetCode($0) }
        let isExpired = (errCode == Int(errSecCertificateExpired))
            || errDesc.lowercased().contains("expired")
        if isExpired {
            let detail = errDesc.isEmpty ? "expired" : errDesc
            return (
                false,
                "证书在验证时间窗内已过期（\(detail)）",
                "Certificate expired for verification date (\(detail))"
            )
        }

        if isSelfSignedSingleCert(secCerts) {
            return (
                false,
                "自签名证书未受信任（未经 Apple Root CA 签发验证）",
                "Untrusted self-signed certificate (not anchored to Apple Root CA)"
            )
        }

        let detailZh = errDesc.isEmpty ? "SecTrust 校验未通过" : errDesc
        let detailEn = errDesc.isEmpty ? "SecTrust evaluation failed" : errDesc
        return (
            false,
            "证书签名链未受信任或缺少 Apple Root CA（\(detailZh)）",
            "Untrusted or incomplete certificate chain (\(detailEn))"
        )
    }

    private struct CertificateMetadata {
        var commonName: String
        var organization: String
        var issuerParts: [String]
        var notBefore: Date?
        var notAfter: Date?
        var publicKeyAlgorithm: String
    }

    private static func extractCertificateMetadata(_ cert: SecCertificate, fallbackSubject: String) -> CertificateMetadata {
        var meta = CertificateMetadata(
            commonName: fallbackSubject,
            organization: "",
            issuerParts: [],
            notBefore: nil,
            notAfter: nil,
            publicKeyAlgorithm: "X.509"
        )

        if let values = SecCertificateCopyValues(cert, nil, nil) as? [String: [String: Any]] {
            if let cnArr = values["2.5.4.3"]?["value"] as? [String], let firstCN = cnArr.first {
                meta.commonName = firstCN
            }
            if let subjectSec = values["2.16.840.1.113741.2.1.1.1.8"]?["value"] as? [[String: Any]] {
                for item in subjectSec {
                    if (item["label"] as? String) == "2.5.4.10", let org = item["value"] as? String {
                        meta.organization = org
                    }
                }
            }
            if let issuerSec = values["2.16.840.1.113741.2.1.1.1.5"]?["value"] as? [[String: Any]] {
                for item in issuerSec {
                    if let val = item["value"] as? String {
                        meta.issuerParts.append(val)
                    }
                }
            }
            if let nbRef = values["2.16.840.1.113741.2.1.1.1.6"]?["value"] as? NSNumber {
                meta.notBefore = Date(timeIntervalSinceReferenceDate: nbRef.doubleValue)
            }
            if let naRef = values["2.16.840.1.113741.2.1.1.1.7"]?["value"] as? NSNumber {
                meta.notAfter = Date(timeIntervalSinceReferenceDate: naRef.doubleValue)
            }
            if let algSec = values["2.16.840.1.113741.2.1.1.1.9"]?["value"] as? [[String: Any]] {
                for item in algSec where (item["label"] as? String) == "Algorithm" {
                    if let oid = item["value"] as? String {
                        if oid == "1.2.840.10045.2.1" { meta.publicKeyAlgorithm = "ECDSA (P-256 / P-384)" }
                        else if oid == "1.2.840.113549.1.1.1" { meta.publicKeyAlgorithm = "RSA" }
                        else { meta.publicKeyAlgorithm = oid }
                    }
                }
            }
        }
        return meta
    }

    private static func certificateCommonName(_ cert: SecCertificate) -> String? {
        var cfCN: CFString?
        guard SecCertificateCopyCommonName(cert, &cfCN) == errSecSuccess,
              let cn = cfCN as String?,
              !cn.isEmpty else {
            return nil
        }
        return cn
    }

    private static func historicalVerifyDate(forLeaf leaf: SecCertificate) -> Date? {
        let summary = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
        let meta = extractCertificateMetadata(leaf, fallbackSubject: summary)
        if let nb = meta.notBefore, let na = meta.notAfter {
            guard nb <= na else { return nb }
            let span = na.timeIntervalSince(nb)
            return span >= 60 ? nb.addingTimeInterval(60) : nb.addingTimeInterval(span * 0.5)
        }
        if let nb = meta.notBefore {
            return nb.addingTimeInterval(60)
        }
        if let na = meta.notAfter {
            return na.addingTimeInterval(-60)
        }
        return nil
    }

    private static func isSelfSignedSingleCert(_ certs: [SecCertificate]) -> Bool {
        guard certs.count == 1,
              let normSubject = SecCertificateCopyNormalizedSubjectSequence(certs[0]) as Data?,
              let normIssuer = SecCertificateCopyNormalizedIssuerSequence(certs[0]) as Data? else {
            return false
        }
        return normSubject == normIssuer
    }

    private static func isAppleRootCA(_ cert: SecCertificate) -> Bool {
        let summary = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
        let meta = extractCertificateMetadata(cert, fallbackSubject: summary)
        let cnFromAPI = certificateCommonName(cert) ?? ""
        let combined = "\(summary) \(meta.commonName) \(cnFromAPI)".lowercased()
        if combined.contains("apple root") {
            return true
        }
        if combined.contains("apple") && (combined.contains("root") || combined.contains("certification authority")) {
            if let normSubject = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?,
               let normIssuer = SecCertificateCopyNormalizedIssuerSequence(cert) as Data? {
                return normSubject == normIssuer
            }
            return true
        }
        return false
    }

    public static func parseDERCertificate(_ derData: Data, index: Int) -> X509CertificateSummary? {
        guard let cert = SecCertificateCreateWithData(nil, derData as CFData) else {
            return nil
        }
        let subjectSummary = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Certificate #\(index)"
        let fingerprint = sha256Hex(derData)
        let meta = extractCertificateMetadata(cert, fallbackSubject: subjectSummary)

        return X509CertificateSummary(
            id: fingerprint,
            indexInChain: index,
            subjectSummary: subjectSummary,
            commonName: meta.commonName,
            organization: meta.organization,
            issuerSummary: meta.issuerParts.isEmpty ? "Unknown Issuer" : meta.issuerParts.joined(separator: " / "),
            notBefore: meta.notBefore,
            notAfter: meta.notAfter,
            publicKeyAlgorithm: meta.publicKeyAlgorithm,
            sha256Fingerprint: fingerprint
        )
    }

    private static func decodeJSONAttestationDict(_ dict: [String: Any], rawByteCount: Int?) -> DecodedCloudAttestation? {
        let certArrayKeys = ["certificateChain", "provisioningCertificateChain", "certificates", "certChain"]
        var certs: [X509CertificateSummary] = []
        var derCerts: [Data] = []
        var notes: [String] = []

        for key in certArrayKeys {
            if let arr = dict[key] as? [Any] {
                for item in arr {
                    let candidateStr: String?
                    if let s = item as? String {
                        candidateStr = s
                    } else if let d = item as? [String: Any] {
                        candidateStr = (d["der"] as? String) ?? (d["certificate"] as? String) ?? (d["data"] as? String)
                    } else {
                        candidateStr = nil
                    }
                    if let str = candidateStr, let der = decodeBase64Data(str) {
                        derCerts.append(der)
                        let idx = certs.count
                        if let parsed = parseDERCertificate(der, index: idx) {
                            certs.append(parsed)
                        } else {
                            notes.append("Failed to parse JSON DER cert #\(idx) (\(der.count) bytes)")
                        }
                    }
                }
            }
        }

        let sepData = (dict["sepAttestation"] as? String).flatMap(decodeBase64Data)
            ?? (dict["sep_attestation"] as? String).flatMap(decodeBase64Data)
        let apData = (dict["apTicket"] as? String).flatMap(decodeBase64Data)
            ?? (dict["ap_ticket"] as? String).flatMap(decodeBase64Data)
        let tpData = (dict["transparencyProof"] as? String).flatMap(decodeBase64Data)
            ?? (dict["transparency_proof"] as? String).flatMap(decodeBase64Data)

        let appName = (dict["nodeIdentifier"] as? String)
            ?? (dict["nodeId"] as? String)
            ?? (dict["pipelineKind"] as? String)
            ?? (dict["name"] as? String)
            ?? (dict["node"] as? String)
        let appDomain = (dict["appDataDomain"] as? String)
            ?? (dict["domain"] as? String)

        let estimatedBytes: Int
        if let rawByteCount {
            estimatedBytes = rawByteCount
        } else if let serialized = try? JSONSerialization.data(withJSONObject: dict) {
            estimatedBytes = serialized.count
        } else {
            estimatedBytes = 0
        }

        let sortedKeys = dict.keys.sorted().joined(separator: ", ")
        notes.append("JSON attestation structure (\(estimatedBytes) bytes, keys: \(sortedKeys))")

        let apHasIM4M = apData?.range(of: Data("IM4M".utf8)) != nil
        let sigResult = verifyDERCertificateChain(derCerts)
        return DecodedCloudAttestation(
            rawBundleByteCount: estimatedBytes,
            sepAttestationBytes: sepData?.count ?? 0,
            sepAttestationSHA256: sepData.map(sha256Hex),
            apTicketBytes: apData?.count ?? 0,
            apTicketHasIM4MMagic: apHasIM4M,
            apTicketSHA256: apData.map(sha256Hex),
            sealedHashSlots: [],
            certificateChain: certs,
            appDataVersion: (dict["version"] as? NSNumber)?.uint64Value,
            appDataDomain: appDomain,
            appDataName: appName,
            keyExpiration: nil,
            hasTransparencyProof: (tpData?.count ?? 0) > 0,
            transparencyProofBytes: tpData?.count ?? 0,
            transparencyProofSHA256: tpData.map(sha256Hex),
            parseNotes: notes,
            signatureChainVerified: sigResult.verified,
            signatureStatusZh: sigResult.statusZh,
            signatureStatusEn: sigResult.statusEn
        )
    }

    private static func decodeBase64Data(_ input: String) -> Data? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("-----BEGIN") {
            let stripped = text
                .components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("-----") }
                .joined()
            text = stripped
        }
        let cleaned = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padLen = (4 - (cleaned.count % 4)) % 4
        let padded = cleaned + String(repeating: "=", count: padLen)
        return Data(base64Encoded: padded, options: .ignoreUnknownCharacters)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func prettyPrintJSONIfPossible(_ raw: String) -> String {
        guard let d = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return s
    }
}
