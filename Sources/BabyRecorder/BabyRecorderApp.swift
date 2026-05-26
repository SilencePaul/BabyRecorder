import AppKit
import SwiftUI

@main
struct BabyRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = RecordingViewModel(captureService: CaptureService())

    var body: some Scene {
        Window("app.title", id: "main") {
            ContentView(viewModel: viewModel)
                .background(WindowCloseHider())
                .task {
                    await viewModel.checkPermissions()
                }
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 460)
        .commands {
            CommandMenu("menu.recording") {
                Button("recording.action.start") {
                    Task { await viewModel.startRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!viewModel.canStartRecording)

                Button("recording.action.stop") {
                    Task { await viewModel.stopRecording() }
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(viewModel.state != .recording)

                Divider()

                Button("menu.recheckPermissions") {
                    Task { await viewModel.checkPermissions() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("menu.revealLatestOutput") {
                    viewModel.revealOutputDirectory()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!viewModel.canRevealOutputDirectory)
            }

            CommandGroup(after: .windowArrangement) {
                Button("menu.openMainWindow") {
                    openMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            StatusBarMenuView(
                viewModel: viewModel,
                openMainWindow: openMainWindow,
                quit: {
                    NSApp.terminate(nil)
                }
            )
        } label: {
            Label("app.title", systemImage: statusBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var statusBarSymbolName: String {
        switch viewModel.state {
        case .recording:
            "record.circle.fill"
        case .permissionsMissing, .failed, .finishedWithMixFailure:
            "exclamationmark.circle"
        default:
            "waveform"
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if bringExistingMainWindowForward() {
            return
        }

        openWindow(id: "main")
        DispatchQueue.main.async {
            _ = bringExistingMainWindowForward()
        }
    }

    private func bringExistingMainWindowForward() -> Bool {
        guard let window = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == WindowCloseHider.mainWindowIdentifier
        }) else {
            return false
        }

        window.makeKeyAndOrderFront(nil)
        return true
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: RecordingViewModel?
    var confirmQuitWhileRecording: @MainActor () -> Bool = AppLifecycleDelegate.showQuitConfirmation

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel?.state == .recording else {
            return .terminateNow
        }

        return confirmQuitWhileRecording() ? .terminateNow : .terminateCancel
    }

    private static func showQuitConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "quit.confirm.title")
        alert.informativeText = String(localized: "quit.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "quit.confirm.quit"))
        alert.addButton(withTitle: String(localized: "quit.confirm.cancel"))

        return alert.runModal() == .alertFirstButtonReturn
    }
}
