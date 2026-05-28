import AppKit
import SwiftUI

struct WindowCloseHider: NSViewRepresentable {
    static let mainWindowIdentifier = "BabyRecorderMainWindow"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            await Task.yield()
            attachCoordinator(context.coordinator, to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            await Task.yield()
            attachCoordinator(context.coordinator, to: nsView.window)
        }
    }

    private func attachCoordinator(_ coordinator: Coordinator, to window: NSWindow?) {
        guard let window else {
            return
        }
        window.delegate = coordinator
        window.identifier = NSUserInterfaceItemIdentifier(Self.mainWindowIdentifier)
        window.minSize = NSSize(width: 640, height: 420)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }
}
