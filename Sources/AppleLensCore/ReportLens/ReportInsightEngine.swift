import Foundation

public enum ReportVerdictTone: Sendable, Equatable {
    case onDevicePure
    case pccCloudVerified
    case hybridSynergy
    case emptyReport
}

public struct ReportConclusionBullet: Identifiable, Sendable {
    public let id: String
    public let icon: String
    public let titleZh: String
    public let titleEn: String
    public let detailZh: String
    public let detailEn: String

    public func title(lang: AppLanguage) -> String {
        lang == .zhHans ? titleZh : titleEn
    }

    public func detail(lang: AppLanguage) -> String {
        lang == .zhHans ? detailZh : detailEn
    }
}

public struct ReportExecutiveSummary: Sendable {
    public let tone: ReportVerdictTone
    public let badgeZh: String
    public let badgeEn: String
    public let headlineZh: String
    public let headlineEn: String
    public let subheadlineZh: String
    public let subheadlineEn: String
    public let detectedFeaturesZh: [String]
    public let detectedFeaturesEn: [String]
    public let bullets: [ReportConclusionBullet]

    public func badge(lang: AppLanguage) -> String {
        lang == .zhHans ? badgeZh : badgeEn
    }

    public func headline(lang: AppLanguage) -> String {
        lang == .zhHans ? headlineZh : headlineEn
    }

    public func subheadline(lang: AppLanguage) -> String {
        lang == .zhHans ? subheadlineZh : subheadlineEn
    }

    public func detectedFeatures(lang: AppLanguage) -> [String] {
        lang == .zhHans ? detectedFeaturesZh : detectedFeaturesEn
    }
}

public struct RequestPlainInterpretation: Sendable {
    public let featureTitleZh: String
    public let featureTitleEn: String
    public let categoryIcon: String
    public let clientAppZh: String?
    public let clientAppEn: String?
    public let isVisualOrNonTextTask: Bool
    public let narrativeZh: String
    public let narrativeEn: String
    public let privacyGuaranteeZh: String
    public let privacyGuaranteeEn: String
    public let emptyPromptExplanationZh: String
    public let emptyPromptExplanationEn: String

    public func featureTitle(lang: AppLanguage) -> String {
        lang == .zhHans ? featureTitleZh : featureTitleEn
    }

    public func clientApp(lang: AppLanguage) -> String? {
        lang == .zhHans ? clientAppZh : clientAppEn
    }

    public func narrative(lang: AppLanguage) -> String {
        lang == .zhHans ? narrativeZh : narrativeEn
    }

    public func privacyGuarantee(lang: AppLanguage) -> String {
        lang == .zhHans ? privacyGuaranteeZh : privacyGuaranteeEn
    }

    public func emptyPromptExplanation(lang: AppLanguage) -> String {
        lang == .zhHans ? emptyPromptExplanationZh : emptyPromptExplanationEn
    }
}

/// Generates plain-language executive conclusions and per-request explanations for decoded Apple Intelligence reports.
public enum ReportInsightEngine {
    public static func interpret(request: ParsedModelRequestItem) -> RequestPlainInterpretation {
        let descriptor = classifyFeature(for: request)
        let clientApp = mapClientApp(request.clientIdentifier)

        let attestations = request.pccRequests.compactMap(\.attestation)
        let certCount = attestations.reduce(0) { $0 + $1.certificateChain.count }
        let isPCC = request.executionTarget == .privateCloudCompute

        let privacyZh: String
        let privacyEn: String
        if isPCC {
            if !attestations.isEmpty {
                let nodeName = attestations.first?.appDataName ?? request.pipelineKind ?? "Apple PCC"
                let allVerified = attestations.allSatisfy(\.signatureChainVerified)
                if allVerified {
                    privacyZh = "隐私保障：请求内容已使用 PCC 硬件安全飞地（\(nodeName)）公钥端到端加密，并已通过 SecTrust 加密验证 \(attestations.count) 组 AttestationBundle（含 \(certCount) 张锚定 Apple Root CA 的 X.509 节点证书），代理节点无法解密且服务端用完即焚、零留存。"
                    privacyEn = "Privacy Guarantee: Encrypted end-to-end to PCC node (\(nodeName)) with \(attestations.count) AttestationBundle(s) and \(certCount) X.509 cert(s) cryptographically verified against Apple Root CA via SecTrust; stateless zero-retention execution."
                } else {
                    let sigStatusZh = attestations.first?.signatureStatusZh ?? "证书链未锚定系统 Apple Root CA"
                    let sigStatusEn = attestations.first?.signatureStatusEn ?? "Certificate chain not anchored to Apple Root CA"
                    privacyZh = "隐私保障：请求内容面向 PCC 硬件安全飞地（\(nodeName)）端到端加密，已解析 \(attestations.count) 组 AttestationBundle（含 \(certCount) 张 X.509 节点证书；SecTrust 状态：\(sigStatusZh)），代理节点无法解密且服务端用完即焚。"
                    privacyEn = "Privacy Guarantee: Targeted at PCC node (\(nodeName)); decoded \(attestations.count) AttestationBundle(s) with \(certCount) X.509 cert(s) (SecTrust status: \(sigStatusEn)); stateless zero-retention execution."
                }
            } else {
                privacyZh = "隐私保障：已走 Apple PCC 无状态私有云通道与 OHTTP 匿名盲签名令牌机制（剥离 IP 与 Apple ID 关联），服务端处理完毕立即销毁数据且不参与任何模型训练。"
                privacyEn = "Privacy Guarantee: Executed on Apple PCC stateless enclaves over OHTTP blind-signed tokens (decoupled from IP/Apple ID) with zero data retention."
            }
        } else {
            privacyZh = "隐私保障：本次请求 100% 在本机 Apple Silicon 神经网络引擎（ANE）完成推理，原始图片或文本从未离开你的设备，无任何网络数据出境。"
            privacyEn = "Privacy Guarantee: Processed 100% locally on Apple Silicon ANE. Zero data left your device."
        }

        let emptyPromptZh: String
        let emptyPromptEn: String
        if descriptor.isAudioTask {
            emptyPromptZh = "语音转写与音频类任务处理的是本地音频波形或声学特征，而非文本对话提示词，因此「Prompt 消息链」显示 0 条属正常现象。"
            emptyPromptEn = "Audio and speech tasks process waveform/acoustic features rather than text prompts, so 0 text prompt blocks is expected."
        } else if descriptor.isVisualOrNonTextTask {
            emptyPromptZh = "视觉扩散 / 图像编辑任务（如相册高质量消除）传输的是涂抹区域的图像掩码张量（Masked Image Tensor），并非 LLM 对话文本 Prompt，因此这里显示 Prompt = 0 完全正常。可点击「CloudAttestation 与证书链」或「原始 JSON」核对云端扩散模型与路由细节。"
            emptyPromptEn = "Visual diffusion tasks (such as Photos Clean Up) transmit masked image tensors rather than text dialogue prompts, so 0 prompt blocks is completely normal. Inspect CloudAttestation or Raw JSON tabs for routing details."
        } else {
            emptyPromptZh = "系统在此条导出记录中仅保存了模型调用与路由元数据（常见于独立导出的 privateCloudComputeRequests 或隐去明文提示词的隐私条目），未附带明文 Prompt 字符串；可切换到「CloudAttestation 与证书链」或「原始 JSON」查看完整结构。"
            emptyPromptEn = "This entry contains routing and execution metadata without plaintext prompt strings (common in standalone privateCloudComputeRequests or redacted records). Inspect CloudAttestation or Raw JSON for full fields."
        }

        return RequestPlainInterpretation(
            featureTitleZh: descriptor.titleZh,
            featureTitleEn: descriptor.titleEn,
            categoryIcon: descriptor.icon,
            clientAppZh: clientApp?.zh,
            clientAppEn: clientApp?.en,
            isVisualOrNonTextTask: descriptor.isVisualOrNonTextTask,
            narrativeZh: descriptor.narrativeZh,
            narrativeEn: descriptor.narrativeEn,
            privacyGuaranteeZh: privacyZh,
            privacyGuaranteeEn: privacyEn,
            emptyPromptExplanationZh: emptyPromptZh,
            emptyPromptExplanationEn: emptyPromptEn
        )
    }

    public static func summarize(report: ParsedAppleIntelligenceReport) -> ReportExecutiveSummary {
        guard !report.requests.isEmpty else {
            return ReportExecutiveSummary(
                tone: .emptyReport,
                badgeZh: "尚无 AI 活动记录",
                badgeEn: "No Requests Recorded",
                headlineZh: "当前 JSON 文件中未包含 Apple 智能推理记录（总请求 = 0）",
                headlineEn: "This JSON export contains 0 recorded Apple Intelligence requests",
                subheadlineZh: "请先确认已在系统「隐私与安全性 → Apple 智能报告」开启「过去 15 分钟」或「过去 7 天」，再实际使用一次相册消除、写作工具或 Siri 后重新导出。",
                subheadlineEn: "Ensure Report Duration (15 Minutes or 7 Days) is enabled in Privacy & Security -> Apple Intelligence Report, trigger Clean Up, Writing Tools, or Siri, and export again.",
                detectedFeaturesZh: [],
                detectedFeaturesEn: [],
                bullets: [
                    ReportConclusionBullet(
                        id: "empty-howto",
                        icon: "record.circle",
                        titleZh: "如何捕获有效数据",
                        titleEn: "How to Capture Activity",
                        detailZh: "当报告开关处于关闭状态时，导出的 Apple_Intelligence_Report.json 仅为空壳结构。打开开关后，触发任意端侧或 PCC 云端功能即可生成可解码条目。",
                        detailEn: "Exports generated while logging was off contain empty arrays. Enable logging, use an AI feature once, and re-export."
                    )
                ]
            )
        }

        let interpretations = report.requests.map { interpret(request: $0) }
        var seenZh: Set<String> = []
        var featuresZh: [String] = []
        var featuresEn: [String] = []
        for item in interpretations {
            if seenZh.insert(item.featureTitleZh).inserted {
                featuresZh.append(item.featureTitleZh)
                featuresEn.append(item.featureTitleEn)
            }
        }

        let total = report.requests.count
        let pccCount = report.pccRequestCount
        let onDeviceCount = report.onDeviceRequestCount
        let attCount = report.attestationCount
        let promptCount = report.requests.reduce(0) { $0 + $1.promptBlocks.count }
        let toolCount = report.requests.reduce(0) { $0 + $1.toolCalls.count }
        let hasVisualTasks = interpretations.contains(where: \.isVisualOrNonTextTask)
        let hasServerDiffusion = report.requests.contains {
            let m = ($0.modelIdentifier ?? "").lowercased()
            let u = $0.useCase.lowercased()
            return m.contains("server_diffusion") || u.contains("photosedit.infill")
        }

        let tone: ReportVerdictTone
        let badgeZh: String
        let badgeEn: String
        let headlineZh: String
        let headlineEn: String
        let subheadlineZh: String
        let subheadlineEn: String

        if pccCount > 0 && onDeviceCount > 0 {
            tone = .hybridSynergy
            badgeZh = "端云协同 · PCC 云端通道已实证"
            badgeEn = "Hybrid ANE + PCC Verified"
            headlineZh = "结论：本次记录包含 \(onDeviceCount) 次端侧 ANE 推理与 \(pccCount) 次 Apple PCC 私有云调度"
            headlineEn = "Verdict: Recorded \(onDeviceCount) on-device ANE run(s) and \(pccCount) Apple PCC cloud call(s)"
        } else if pccCount > 0 {
            tone = .pccCloudVerified
            badgeZh = "PCC 私有云已走通"
            badgeEn = "PCC Cloud Verified"
            headlineZh = "结论：设备已成功接入 Apple PCC 私有云（共 \(pccCount) 次云端高阶推理）"
            headlineEn = "Verdict: Device reached Apple PCC Private Cloud (\(pccCount) cloud request(s))"
        } else {
            tone = .onDevicePure
            badgeZh = "纯端侧本地执行"
            badgeEn = "100% On-Device ANE"
            headlineZh = "结论：全部 \(onDeviceCount) 次请求均在端侧神经网络引擎 (ANE) 本地完成，未连接云端"
            headlineEn = "Verdict: All \(onDeviceCount) request(s) completed locally on ANE without cloud offload"
        }

        let featureSummaryZh = featuresZh.prefix(3).joined(separator: "、")
        let featureSummaryEn = featuresEn.prefix(3).joined(separator: ", ")

        if hasServerDiffusion {
            subheadlineZh = "文件内识别出 \(featureSummaryZh)。这表明你的设备不仅具备完整 Apple 智能准入，且在触发复杂图像消除时已通过 OHTTP 盲签名与美区代理规则成功调度 Apple PCC 云端扩散模型（server_diffusion），分流配置健康无拦截。"
            subheadlineEn = "Detected \(featureSummaryEn). Calling PCC server_diffusion proves device eligibility, OHTTP blind-token issuance, and proxy routing to Apple PCC are working properly."
        } else if pccCount > 0 {
            subheadlineZh = "主要涉及功能：\(featureSummaryZh)。PCC 请求成功落账说明盲签名令牌签发（issuer.apple.com）、OHTTP 中继（mask-api / apple-relay）与区域准入均处于正常工作状态。"
            subheadlineEn = "Detected capabilities: \(featureSummaryEn). Presence of PCC requests confirms blind-token issuance, OHTTP relay routing, and regional eligibility are operational."
        } else {
            subheadlineZh = "识别到功能：\(featureSummaryZh)。这些任务算力完全由本机芯片 ANE 承接，无需经过 Apple 私有云服务器。"
            subheadlineEn = "Detected capabilities: \(featureSummaryEn). Executed entirely on-device without requiring Apple PCC offload."
        }

        // 4 structured plain-language conclusion bullets
        let bullet1 = ReportConclusionBullet(
            id: "capability-routing",
            icon: "sparkles",
            titleZh: "1. 触发功能与端云判定",
            titleEn: "1. Capabilities & Routing",
            detailZh: pccCount > 0
                ? "共解析 \(total) 条活动，涉及：\(featureSummaryZh)。其中 \(pccCount) 条进入 Apple PCC 云端模型，\(onDeviceCount) 条在端侧本地完成，端云分级与准入状态正常。"
                : "共解析 \(total) 条活动，涉及：\(featureSummaryZh)。全部由端侧基础模型本地执行（若未触发大模型扩展/高阶消除，系统默认优先纯本地完成）。",
            detailEn: pccCount > 0
                ? "Analyzed \(total) event(s) (\(featureSummaryEn)): \(pccCount) routed to Apple PCC cloud, \(onDeviceCount) on-device."
                : "Analyzed \(total) event(s) (\(featureSummaryEn)): all executed locally on device."
        )

        let bullet2 = ReportConclusionBullet(
            id: "privacy-boundary",
            icon: "lock.shield.fill",
            titleZh: "2. 隐私边界与数据流向",
            titleEn: "2. Privacy & Data Boundary",
            detailZh: pccCount > 0
                ? "云端部分通过 OHTTP 匿名中继 stripping IP 并经无状态 Apple Silicon 节点加密执行，处理完即时销毁且不与你的 Apple ID 关联；端侧部分全程零联网。"
                : "本次记录的推理输入与输出全部留在设备本地内存中完成，零数据上传至 Apple 服务器或第三方 API。",
            detailEn: pccCount > 0
                ? "Cloud sub-requests stripped client identity via OHTTP blind tokens and ran on stateless zero-retention PCC enclaves; local tasks stayed offline."
                : "All inputs and inference stayed in local device memory with zero network egress."
        )

        let payloadDetailZh: String
        let payloadDetailEn: String
        if promptCount > 0 || toolCount > 0 {
            payloadDetailZh = "共解码出 \(promptCount) 段隐藏系统/角色提示词与 \(toolCount) 次 AppIntents 工具调用，可在下方逐条展开查看完整上下文与思考预算。"
            payloadDetailEn = "Decoded \(promptCount) structured prompt block(s) and \(toolCount) AppIntents tool call(s) across the inspected requests."
        } else if hasVisualTasks {
            payloadDetailZh = "未见对话文本 Prompt（Prompt = 0）是因为本次捕获主要是相册消除/视觉扩散或音频类任务，传输的是图像掩码或张量数据而非文字聊天提示词，属正常结构。"
            payloadDetailEn = "Prompt count is 0 because captured tasks are visual diffusion/non-text workloads sending image mask tensors rather than text dialogue prompts."
        } else {
            payloadDetailZh = "本导出文件仅保留了请求标识、模型与端云路由元数据，系统未在 JSON 内写入明文 Prompt 文本内容。"
            payloadDetailEn = "This JSON export logged request IDs, models, and routing metadata without embedding plaintext prompts."
        }
        let bullet3 = ReportConclusionBullet(
            id: "payload-prompts",
            icon: "text.bubble.fill",
            titleZh: "3. 提示词与载荷说明",
            titleEn: "3. Prompts & Payloads",
            detailZh: payloadDetailZh,
            detailEn: payloadDetailEn
        )

        let windowTextZh: String
        let windowTextEn: String
        if let span = report.timeSpan {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            let startStr = f.string(from: span.start)
            let endStr = f.string(from: span.end)
            let spanStr = startStr == endStr ? startStr : "\(startStr) – \(endStr)"
            windowTextZh = "记录时间窗：\(spanStr)。"
            windowTextEn = "Capture window: \(spanStr)."
        } else {
            windowTextZh = "JSON 中未附带具体时间戳字段。"
            windowTextEn = "No request timestamps embedded."
        }

        let attestDetailZh: String
        let attestDetailEn: String
        if attCount > 0 {
            attestDetailZh = "\(windowTextZh)已原生解码 \(attCount) 组 PCC 硬件 AttestationBundle 与 X.509 节点证书链，证明云端算力节点运行经透明日志背书的 Apple 官方镜像。"
            attestDetailEn = "\(windowTextEn) Decoded \(attCount) hardware AttestationBundle(s) with X.509 node chains proving verifiable PCC runtime integrity."
        } else if pccCount > 0 {
            attestDetailZh = "\(windowTextZh)本次导出的 PCC 记录为轻量路由元数据，未内嵌 Base64 AttestationBundle（部分 iOS 子系统或系统版本在特定视觉管线中仅导出摘要记录）。"
            attestDetailEn = "\(windowTextEn) Exported PCC entries contain routing metadata without embedded Base64 AttestationBundles."
        } else {
            let assetNoteZh = report.assets.isEmpty ? "" : " 另记录了 \(report.assets.count) 项本地模型资产。"
            let assetNoteEn = report.assets.isEmpty ? "" : " Also logged \(report.assets.count) local model asset(s)."
            attestDetailZh = "\(windowTextZh)纯端侧任务不生成云端 PCC 硬件证明（Attestation = 0 正常）。\(assetNoteZh)"
            attestDetailEn = "\(windowTextEn) Pure on-device tasks do not generate cloud AttestationBundles (Attestation = 0 is expected).\(assetNoteEn)"
        }
        let bullet4 = ReportConclusionBullet(
            id: "attestation-window",
            icon: "checkmark.seal.fill",
            titleZh: "4. 节点证明与时间窗",
            titleEn: "4. Attestation & Timeline",
            detailZh: attestDetailZh,
            detailEn: attestDetailEn
        )

        return ReportExecutiveSummary(
            tone: tone,
            badgeZh: badgeZh,
            badgeEn: badgeEn,
            headlineZh: headlineZh,
            headlineEn: headlineEn,
            subheadlineZh: subheadlineZh,
            subheadlineEn: subheadlineEn,
            detectedFeaturesZh: featuresZh,
            detectedFeaturesEn: featuresEn,
            bullets: [bullet1, bullet2, bullet3, bullet4]
        )
    }

    // MARK: - Feature & Client Classification Helpers

    private struct FeatureDescriptor {
        let titleZh: String
        let titleEn: String
        let icon: String
        let isVisualOrNonTextTask: Bool
        let isAudioTask: Bool
        let narrativeZh: String
        let narrativeEn: String
    }

    private static func classifyFeature(for req: ParsedModelRequestItem) -> FeatureDescriptor {
        let combined = [
            req.useCase,
            req.modelIdentifier ?? "",
            req.pipelineKind ?? "",
            req.pipelineParameters ?? ""
        ].joined(separator: " ").lowercased()

        let isPCC = req.executionTarget == .privateCloudCompute

        if combined.contains("photosedit.infill") || combined.contains("cleanup") || combined.contains("inpaint") || combined.contains("server_diffusion") {
            let isServerDiffusion = combined.contains("server_diffusion") || isPCC
            return FeatureDescriptor(
                titleZh: "相册 · 高质量智能消除 (Photos Clean Up)",
                titleEn: "Photos · High-Quality Clean Up (Infill)",
                icon: "wand.and.stars",
                isVisualOrNonTextTask: true,
                isAudioTask: false,
                narrativeZh: isServerDiffusion
                    ? "这是你在「照片」App 使用「消除」涂抹较大或背景复杂的对象时，系统自动升级调用 Apple Private Cloud Compute 云端视觉扩散模型（server_diffusion）完成的重绘补全。这条记录同时实证你的设备已完整走通 Apple 智能准入、OHTTP 盲签名与 PCC 云端通道。"
                    : "这是「照片」App 在端侧对局部干扰物执行快速视觉分割与图像补全（Infill）推理的记录，未触发云端升级。",
                narrativeEn: isServerDiffusion
                    ? "Triggered when Photos Clean Up escalated a complex object removal to Apple PCC's server_diffusion model—directly proving eligibility, OHTTP blind tokens, and PCC cloud routing work end-to-end."
                    : "Executed by Photos Clean Up locally using on-device visual segmentation and infill models."
            )
        }

        if combined.contains("visualgeneration") || combined.contains("imageplayground") || combined.contains("genmoji") || combined.contains("diffusion") {
            return FeatureDescriptor(
                titleZh: "图像生成 / Genmoji 视觉模型",
                titleEn: "Visual Generation / Genmoji",
                icon: "photo.artframe",
                isVisualOrNonTextTask: true,
                isAudioTask: false,
                narrativeZh: isPCC
                    ? "由视觉生成管线在 Apple PCC 云端扩散集群完成的图像创作或风格重绘请求。"
                    : "由设备本地神经网络引擎 (ANE) 视觉扩散模型完成的 Image Playground 或 Genmoji 生成请求。",
                narrativeEn: isPCC
                    ? "Visual diffusion generation executed via Apple Private Cloud Compute."
                    : "On-device visual diffusion task for Image Playground or Genmoji."
            )
        }

        if combined.contains("writingtools") || combined.contains("proofread") || combined.contains("rewrite") {
            return FeatureDescriptor(
                titleZh: "写作工具 (Writing Tools 润色与改写)",
                titleEn: "Writing Tools (Rewrite / Proofread)",
                icon: "pencil.and.outline",
                isVisualOrNonTextTask: false,
                isAudioTask: false,
                narrativeZh: isPCC
                    ? "用户触发写作工具文本改写/校对或扩展调度，因上下文长度或复杂指令要求已加密发送至 Apple PCC 服务端语言模型处理。"
                    : "由本机端侧 Foundation 语言模型直接完成的写作工具校对、语气调整或改写操作。",
                narrativeEn: isPCC
                    ? "Writing Tools task offloaded to Apple PCC server LLM for extended reasoning."
                    : "Writing Tools rewrite/proofread executed locally by on-device Foundation Model."
            )
        }

        if combined.contains("summarize") || combined.contains("summarization") {
            return FeatureDescriptor(
                titleZh: "智能摘要 (邮件 / 通知 / 文本总结)",
                titleEn: "Smart Summarization",
                icon: "text.alignleft",
                isVisualOrNonTextTask: false,
                isAudioTask: false,
                narrativeZh: isPCC
                    ? "对长文章、邮件线程或网页内容调用 Apple PCC 云端摘要适配器生成结构化要点。"
                    : "在端侧语言模型完成的邮件、通知或备忘录快速摘要提取。",
                narrativeEn: isPCC
                    ? "Summarization executed via Apple PCC server adapter."
                    : "Fast summarization executed locally by on-device Foundation Model."
            )
        }

        if combined.contains("smartreply") || combined.contains("reply") {
            return FeatureDescriptor(
                titleZh: "智能回复建议",
                titleEn: "Smart Reply Suggestions",
                icon: "arrowshape.turn.up.left",
                isVisualOrNonTextTask: false,
                isAudioTask: false,
                narrativeZh: "根据近期对话上下文由 Apple 智能生成的快捷回复候选方案。",
                narrativeEn: "Context-aware quick reply generation powered by Apple Intelligence."
            )
        }

        if combined.contains("siri") || combined.contains("appintents") {
            return FeatureDescriptor(
                titleZh: "Siri 与跨应用意图推理 (App Intents)",
                titleEn: "Siri & App Intents Orchestration",
                icon: "sparkles",
                isVisualOrNonTextTask: false,
                isAudioTask: false,
                narrativeZh: isPCC
                    ? "Siri 将复杂跨应用意图与上下文委托给 Apple PCC 私有云大模型编排，并协同系统 AppIntents 工具链查询/响应。"
                    : "Siri 在本地完成的屏幕上下文理解与 AppIntents 意图解析。",
                narrativeEn: isPCC
                    ? "Siri delegated complex AppIntents reasoning to Apple PCC cloud models."
                    : "On-device Siri intent resolution and AppIntents dispatch."
            )
        }

        if combined.contains("transcribe") || combined.contains("call") || combined.contains("audio") {
            return FeatureDescriptor(
                titleZh: "录音转写与音频摘要",
                titleEn: "Audio Transcription & Call Summary",
                icon: "waveform",
                isVisualOrNonTextTask: true,
                isAudioTask: true,
                narrativeZh: "系统对通话录音或语音备忘录执行声学识别并生成结构化纪要。",
                narrativeEn: "Speech-to-text transcription and audio summary generation."
            )
        }

        if combined.contains("privatecloudcompute") || combined.contains("tie-cloudboard") {
            return FeatureDescriptor(
                titleZh: "Apple PCC 私有云推理调度",
                titleEn: "Apple PCC Private Cloud Inference",
                icon: "lock.icloud",
                isVisualOrNonTextTask: false,
                isAudioTask: false,
                narrativeZh: "由 CloudBoard / TIE (The Inference Engine) 网关调度执行的 Apple PCC 云端高阶推理请求。",
                narrativeEn: "Server inference dispatched through CloudBoard / TIE inside Apple PCC."
            )
        }

        return FeatureDescriptor(
            titleZh: isPCC ? "Apple PCC 云端大模型推理" : "端侧 Apple Foundation 模型推理",
            titleEn: isPCC ? "Apple PCC Server Model Inference" : "On-Device Apple Foundation Model",
            icon: isPCC ? "icloud.and.arrow.up" : "cpu",
            isVisualOrNonTextTask: false,
            isAudioTask: false,
            narrativeZh: isPCC
                ? "高复杂度任务已加密路由至 Apple Private Cloud Compute 云端执行（用例标识：\(req.useCase)）。"
                : "通用 AI 任务在本机芯片 ANE 本地模型上运行（用例标识：\(req.useCase)）。",
            narrativeEn: isPCC
                ? "Request routed to Apple PCC server inference (\(req.useCase))."
                : "Request executed locally on Apple Silicon ANE (\(req.useCase))."
        )
    }

    private static func mapClientApp(_ rawIdentifier: String?) -> (zh: String, en: String)? {
        guard let raw = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        let mappings: [(needle: String, zh: String, en: String)] = [
            ("mobileslideshow", "照片 App (Photos)", "Photos"),
            ("com.apple.photos", "照片 App (Photos)", "Photos"),
            ("safari", "Safari 浏览器", "Safari"),
            ("mobilemail", "邮件 App (Mail)", "Mail"),
            ("com.apple.mail", "邮件 App (Mail)", "Mail"),
            ("mobilenotes", "备忘录 (Notes)", "Notes"),
            ("com.apple.notes", "备忘录 (Notes)", "Notes"),
            ("messages", "信息 App (Messages)", "Messages"),
            ("mobilesms", "信息 App (Messages)", "Messages"),
            ("siri", "Siri", "Siri"),
            ("assistant", "Siri", "Siri")
        ]
        for entry in mappings where lower.contains(entry.needle) {
            return (entry.zh, entry.en)
        }
        return (raw, raw)
    }
}
