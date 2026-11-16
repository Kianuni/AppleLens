import AppKit
import AppleLensCore
import SwiftUI

// MARK: - Design Tokens

enum LensTheme {
    /// On-device ANE inference — Ice-Emerald
    static let emerald = Color(red: 0.08, green: 0.67, blue: 0.49)
    /// Apple Private Cloud Compute — Glacier-Sapphire
    static let sapphire = Color(red: 0.14, green: 0.50, blue: 0.94)
    /// External LLM API / Caution — Champagne-Gold
    static let amber = Color(red: 0.87, green: 0.61, blue: 0.16)
    /// Critical Block / MitM Detected — Signal Coral
    static let coral = Color(red: 0.90, green: 0.29, blue: 0.26)
    /// Hybrid State / System Instruction — Muted Indigo-Violet
    static let plum = Color(red: 0.54, green: 0.41, blue: 0.85)

    static let hairline = Color.primary.opacity(0.08)
    static let hairlineStrong = Color.primary.opacity(0.14)
}

extension RadarOverallState {
    var tintColor: Color {
        switch self {
        case .idle: return .secondary
        case .onDevice: return LensTheme.emerald
        case .applePCC: return LensTheme.sapphire
        case .externalLLM: return LensTheme.amber
        case .hybrid: return LensTheme.plum
        }
    }

    func shortBadgeLabel(lang: AppLanguage) -> String {
        switch self {
        case .idle: return tr("待机", "Idle", lang: lang)
        case .onDevice: return tr("端侧", "ANE", lang: lang)
        case .applePCC: return "PCC"
        case .externalLLM: return tr("外连", "Ext AI", lang: lang)
        case .hybrid: return tr("混合", "Hybrid", lang: lang)
        }
    }
}

/// Strips legacy emoji status prefixes when rendering core telemetry lines in crisp native chrome.
func cleanTelemetryLine(_ raw: String) -> String {
    let prefixes = ["🟢 ", "🔵 ", "🟠 ", "⚪️ ", "🔴 ", "🟡 "]
    for prefix in prefixes where raw.hasPrefix(prefix) {
        return String(raw.dropFirst(prefix.count))
    }
    return raw
}

// MARK: - Behind-Window Vibrancy Backdrop

struct VibrancyBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Precision Indicator & Mini Prism Emblem

struct PulseIndicatorDot: View {
    let color: Color
    var isActive: Bool = true
    var size: CGFloat = 7

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(color.opacity(0.24))
                    .frame(width: size * 2.1, height: size * 2.1)
            }
            Circle()
                .fill(isActive ? color : Color.secondary.opacity(0.42))
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.2, height: size * 2.2)
    }
}

/// Crisp geometric optical prism emblem inspired by the AppleLens app icon.
struct MiniPrismEmblem: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.38), LensTheme.hairlineStrong],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )

            Canvas { ctx, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height

                // Incoming monochrome probe ray (top-left into left facet)
                var inRay = Path()
                inRay.move(to: CGPoint(x: w * 0.10, y: h * 0.56))
                inRay.addLine(to: CGPoint(x: w * 0.38, y: h * 0.50))
                ctx.stroke(inRay, with: .color(Color.primary.opacity(0.65)), lineWidth: max(1.0, size * 0.055))

                // Equilateral optical prism silhouette
                let apex = CGPoint(x: w * 0.50, y: h * 0.20)
                let bottomLeft = CGPoint(x: w * 0.24, y: h * 0.76)
                let bottomRight = CGPoint(x: w * 0.76, y: h * 0.76)

                var prism = Path()
                prism.move(to: apex)
                prism.addLine(to: bottomRight)
                prism.addLine(to: bottomLeft)
                prism.closeSubpath()

                ctx.fill(
                    prism,
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.28), LensTheme.sapphire.opacity(0.14)]),
                        startPoint: apex,
                        endPoint: bottomRight
                    )
                )
                ctx.stroke(prism, with: .color(Color.primary.opacity(0.45)), lineWidth: max(0.85, size * 0.04))

                // Three refracted spectrum filaments (Ice-Emerald, Glacier-Sapphire, Champagne-Gold)
                let exitTop = CGPoint(x: w * 0.61, y: h * 0.45)
                let filaments: [(CGFloat, Color)] = [
                    (0.32, LensTheme.emerald),
                    (0.50, LensTheme.sapphire),
                    (0.68, LensTheme.amber)
                ]
                for (endYRatio, color) in filaments {
                    var ray = Path()
                    ray.move(to: exitTop)
                    ray.addLine(to: CGPoint(x: w * 0.90, y: h * endYRatio))
                    ctx.stroke(
                        ray,
                        with: .color(color.opacity(0.95)),
                        style: StrokeStyle(lineWidth: max(1.0, size * 0.05), lineCap: .round)
                    )
                }
            }
            .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Sticky Frosted Header & Liquid Glass Helpers

struct GlassHeaderBar<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let actions: () -> Actions

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                LensActionCluster {
                    actions()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            Rectangle()
                .fill(LensTheme.hairline)
                .frame(height: 0.75)
        }
    }
}

struct LensActionCluster<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                HStack(spacing: spacing) {
                    content()
                }
            }
        } else {
            HStack(spacing: spacing) {
                content()
            }
        }
    }
}

struct LensCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color = LensTheme.sapphire

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background {
                if prominent {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.78)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: tint.opacity(0.20), radius: 5, y: 1.5)
                } else {
                    ZStack {
                        Capsule()
                            .fill(.ultraThinMaterial)
                        Capsule()
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.055))
                    }
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        prominent
                            ? LinearGradient(colors: [Color.white.opacity(0.36), Color.white.opacity(0.14)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.white.opacity(0.28), LensTheme.hairlineStrong], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75
                    )
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1.0) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func lensGlassButton(prominent: Bool = false, tint: Color = LensTheme.sapphire) -> some View {
        self.buttonStyle(LensCapsuleButtonStyle(prominent: prominent, tint: tint))
    }

    @ViewBuilder
    func lensFloatingGlass(cornerRadius: CGFloat = 16) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), LensTheme.hairlineStrong],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        }
    }

    @ViewBuilder
    func lensWindowContainerMaterial() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.thinMaterial, for: .window)
        } else {
            self
        }
    }
}

// MARK: - Frosted Surface Card & Inset Code Well

struct SurfaceCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 14
    @ViewBuilder let content: () -> Content

    init(
        tint: Color? = nil,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 14,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.055))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                tint?.opacity(0.24) ?? LensTheme.hairlineStrong
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct InsetCodeWell<Content: View>: View {
    var maxHeight: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    init(maxHeight: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.maxHeight = maxHeight
        self.content = content
    }

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxHeight)
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.038), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LensTheme.hairline, lineWidth: 0.75)
        )
        .textSelection(.enabled)
    }
}

// MARK: - Semantic Badges & Restrained Neutral Meta Pills

struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.6))
    }
}

/// Restrained neutral metadata pill for technical tags so semantic alerts remain focal.
struct MetaPill: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(LensTheme.hairline, lineWidth: 0.5))
    }
}

@MainActor
func radarPollIntervalText(radar: TriStateRadarCoordinator, lang: AppLanguage) -> String {
    if radar.isPausedForSystemSleep {
        return tr("休眠暂停", "Sleep Paused", lang: lang)
    }
    let interval = radar.currentPollIntervalSeconds
    if abs(interval - interval.rounded()) < 0.05 {
        return "\(Int(interval.rounded()))s"
    }
    return String(format: "%.1fs", interval)
}

struct CopyActionButton: View {
    let title: String
    let copiedTitle: String
    var icon: String = "doc.on.doc"
    var useGlassStyle: Bool = false
    let action: () -> Void

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        buttonView
            .controlSize(.small)
            .onDisappear {
                resetTask?.cancel()
                resetTask = nil
            }
    }

    @ViewBuilder
    private var buttonView: some View {
        let btn = Button {
            action()
            copied = true
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            Label(
                copied ? copiedTitle : title,
                systemImage: copied ? "checkmark" : icon
            )
            .font(.caption.weight(.medium))
        }

        if useGlassStyle {
            btn.lensGlassButton(prominent: false)
        } else {
            btn.buttonStyle(.bordered)
        }
    }
}

struct CopySnippetButton: View {
    let text: String
    let lang: AppLanguage
    let onCopy: (String) -> Void

    var body: some View {
        CopyActionButton(
            title: tr("复制", "Copy", lang: lang),
            copiedTitle: tr("已复制", "Copied", lang: lang)
        ) {
            onCopy(text)
        }
    }
}

struct SettingsPreferencesMenu: View {
    @Bindable var viewModel: AppViewModel
    var compact: Bool = false

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        Menu {
            Toggle(
                tr("关闭窗口隐藏程序坞图标", "Hide Dock When Closed", lang: lang),
                isOn: $viewModel.hideDockWhenClosed
            )

            Button {
                viewModel.toggleLaunchAtLogin()
            } label: {
                if viewModel.isLaunchAtLoginEnabled {
                    Label(tr("开机自启动（已开启）", "Launch at Login (On)", lang: lang), systemImage: "checkmark")
                } else {
                    Label(tr("开机自启动", "Launch at Login", lang: lang), systemImage: "power")
                }
            }

            Divider()

            Button {
                Task { await viewModel.checkForUpdates() }
            } label: {
                Label(
                    viewModel.isCheckingUpdate
                        ? tr("正在检查更新…", "Checking for Updates…", lang: lang)
                        : tr("检查更新", "Check for Updates", lang: lang),
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(viewModel.isCheckingUpdate)

            if let msg = viewModel.updateStatusMessage {
                Divider()
                Text(msg)
                if let releaseURL = viewModel.latestReleaseURL {
                    Button {
                        viewModel.openExternalURL(releaseURL)
                    } label: {
                        Label(tr("前往下载页面", "Open Release Page", lang: lang), systemImage: "arrow.up.right.square")
                    }
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("偏好设置与更新", "Preferences & Updates", lang: lang))
    }
}

struct UpdateStatusNoticeBar: View {
    @Bindable var viewModel: AppViewModel
    var compact: Bool = false

    private var lang: AppLanguage { viewModel.lang }

    var body: some View {
        if let message = viewModel.updateStatusMessage {
            HStack(spacing: 8) {
                Image(systemName: viewModel.latestReleaseURL != nil ? "arrow.down.circle.fill" : "info.circle.fill")
                    .font(.system(size: compact ? 11.5 : 12.5))
                    .foregroundStyle(LensTheme.sapphire)

                Text(message)
                    .font(.system(size: compact ? 11 : 12))
                    .lineLimit(2)

                Spacer(minLength: 4)

                if let releaseURL = viewModel.latestReleaseURL {
                    Button(tr("查看", "Download", lang: lang)) {
                        viewModel.openExternalURL(releaseURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Button {
                    viewModel.updateStatusMessage = nil
                    viewModel.latestReleaseURL = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 7 : 8)
            .background(LensTheme.sapphire.opacity(0.08))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(LensTheme.hairline)
                    .frame(height: 0.75)
            }
        }
    }
}

struct LanguageToggleButton: View {
    @Bindable var manager: LanguageManager

    var body: some View {
        Button {
            manager.current = (manager.current == .zhHans) ? .en : .zhHans
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                Text(manager.current.shortLabel)
                    .font(.system(size: 11.5, weight: .semibold))
            }
        }
        .lensGlassButton(prominent: false)
        .controlSize(.small)
        .help(tr("切换中/英界面语言", "Switch UI Language (ZH/EN)", lang: manager.current))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
