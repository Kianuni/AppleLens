import CryptoKit
import Foundation

public enum ReportDecodeError: Error, LocalizedError {
    case invalidJSONRoot
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .invalidJSONRoot: return "JSON root is neither an object nor an array."
        case .unreadableFile: return "Unable to read report JSON data."
        }
    }
}

public enum IntelligenceReportDecoder {
    public static func decodeFile(at url: URL) throws -> ParsedAppleIntelligenceReport {
        let data = try Data(contentsOf: url)
        return try decode(data: data, fileName: url.lastPathComponent)
    }

    public static func decode(data: Data, fileName: String = "Apple_Intelligence_Report.json") throws -> ParsedAppleIntelligenceReport {
        let rawObj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        var rawRequests: [[String: Any]] = []
        var topLevelPCCRequests: [[String: Any]] = []
        var rawAssets: [[String: Any]] = []
        var topLevelKeys: [String] = []

        if let dict = rawObj as? [String: Any] {
            topLevelKeys = dict.keys.sorted()
            if let arr = dict["modelRequests"] as? [[String: Any]] {
                rawRequests.append(contentsOf: arr)
            }
            if let arr = dict["requests"] as? [[String: Any]] {
                rawRequests.append(contentsOf: arr)
            }
            if let arr = dict["events"] as? [[String: Any]] {
                rawRequests.append(contentsOf: arr)
            }
            if let arr = dict["privateCloudComputeRequests"] as? [[String: Any]] {
                topLevelPCCRequests.append(contentsOf: arr)
            }
            if let arr = dict["assets"] as? [[String: Any]] {
                rawAssets.append(contentsOf: arr)
            }
        } else if let arr = rawObj as? [[String: Any]] {
            topLevelKeys = ["<root array>"]
            rawRequests = arr
        } else {
            throw ReportDecodeError.invalidJSONRoot
        }

        var rawDictsByIndex: [[String: Any]] = rawRequests
        var requests: [ParsedModelRequestItem] = rawRequests.enumerated().map { idx, reqDict in
            parseRequestItem(reqDict, index: idx)
        }

        // Correlate sibling top-level `privateCloudComputeRequests` back to `modelRequests`.
        if !topLevelPCCRequests.isEmpty {
            let unlinkedPCCRequestsCount = requests.filter {
                $0.executionTarget == .privateCloudCompute && $0.pccRequests.isEmpty
            }.count

            for (pIdx, pccDict) in topLevelPCCRequests.enumerated() {
                let subReqs = extractPCCSubRequests(from: pccDict)
                let pccID = ((pccDict["requestId"] as? String)
                    ?? (pccDict["modelRequestIdentifier"] as? String)
                    ?? (pccDict["parentRequestId"] as? String)
                    ?? (pccDict["identifier"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines)
                let pccTS = parseTimestamp(pccDict["timestamp"] ?? pccDict["date"] ?? pccDict["startTime"] ?? pccDict["createdAt"])
                let pKind = pccDict["pipelineKind"] as? String
                let pParams = pccDict["pipelineParameters"].map { stringifyAny($0) }

                let matchedIdx = findMatchingRequestIndex(
                    forPCCID: pccID,
                    timestamp: pccTS,
                    requests: requests,
                    allowSingleFallback: topLevelPCCRequests.count == 1 && unlinkedPCCRequestsCount == 1
                )

                if let idx = matchedIdx {
                    var updatedDict = rawDictsByIndex[idx]
                    if var linked = updatedDict["linkedPrivateCloudComputeRequests"] as? [[String: Any]] {
                        linked.append(pccDict)
                        updatedDict["linkedPrivateCloudComputeRequests"] = linked
                    } else {
                        updatedDict["linkedPrivateCloudComputeRequest"] = pccDict
                    }
                    rawDictsByIndex[idx] = updatedDict

                    let orig = requests[idx]
                    let mergedPCC = orig.pccRequests + subReqs
                    requests[idx] = ParsedModelRequestItem(
                        id: orig.id,
                        timestamp: orig.timestamp ?? pccTS,
                        useCase: orig.useCase,
                        executionTarget: .privateCloudCompute,
                        modelIdentifier: orig.modelIdentifier ?? extractModelFromPipelineParameters(pccDict["pipelineParameters"]),
                        modelVersion: orig.modelVersion,
                        clientIdentifier: orig.clientIdentifier,
                        pipelineKind: orig.pipelineKind ?? pKind,
                        pipelineParameters: orig.pipelineParameters ?? pParams,
                        promptBlocks: orig.promptBlocks,
                        toolCalls: orig.toolCalls,
                        responseText: orig.responseText,
                        pccRequests: mergedPCC,
                        rawJSONSnippet: formatJSONSnippet(updatedDict)
                    )
                } else {
                    let adapterOrModel = extractModelFromPipelineParameters(pccDict["pipelineParameters"])
                    let inferredUseCase = (pccDict["useCase"] as? String)
                        ?? (pccDict["useCaseIdentifier"] as? String)
                        ?? adapterOrModel
                        ?? pKind
                        ?? "PrivateCloudCompute"
                    let item = ParsedModelRequestItem(
                        id: pccID ?? "pcc-top-\(pIdx + 1)",
                        timestamp: pccTS,
                        useCase: inferredUseCase,
                        executionTarget: .privateCloudCompute,
                        modelIdentifier: (pccDict["modelIdentifier"] as? String) ?? (pccDict["model"] as? String) ?? adapterOrModel,
                        modelVersion: (pccDict["modelVersion"] as? String) ?? (pccDict["modelVersion"] as? NSNumber)?.stringValue,
                        clientIdentifier: (pccDict["clientIdentifier"] as? String) ?? (pccDict["bundleIdentifier"] as? String),
                        pipelineKind: pKind,
                        pipelineParameters: pParams,
                        promptBlocks: [],
                        toolCalls: [],
                        responseText: nil,
                        pccRequests: subReqs,
                        rawJSONSnippet: formatJSONSnippet(pccDict)
                    )
                    requests.append(item)
                    rawDictsByIndex.append(pccDict)
                }
            }
        }

        let assets: [ParsedModelAssetItem] = rawAssets.enumerated().map { idx, aDict in
            let assetID = (aDict["assetId"] as? String)
                ?? (aDict["assetID"] as? String)
                ?? (aDict["identifier"] as? String)
                ?? "asset-\(idx)"
            return ParsedModelAssetItem(
                id: "\(idx)-\(assetID)",
                assetID: assetID,
                version: aDict["version"] as? String,
                status: aDict["status"] as? String
            )
        }

        return ParsedAppleIntelligenceReport(
            sourceFileName: fileName,
            parsedAt: Date(),
            requests: requests,
            assets: assets,
            topLevelKeys: topLevelKeys
        )
    }

    // MARK: - Timestamp Conversion (Unix 1970 vs Apple Reference Date 2001)

    public static func parseTimestamp(_ value: Any?) -> Date? {
        if let num = value as? Double {
            if num > 1_500_000_000 {
                return Date(timeIntervalSince1970: num)
            } else if num > 400_000_000 {
                return Date(timeIntervalSinceReferenceDate: num)
            }
            return nil
        }
        if let intVal = value as? Int {
            return parseTimestamp(Double(intVal))
        }
        if let str = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            let isoBasic = ISO8601DateFormatter()
            if let d = isoBasic.date(from: str) { return d }
        }
        return nil
    }

    // MARK: - Request Parsing

    private static func parseRequestItem(_ dict: [String: Any], index: Int) -> ParsedModelRequestItem {
        let id = (dict["identifier"] as? String) ?? (dict["id"] as? String) ?? (dict["requestId"] as? String) ?? "req-\(index + 1)"
        let timestamp = parseTimestamp(dict["timestamp"] ?? dict["date"] ?? dict["createdAt"] ?? dict["startTime"])
        let useCase = (dict["useCase"] as? String)
            ?? (dict["useCaseIdentifier"] as? String)
            ?? (dict["feature"] as? String)
            ?? "Apple Intelligence"
        let modelID = (dict["modelIdentifier"] as? String) ?? (dict["model"] as? String)
        let modelVersion = (dict["modelVersion"] as? String) ?? (dict["modelVersion"] as? NSNumber)?.stringValue
        let clientIdentifier = (dict["clientIdentifier"] as? String)
            ?? (dict["bundleIdentifier"] as? String)
            ?? (dict["sourceApp"] as? String)
        let pipelineKind = dict["pipelineKind"] as? String
        let pipelineParameters = dict["pipelineParameters"].map { stringifyAny($0) }

        // Extract prompt string (or prompt array/messages)
        var promptBlocks: [PromptBlock] = []
        if let promptStr = dict["prompt"] as? String {
            promptBlocks.append(contentsOf: sliceAFMPrompt(promptStr))
        } else if let inputStr = dict["input"] as? String {
            promptBlocks.append(contentsOf: sliceAFMPrompt(inputStr))
        } else if let messages = dict["messages"] as? [[String: Any]] {
            for m in messages {
                let roleStr = (m["role"] as? String ?? "raw").lowercased()
                let role = PromptRole(rawValue: roleStr) ?? .raw
                let content = (m["content"] as? String) ?? stringifyAny(m["content"])
                promptBlocks.append(PromptBlock(
                    id: UUID(),
                    role: role,
                    content: content,
                    silentTokenBudget: extractSilentTokenBudget(from: content)
                ))
            }
        }

        // Extract tool calls from structured fields AND from prompt blocks
        var toolCalls = extractStructuredToolCalls(from: dict)
        for block in promptBlocks {
            toolCalls.append(contentsOf: extractToolCallsFromText(block.content))
        }

        let responseText = (dict["response"] as? String)
            ?? (dict["output"] as? String)
            ?? (dict["generatedText"] as? String)

        // Parse PCC sub-requests + CloudAttestation bundles
        var pccList: [ParsedPCCSubRequest] = []
        if let pccArr = dict["privateCloudComputeRequests"] as? [[String: Any]] {
            for pDict in pccArr {
                pccList.append(contentsOf: extractPCCSubRequests(from: pDict))
            }
        } else if let pccSingle = dict["privateCloudComputeRequest"] as? [String: Any] {
            pccList.append(contentsOf: extractPCCSubRequests(from: pccSingle))
        } else if dict["attestationBundle"] != nil || dict["attestation"] != nil || dict["attestations"] != nil || dict["subrequests"] != nil || dict["subRequests"] != nil {
            pccList.append(contentsOf: extractPCCSubRequests(from: dict))
        }

        let target = classifyExecutionTarget(
            dict: dict,
            useCase: useCase,
            modelID: modelID,
            hasPCCRequests: !pccList.isEmpty
        )
        let rawSnippet = formatJSONSnippet(dict)

        return ParsedModelRequestItem(
            id: id,
            timestamp: timestamp,
            useCase: useCase,
            executionTarget: target,
            modelIdentifier: modelID,
            modelVersion: modelVersion,
            clientIdentifier: clientIdentifier,
            pipelineKind: pipelineKind ?? pccList.first?.rawFieldsSummary["pipelineKind"],
            pipelineParameters: pipelineParameters ?? pccList.first?.rawFieldsSummary["pipelineParameters"],
            promptBlocks: promptBlocks,
            toolCalls: deduplicateToolCalls(toolCalls),
            responseText: responseText,
            pccRequests: pccList,
            rawJSONSnippet: rawSnippet
        )
    }

    private static func classifyExecutionTarget(
        dict: [String: Any],
        useCase: String,
        modelID: String?,
        hasPCCRequests: Bool
    ) -> ParsedModelRequestItem.ExecutionTarget {
        if hasPCCRequests { return .privateCloudCompute }

        let envCandidates = [
            dict["executionEnvironment"] as? String,
            dict["computeLocation"] as? String,
            dict["location"] as? String,
            dict["destination"] as? String
        ].compactMap { $0?.lowercased() }

        for env in envCandidates {
            if env.contains("privatecloudcompute") || env.contains("pcc") || env.contains("cloud") || env.contains("server") || env.contains("remote") {
                return .privateCloudCompute
            }
        }

        if let model = modelID?.lowercased(),
           model.contains("server") || model.contains("pcc") || model.contains("cloud") {
            return .privateCloudCompute
        }

        let lowerUC = useCase.lowercased()
        if lowerUC.contains("privatecloudcompute") || lowerUC.contains("pcc") {
            return .privateCloudCompute
        }

        return .onDevice
    }

    private static func findMatchingRequestIndex(
        forPCCID pccID: String?,
        timestamp pccTS: Date?,
        requests: [ParsedModelRequestItem],
        allowSingleFallback: Bool
    ) -> Int? {
        if let pccID, !pccID.isEmpty {
            if let exactIdx = requests.firstIndex(where: { $0.id.caseInsensitiveCompare(pccID) == .orderedSame }) {
                return exactIdx
            }
        }

        if let pccTS {
            // Prefer PCC-classified requests without attached PCC sub-requests within +/-30s
            let emptyCandidates = requests.enumerated().compactMap { idx, item -> (Int, TimeInterval)? in
                guard item.executionTarget == .privateCloudCompute,
                      item.pccRequests.isEmpty,
                      let ts = item.timestamp else { return nil }
                let delta = abs(ts.timeIntervalSince(pccTS))
                return delta <= 30.0 ? (idx, delta) : nil
            }
            if let best = emptyCandidates.min(by: { $0.1 < $1.1 }) {
                return best.0
            }

            let anyPCCCandidates = requests.enumerated().compactMap { idx, item -> (Int, TimeInterval)? in
                guard item.executionTarget == .privateCloudCompute,
                      let ts = item.timestamp else { return nil }
                let delta = abs(ts.timeIntervalSince(pccTS))
                return delta <= 30.0 ? (idx, delta) : nil
            }
            if let best = anyPCCCandidates.min(by: { $0.1 < $1.1 }) {
                return best.0
            }
        }

        if allowSingleFallback,
           let singleIdx = requests.firstIndex(where: { $0.executionTarget == .privateCloudCompute && $0.pccRequests.isEmpty }) {
            return singleIdx
        }

        return nil
    }

    private static func extractPCCSubRequests(from dict: [String: Any], depth: Int = 0) -> [ParsedPCCSubRequest] {
        guard depth < 4 else { return [] }

        var results: [ParsedPCCSubRequest] = []
        let baseID = (dict["identifier"] as? String) ?? (dict["requestId"] as? String) ?? "pcc-\(depth + 1)"
        let endpoint = (dict["pccEndpoint"] as? String)
            ?? (dict["endpoint"] as? String)
            ?? (dict["pipelineKind"] as? String)
            ?? (dict["nodeIdentifier"] as? String)
            ?? (dict["nodeId"] as? String)
        let state = (dict["requestState"] as? String) ?? (dict["status"] as? String) ?? (dict["state"] as? String)
        let payloadBytes = (dict["payloadSize"] as? Int) ?? (dict["estimatedSize"] as? Int)

        var summary: [String: String] = [:]
        let excludedKeys: Set<String> = [
            "attestationBundle", "attestation", "attestationData",
            "attestations", "subrequests", "subRequests"
        ]
        for (k, v) in dict where !excludedKeys.contains(k) {
            summary[k] = stringifyAny(v)
        }

        if let subArr = (dict["subrequests"] as? [[String: Any]]) ?? (dict["subRequests"] as? [[String: Any]]) {
            for sub in subArr {
                results.append(contentsOf: extractPCCSubRequests(from: sub, depth: depth + 1))
            }
        }

        if let attestationsArr = dict["attestations"] as? [Any], !attestationsArr.isEmpty {
            for (aIdx, rawAtt) in attestationsArr.enumerated() {
                if let decoded = CloudAttestationInspector.decodeAnyAttestation(rawAtt) {
                    let nodeName = decoded.appDataName
                    let combinedEndpoint: String?
                    if let endpoint, let nodeName, !nodeName.isEmpty, endpoint != nodeName {
                        combinedEndpoint = "\(endpoint) (\(nodeName))"
                    } else {
                        combinedEndpoint = endpoint ?? nodeName
                    }
                    results.append(ParsedPCCSubRequest(
                        id: attestationsArr.count > 1 ? "\(baseID)-att-\(aIdx + 1)" : baseID,
                        endpoint: combinedEndpoint,
                        requestState: state,
                        payloadBytes: payloadBytes,
                        attestation: decoded,
                        rawFieldsSummary: summary
                    ))
                }
            }
        } else if let singular = dict["attestationBundle"] ?? dict["attestation"] ?? dict["attestationData"],
                  let decoded = CloudAttestationInspector.decodeAnyAttestation(singular) {
            results.append(ParsedPCCSubRequest(
                id: baseID,
                endpoint: endpoint ?? decoded.appDataName,
                requestState: state,
                payloadBytes: payloadBytes,
                attestation: decoded,
                rawFieldsSummary: summary
            ))
        }

        if results.isEmpty {
            results.append(ParsedPCCSubRequest(
                id: baseID,
                endpoint: endpoint,
                requestState: state,
                payloadBytes: payloadBytes,
                attestation: nil,
                rawFieldsSummary: summary
            ))
        }

        return results
    }

    private static func extractModelFromPipelineParameters(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return (dict["adapter"] as? String)
                ?? (dict["model"] as? String)
                ?? (dict["modelIdentifier"] as? String)
        }
        if let str = value as? String,
           let data = str.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (dict["adapter"] as? String)
                ?? (dict["model"] as? String)
                ?? (dict["modelIdentifier"] as? String)
        }
        return nil
    }

    private static func formatJSONSnippet(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - AFM Control-Token Prompt Slicer

    /// Splits `<ctrl99>role\n...<ctrl100>` prompt structures into structured role blocks.
    public static func sliceAFMPrompt(_ rawPrompt: String) -> [PromptBlock] {
        guard rawPrompt.contains("<ctrl99>") else {
            let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            return [PromptBlock(
                id: UUID(),
                role: .raw,
                content: trimmed,
                silentTokenBudget: extractSilentTokenBudget(from: trimmed)
            )]
        }

        var blocks: [PromptBlock] = []
        let segments = rawPrompt.components(separatedBy: "<ctrl99>")
        for seg in segments {
            let cleaned = seg.replacingOccurrences(of: "<ctrl100>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            if let newlineIdx = cleaned.firstIndex(of: "\n") {
                let roleToken = String(cleaned[..<newlineIdx]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let body = String(cleaned[cleaned.index(after: newlineIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let role = mapRoleToken(roleToken)
                blocks.append(PromptBlock(
                    id: UUID(),
                    role: role,
                    content: body.isEmpty ? cleaned : body,
                    silentTokenBudget: extractSilentTokenBudget(from: body)
                ))
            } else {
                blocks.append(PromptBlock(
                    id: UUID(),
                    role: .raw,
                    content: cleaned,
                    silentTokenBudget: extractSilentTokenBudget(from: cleaned)
                ))
            }
        }
        return blocks
    }

    private static func mapRoleToken(_ token: String) -> PromptRole {
        switch token {
        case "system": return .system
        case "developer": return .developer
        case "thought", "thinking": return .thought
        case "user": return .user
        case "tool", "function", "tool_response": return .tool
        case "model", "assistant": return .assistant
        default: return .raw
        }
    }

    private static func extractSilentTokenBudget(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"Silent thinking token budget:\s*(\d+)"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[r])
    }

    private static func extractStructuredToolCalls(from dict: [String: Any]) -> [ExtractedToolCall] {
        var calls: [ExtractedToolCall] = []
        if let arr = dict["toolCalls"] as? [[String: Any]] ?? dict["tool_calls"] as? [[String: Any]] {
            for (idx, item) in arr.enumerated() {
                let name = (item["name"] as? String) ?? (item["toolName"] as? String) ?? "tool_\(idx + 1)"
                let args = stringifyAny(item["arguments"] ?? item["parameters"] ?? item["input"] ?? [:])
                let res = item["result"].map { stringifyAny($0) }
                calls.append(ExtractedToolCall(
                    id: "\(idx)-\(name)",
                    name: name,
                    argumentsJSON: args,
                    resultPreview: res
                ))
            }
        }
        if let toolDefs = dict["tools"] as? [[String: Any]] {
            for (idx, def) in toolDefs.enumerated() {
                let name = (def["name"] as? String)
                    ?? ((def["function"] as? [String: Any])?["name"] as? String)
                    ?? "declared_tool_\(idx + 1)"
                let args = stringifyAny(def["parameters"] ?? def["schema"] ?? def)
                calls.append(ExtractedToolCall(
                    id: "def-\(idx)-\(name)",
                    name: "\(name) [Schema]",
                    argumentsJSON: args,
                    resultPreview: nil
                ))
            }
        }
        return calls
    }

    private static func extractToolCallsFromText(_ text: String) -> [ExtractedToolCall] {
        var calls: [ExtractedToolCall] = []
        // Look for JSON objects containing "name" and "arguments" or App Intents call syntax
        guard let regex = try? NSRegularExpression(pattern: #"\{[^{}]*"(?:name|tool)"\s*:\s*"([^"]+)"[^{}]*\}"#, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (idx, match) in regex.matches(in: text, range: range).enumerated() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let snippet = String(text[fullRange])
            let name = String(text[nameRange])
            calls.append(ExtractedToolCall(
                id: "text-\(idx)-\(name)",
                name: name,
                argumentsJSON: snippet,
                resultPreview: nil
            ))
        }
        return calls
    }

    private static func deduplicateToolCalls(_ items: [ExtractedToolCall]) -> [ExtractedToolCall] {
        var seen: Set<String> = []
        var out: [ExtractedToolCall] = []
        for item in items {
            let key = "\(item.name)|\(item.argumentsJSON)"
            if seen.insert(key).inserted {
                out.append(item)
            }
        }
        return out
    }

    private static func stringifyAny(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value),
           let d = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return String(describing: value)
    }
}

// MARK: - Built-in Sample Report Fixture (with real Protobuf AttestationBundle + DER X.509 Cert)

public enum SampleReportFixture {
    public static func sampleReportJSONData() -> Data {
        let sampleBundleBase64 = buildSampleAttestationBundleBase64()
        let nowUnix = Date().timeIntervalSince1970

        let report: [String: Any] = [
            "modelRequests": [
                [
                    "timestamp": nowUnix - 180,
                    "identifier": "A7F2D910-4C3B-4E19-9A2E-8B5D30F1E201",
                    "useCase": "Siri.AppIntents.WritingTools",
                    "modelIdentifier": "com.apple.gm.pcc-server-llm.v3",
                    "prompt": """
                    <ctrl99>system
                    SPECIAL INSTRUCTION: think silently. Silent thinking token budget: 64 tokens.<ctrl100>
                    <ctrl99>developer
                    You are Apple Intelligence operating inside Private Cloud Compute. Preserve user privacy, invoke declared AppIntents tools strictly when needed, and return concise output.<ctrl100>
                    <ctrl99>thought
                    User asked to summarize today's schedule and check calendar conflicts via AppIntents tool.<ctrl100>
                    <ctrl99>user
                    Summarize my afternoon meeting notes and draft a brief polite reply.<ctrl100>
                    <ctrl99>tool
                    {"name": "CalendarAppIntent.fetchEvents", "arguments": {"windowHours": 8, "includeNotes": true}}<ctrl100>
                    """,
                    "toolCalls": [
                        [
                            "name": "CalendarAppIntent.fetchEvents",
                            "arguments": ["windowHours": 8, "includeNotes": true],
                            "result": ["matchedEvents": 2, "status": "ok"]
                        ]
                    ],
                    "response": "Your 15:00 architecture sync focuses on zero-MitM Apple PCC routing and live USB diagnostics.",
                    "privateCloudComputeRequests": [
                        [
                            "identifier": "PCC-REQ-9941A",
                            "pccEndpoint": "tie-cloudboard.apple.com",
                            "requestState": "completed",
                            "payloadSize": 4820,
                            "attestationBundle": sampleBundleBase64
                        ]
                    ]
                ],
                [
                    "timestamp": nowUnix - 420,
                    "identifier": "B4C108E2-9104-4B77-A011-3F92E701C004",
                    "useCase": "FoundationModels.OnDevice.Summarize",
                    "modelIdentifier": "com.apple.fm.ondevice.3b",
                    "prompt": """
                    <ctrl99>system
                    SPECIAL INSTRUCTION: think silently. Silent thinking token budget: 32 tokens.<ctrl100>
                    <ctrl99>user
                    Extract key action items locally on ANE without leaving the device.<ctrl100>
                    """,
                    "response": "1. Verify Surge skip-proxy includes guzzoni.apple.com\n2. Confirm UDP 443 QUIC passes on US node."
                ]
            ],
            "assets": [
                [
                    "assetId": "com.apple.MobileAsset.UAF.FM.GenerativeModels",
                    "version": "2026.11.2",
                    "status": "installed"
                ],
                [
                    "assetId": "com.apple.MobileAsset.UAF.IF.NLRouter",
                    "version": "2026.11.1",
                    "status": "installed"
                ]
            ]
        ]

        return (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    public static func buildSampleAttestationBundleBase64() -> String {
        let leafDER = buildSelfSignedSampleDERCert(
            issuerCN: "Apple PCC Provisioning Intermediate CA",
            subjectCN: "pcc-compute-us-west-02.apple.com"
        )
        let intermediateDER = buildSelfSignedSampleDERCert(
            issuerCN: "Apple Private Cloud Compute Root CA",
            subjectCN: "Apple PCC Provisioning Intermediate CA"
        )

        // field 1: sep_attestation (synthetic 48-byte hardware quote)
        let sepData = Data("SEP_ATTEST_SIMULATED_HARDWARE_QUOTE_APPLE_SILICON".utf8)
        // field 2: ap_ticket with genuine IM4M magic prefix
        var apData = Data("IM4M".utf8)
        apData.append(Data(repeating: 0xA5, count: 44))

        // field 3: SealedHashLedger -> map<string, SealedHash> entry
        let secureConfigJSON = #"{"release_train":"PCC-27.2","environment":"production","network_egress":"disabled"}"#
        let secureConfigMsg = ProtobufWireEncoder.stringField(1, secureConfigJSON)
        let digestBytes = Data(SHA256.hash(data: Data(secureConfigJSON.utf8)))
        var entryMsg = ProtobufWireEncoder.varintField(1, value: 0x01)
        entryMsg.append(ProtobufWireEncoder.bytesField(2, data: digestBytes))
        entryMsg.append(ProtobufWireEncoder.bytesField(5, data: secureConfigMsg))

        var sealedHashMsg = ProtobufWireEncoder.varintField(1, value: 1) // SHA-256
        sealedHashMsg.append(ProtobufWireEncoder.bytesField(2, data: entryMsg))

        var mapEntry = ProtobufWireEncoder.stringField(1, "slot-0-darwin-init")
        mapEntry.append(ProtobufWireEncoder.bytesField(2, data: sealedHashMsg))
        let ledgerMsg = ProtobufWireEncoder.bytesField(1, data: mapEntry)

        // field 5: AppData
        var appDataMsg = ProtobufWireEncoder.varintField(1, value: 1)
        appDataMsg.append(ProtobufWireEncoder.stringField(2, "com.apple.PrivateCloudCompute"))
        appDataMsg.append(ProtobufWireEncoder.stringField(3, "tie-cloudboard-apple-com"))

        // field 8: TransparencyProofs
        let tpProof = ProtobufWireEncoder.bytesField(1, data: Data("ATLOG_MERKLE_INCLUSION_PROOF_DEMO".utf8))

        var bundle = Data()
        bundle.append(ProtobufWireEncoder.bytesField(1, data: sepData))
        bundle.append(ProtobufWireEncoder.bytesField(2, data: apData))
        bundle.append(ProtobufWireEncoder.bytesField(3, data: ledgerMsg))
        bundle.append(ProtobufWireEncoder.bytesField(4, data: leafDER))
        bundle.append(ProtobufWireEncoder.bytesField(4, data: intermediateDER))
        bundle.append(ProtobufWireEncoder.bytesField(5, data: appDataMsg))
        bundle.append(ProtobufWireEncoder.timestampField(6, date: Date().addingTimeInterval(86400 * 7)))
        bundle.append(ProtobufWireEncoder.bytesField(8, data: tpProof))

        return bundle.base64EncodedString()
    }

    private static func buildSelfSignedSampleDERCert(issuerCN: String, subjectCN: String) -> Data {
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

        let sigAlg = seq(oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        let key = P256.Signing.PrivateKey()
        let spki = seq(
            seq(oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]), oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])),
            tlv(0x03, [0x00] + Array(key.publicKey.x963Representation))
        )
        let tbs = seq(
            tlv(0xA0, tlv(0x02, [0x02])),
            tlv(0x02, [0x01, 0x02, 0x03]),
            sigAlg,
            rdn(cn: issuerCN, org: "Apple Inc."),
            seq(utc("260101000000Z"), utc("271231235959Z")),
            rdn(cn: subjectCN, org: "Apple Inc."),
            spki
        )
        let sig = (try? key.signature(for: Data(tbs)).derRepresentation) ?? Data()
        return Data(seq(tbs, sigAlg, tlv(0x03, [0x00] + Array(sig))))
    }
}
