import AppleLensCore
import SwiftUI

struct ReportInspectorTabsView: View {
    @Bindable var viewModel: AppViewModel
    let request: ParsedModelRequestItem
    let assets: [ParsedModelAssetItem]

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            requestSummaryCard(request)

            Picker("", selection: $viewModel.selectedReportInspectorTab) {
                ForEach(ReportInspectorTab.allCases) { tab in
                    Text(tab.title(lang: lang)).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch viewModel.selectedReportInspectorTab {
            case .promptsAndTools:
                promptsAndToolsView(request)
            case .attestationAndX509:
                attestationAndX509View(request)
            case .sealedHashesAndJSON:
                sealedHashesAndJSONView(request, assets: assets)
            }
        }
    }

    // MARK: - Request Summary Card

    private func requestSummaryCard(_ req: ParsedModelRequestItem) -> some View {
        let accent = req.executionTarget == .privateCloudCompute ? LensTheme.sapphire : LensTheme.emerald
        let interp = ReportInsightEngine.interpret(request: req)
        return SurfaceCard(tint: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: interp.categoryIcon)
                                .foregroundStyle(accent)
                            Text(interp.featureTitle(lang: lang))
                                .font(.system(size: 15, weight: .semibold))
                            StatusBadge(text: req.executionTarget.label(lang: lang), color: accent)
                        }

                        FlowMetaRow(pills: buildMetaPills(for: req, interp: interp))
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(accent)
                            .padding(.top, 1)
                        Text(interp.narrative(lang: lang))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 12))
                            .foregroundStyle(LensTheme.emerald)
                            .padding(.top, 1)
                        Text(interp.privacyGuarantee(lang: lang))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func buildMetaPills(for req: ParsedModelRequestItem, interp: RequestPlainInterpretation) -> [String] {
        var pills: [String] = []
        pills.append(req.useCase)
        if let app = interp.clientApp(lang: lang) {
            pills.append(tr("来源：", "App: ", lang: lang) + app)
        }
        if let model = req.modelIdentifier {
            pills.append(tr("模型：", "Model: ", lang: lang) + model)
        }
        if let pipeline = req.pipelineKind {
            pills.append(tr("通道：", "Pipeline: ", lang: lang) + pipeline)
        }
        if let ts = req.timestamp {
            pills.append(ts.formatted(date: .abbreviated, time: .standard))
        }
        return pills
    }

    // MARK: - Tab 1: Prompts & Tool Calls

    private func promptsAndToolsView(_ req: ParsedModelRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: tr("Prompt 消息链与隐藏系统指令 (\(req.promptBlocks.count))", "Prompt Chain & Hidden System Instructions (\(req.promptBlocks.count))", lang: lang),
                icon: "text.bubble"
            )

            if req.promptBlocks.isEmpty {
                let interp = ReportInsightEngine.interpret(request: req)
                SurfaceCard(tint: LensTheme.sapphire, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(LensTheme.sapphire)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("为什么这里没有对话 Prompt？", "Why Are There 0 Text Prompts?", lang: lang))
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(interp.emptyPromptExplanation(lang: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        LensActionCluster(spacing: 8) {
                            if !req.pccRequests.isEmpty {
                                Button {
                                    viewModel.selectedReportInspectorTab = .attestationAndX509
                                } label: {
                                    Label(tr("查看 CloudAttestation 与证书链", "View CloudAttestation & X.509", lang: lang), systemImage: "checkmark.seal")
                                }
                                .lensGlassButton(prominent: false, tint: LensTheme.sapphire)
                                .controlSize(.small)
                            }

                            Button {
                                viewModel.selectedReportInspectorTab = .sealedHashesAndJSON
                            } label: {
                                Label(tr("查看原始 JSON 载荷", "Inspect Raw JSON Payload", lang: lang), systemImage: "curlybraces")
                            }
                            .lensGlassButton(prominent: false)
                            .controlSize(.small)
                        }
                    }
                }
            }

            ForEach(req.promptBlocks) { block in
                let roleColor = promptRoleColor(block.role)
                SurfaceCard(tint: roleColor, padding: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            StatusBadge(text: block.role.label(lang: lang), color: roleColor)
                            if let budget = block.silentTokenBudget {
                                MetaPill(text: "Silent Budget: \(budget) tok")
                            }
                            Spacer()
                            CopySnippetButton(text: block.content, lang: lang) {
                                viewModel.copyToPasteboard($0)
                            }
                        }
                        Text(block.content)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !req.toolCalls.isEmpty {
                SectionHeader(
                    title: tr("工具调用链 Tool Calling (\(req.toolCalls.count))", "Tool Call Chain (\(req.toolCalls.count))", lang: lang),
                    icon: "wrench.and.screwdriver"
                )

                ForEach(req.toolCalls) { tool in
                    SurfaceCard(tint: LensTheme.amber, padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(tool.name, systemImage: "function")
                                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                                Spacer()
                                CopySnippetButton(text: tool.argumentsJSON, lang: lang) {
                                    viewModel.copyToPasteboard($0)
                                }
                            }
                            InsetCodeWell {
                                Text(tool.argumentsJSON)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            if let res = tool.resultPreview {
                                Text(tr("返回：", "Result: ", lang: lang) + res)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let response = req.responseText {
                SurfaceCard(tint: LensTheme.emerald, padding: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(title: tr("模型最终输出", "Final Model Output", lang: lang), icon: "quote.bubble")
                        Text(response)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: CloudAttestation & X.509

    private func attestationAndX509View(_ req: ParsedModelRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if req.pccRequests.isEmpty {
                SurfaceCard {
                    HStack(spacing: 10) {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(LensTheme.emerald)
                        Text(tr("此请求完全在端侧 Apple Silicon ANE 上完成推理，未产生 PCC 加密节点交互与 AttestationBundle。", "Executed 100% on-device via ANE; no PCC node attestation involved.", lang: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(req.pccRequests) { sub in
                    pccSubRequestCard(sub)
                }
            }
        }
    }

    private func pccSubRequestCard(_ sub: ParsedPCCSubRequest) -> some View {
        SurfaceCard(tint: LensTheme.sapphire) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(sub.endpoint ?? "Apple PCC Node")
                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    if let state = sub.requestState {
                        MetaPill(text: state)
                    }
                    if let bytes = sub.payloadBytes {
                        MetaPill(text: "\(bytes) B")
                    }
                    Spacer()
                }

                if let att = sub.attestation {
                    attestationDetailView(att)
                } else {
                    Text(tr("此 PCC 子请求未内嵌 Base64 CloudAttestation 字段。", "No Base64 CloudAttestation bundle embedded in this sub-request.", lang: lang))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func attestationDetailView(_ att: DecodedCloudAttestation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    StatusBadge(
                        text: tr(att.nodeRoleLabelZh, att.nodeRoleLabelEn, lang: lang),
                        color: LensTheme.sapphire,
                        icon: "lock.icloud.fill"
                    )
                    StatusBadge(
                        text: att.signatureStatus(lang: lang),
                        color: att.signatureChainVerified ? LensTheme.emerald : LensTheme.amber,
                        icon: att.signatureChainVerified ? "checkmark.shield.fill" : "exclamationmark.shield"
                    )
                    if att.apTicketHasIM4MMagic {
                        StatusBadge(text: "APTicket IM4M", color: LensTheme.emerald, icon: "checkmark.seal.fill")
                    }
                    if att.hasTransparencyProof {
                        StatusBadge(text: tr("KT 透明证明 \(att.transparencyProofBytes)B", "KT Proof \(att.transparencyProofBytes)B", lang: lang), color: LensTheme.plum)
                    }
                }
            }

            HStack(spacing: 12) {
                metricBox(title: tr("Bundle 体积", "Bundle Size", lang: lang), value: "\(att.rawBundleByteCount) B")
                metricBox(title: "SEP Attestation", value: "\(att.sepAttestationBytes) B")
                metricBox(title: "APTicket (SecureBoot)", value: "\(att.apTicketBytes) B")
                metricBox(title: tr("X.509 证书链", "X.509 Chain", lang: lang), value: "\(att.certificateChain.count)")
            }

            if let domain = att.appDataDomain {
                InsetCodeWell {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("节点域（AppData Domain）", "AppData Domain", lang: lang) + ": \(domain)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        if let exp = att.keyExpiration {
                            Text(tr("公钥过期时间：", "Key Expiration: ", lang: lang) + exp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if let sha = att.transparencyProofSHA256 {
                            Text("KT Proof SHA-256: \(sha)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !att.certificateChain.isEmpty {
                SectionHeader(title: tr("内嵌 X.509 硬件证明证书链", "Embedded X.509 Hardware Attestation Chain", lang: lang), icon: "checkmark.seal")

                ForEach(att.certificateChain) { cert in
                    HStack(spacing: 10) {
                        Text("#\(cert.indexInChain)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(LensTheme.sapphire)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cert.commonName.isEmpty ? cert.subjectSummary : cert.commonName)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("\(cert.organization) · \(cert.publicKeyAlgorithm)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("SHA-256: \(cert.sha256Fingerprint)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            StatusBadge(
                                text: cert.isAppleAnchored ? "Apple Anchored" : "Third-Party",
                                color: cert.isAppleAnchored ? LensTheme.emerald : LensTheme.amber
                            )
                            Text(cert.isCurrentlyValid ? tr("有效期内", "Valid", lang: lang) : tr("已过期", "Expired", lang: lang))
                                .font(.caption2)
                                .foregroundStyle(cert.isCurrentlyValid ? LensTheme.emerald : LensTheme.coral)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
                    )
                }
            }

            if !att.parseNotes.isEmpty {
                DisclosureGroup(tr("解码器结构注记 (\(att.parseNotes.count))", "Decoder Structural Notes (\(att.parseNotes.count))", lang: lang)) {
                    InsetCodeWell {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(att.parseNotes, id: \.self) { note in
                                Text("• \(note)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Tab 3: Sealed Hashes & Raw JSON

    private func sealedHashesAndJSONView(_ req: ParsedModelRequestItem, assets: [ParsedModelAssetItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let slots = req.pccRequests.compactMap(\.attestation).flatMap(\.sealedHashSlots)
            if !slots.isEmpty {
                SectionHeader(title: tr("Sealed Hash 节点运行映像哈希槽", "Sealed Hash Image Slots", lang: lang), icon: "number.square")

                ForEach(slots) { slot in
                    SurfaceCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(slot.slotName)
                                    .font(.system(size: 13, weight: .semibold))
                                MetaPill(text: slot.hashAlgorithm)
                                MetaPill(text: tr("\(slot.entryCount) 条 Cryptex 哈希", "\(slot.entryCount) digests", lang: lang))
                                Spacer()
                            }

                            if !slot.entryDigestsHex.isEmpty {
                                InsetCodeWell {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(slot.entryDigestsHex, id: \.self) { hex in
                                            Text(hex)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !assets.isEmpty {
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: tr("本地模型资产记录 (\(assets.count))", "Model Assets (\(assets.count))", lang: lang), icon: "shippingbox")
                        ForEach(assets) { asset in
                            HStack {
                                Text(asset.assetID)
                                    .font(.system(size: 11.5, design: .monospaced))
                                Spacer()
                                if let ver = asset.version {
                                    MetaPill(text: ver)
                                }
                                if let st = asset.status {
                                    MetaPill(text: st)
                                }
                            }
                        }
                    }
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(title: tr("原始请求 JSON 片段", "Raw Request JSON Snippet", lang: lang), icon: "curlybraces")
                        CopySnippetButton(text: req.rawJSONSnippet, lang: lang) {
                            viewModel.copyToPasteboard($0)
                        }
                    }
                    InsetCodeWell(maxHeight: 260) {
                        Text(req.rawJSONSnippet)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func metricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
        )
    }

    private func promptRoleColor(_ role: PromptRole) -> Color {
        switch role {
        case .system: return LensTheme.plum
        case .developer: return LensTheme.sapphire
        case .thought: return .secondary
        case .user: return LensTheme.emerald
        case .tool: return LensTheme.amber
        case .assistant: return LensTheme.sapphire
        case .raw: return .secondary
        }
    }
}

private struct FlowMetaRow: View {
    let pills: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pills, id: \.self) { pill in
                    MetaPill(text: pill)
                }
            }
        }
    }
}
