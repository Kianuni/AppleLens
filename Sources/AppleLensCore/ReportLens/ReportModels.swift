import Foundation

public enum PromptRole: String, Codable, Sendable {
    case system
    case developer
    case thought
    case user
    case tool
    case assistant
    case raw

    public func label(lang: AppLanguage) -> String {
        switch self {
        case .system: return tr("系统隐藏指令 (System)", "Hidden System Prompt", lang: lang)
        case .developer: return tr("开发者策略 (Developer)", "Developer Instruction", lang: lang)
        case .thought: return tr("静默思考链 (Silent Thought)", "Silent Thinking", lang: lang)
        case .user: return tr("用户输入 (User)", "User Prompt", lang: lang)
        case .tool: return tr("工具定义 / 返回 (Tool)", "Tool Schema / Result", lang: lang)
        case .assistant: return tr("模型输出 (Model)", "Model Output", lang: lang)
        case .raw: return tr("原始载荷", "Raw Payload", lang: lang)
        }
    }
}

public struct ExtractedToolCall: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
    public let resultPreview: String?
}

public struct PromptBlock: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let role: PromptRole
    public let content: String
    public let silentTokenBudget: Int?
}

public struct ParsedPCCSubRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let endpoint: String?
    public let requestState: String?
    public let payloadBytes: Int?
    public let attestation: DecodedCloudAttestation?
    public let rawFieldsSummary: [String: String]
}

public struct ParsedModelRequestItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let timestamp: Date?
    public let useCase: String
    public let executionTarget: ExecutionTarget
    public let modelIdentifier: String?
    public let modelVersion: String?
    public let clientIdentifier: String?
    public let pipelineKind: String?
    public let pipelineParameters: String?
    public let promptBlocks: [PromptBlock]
    public let toolCalls: [ExtractedToolCall]
    public let responseText: String?
    public let pccRequests: [ParsedPCCSubRequest]
    public let rawJSONSnippet: String

    public init(
        id: String,
        timestamp: Date?,
        useCase: String,
        executionTarget: ExecutionTarget,
        modelIdentifier: String?,
        modelVersion: String? = nil,
        clientIdentifier: String? = nil,
        pipelineKind: String? = nil,
        pipelineParameters: String? = nil,
        promptBlocks: [PromptBlock],
        toolCalls: [ExtractedToolCall],
        responseText: String?,
        pccRequests: [ParsedPCCSubRequest],
        rawJSONSnippet: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.useCase = useCase
        self.executionTarget = executionTarget
        self.modelIdentifier = modelIdentifier
        self.modelVersion = modelVersion
        self.clientIdentifier = clientIdentifier
        self.pipelineKind = pipelineKind
        self.pipelineParameters = pipelineParameters
        self.promptBlocks = promptBlocks
        self.toolCalls = toolCalls
        self.responseText = responseText
        self.pccRequests = pccRequests
        self.rawJSONSnippet = rawJSONSnippet
    }

    public enum ExecutionTarget: String, Codable, Sendable {
        case onDevice
        case privateCloudCompute

        public func label(lang: AppLanguage) -> String {
            switch self {
            case .onDevice: return tr("端侧本地", "On-Device", lang: lang)
            case .privateCloudCompute: return tr("Apple PCC 云端", "Apple PCC", lang: lang)
            }
        }
    }
}

public struct ParsedModelAssetItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let assetID: String
    public let version: String?
    public let status: String?
}

public struct ParsedAppleIntelligenceReport: Sendable {
    public let sourceFileName: String
    public let parsedAt: Date
    public let requests: [ParsedModelRequestItem]
    public let assets: [ParsedModelAssetItem]
    public let topLevelKeys: [String]

    public var pccRequestCount: Int {
        requests.filter { $0.executionTarget == .privateCloudCompute }.count
    }

    public var onDeviceRequestCount: Int {
        requests.filter { $0.executionTarget == .onDevice }.count
    }

    public var attestationCount: Int {
        requests.reduce(0) { sum, req in
            sum + req.pccRequests.filter { $0.attestation != nil }.count
        }
    }

    public var timeSpan: (start: Date, end: Date)? {
        let stamps = requests.compactMap(\.timestamp)
        guard let earliest = stamps.min(), let latest = stamps.max() else {
            return nil
        }
        return (earliest, latest)
    }
}
