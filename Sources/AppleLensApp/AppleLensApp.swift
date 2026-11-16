import AppKit
import AppleLensCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppleLensAppDelegate: NSObject, NSApplicationDelegate {
    var openWorkbench: (@MainActor () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if sender.activationPolicy() != .regular {
            sender.setActivationPolicy(.regular)
        }
        for window in sender.windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !flag {
            openWorkbench?()
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

private struct WorkbenchReopenRegistrar: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppleLensAppDelegate

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.openWorkbench = { [openWindow] in
                if NSApplication.shared.activationPolicy() != .regular {
                    NSApplication.shared.setActivationPolicy(.regular)
                }
                openWindow(id: "workbench")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}

@main
struct AppleLensApp: App {
    @NSApplicationDelegateAdaptor(AppleLensAppDelegate.self) private var appDelegate
    @State private var viewModel = AppViewModel()
    @State private var isDropTargeted = false

    var body: some Scene {
        Window("AppleLens", id: "workbench") {
            WorkbenchView(viewModel: viewModel, isDropTargeted: isDropTargeted)
                .frame(minWidth: 960, minHeight: 640)
                .lensWindowContainerMaterial()
                .modifier(WorkbenchReopenRegistrar(appDelegate: appDelegate))
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    viewModel.handleDroppedProviders(providers)
                }
                .onOpenURL { url in
                    viewModel.prepareForWorkbenchOpen()
                    viewModel.importFile(url: url)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 740)

        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
                .frame(width: 400, height: 520)
                .modifier(WorkbenchReopenRegistrar(appDelegate: appDelegate))
        } label: {
            HStack(spacing: 4) {
                if viewModel.radar.overallState != .idle {
                    Image(nsImage: Self.menuBarStatusDot(for: viewModel.radar.overallState))
                }
                Image(systemName: viewModel.radar.overallState.sfSymbol)
                if let badge = viewModel.menuBarBadgeText {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static func menuBarStatusDot(for state: RadarOverallState) -> NSImage {
        let size = NSSize(width: 7, height: 7)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(state.tintColor).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
