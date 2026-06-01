import AppKit
import SwiftUI

@main
struct BabyRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = RecordingViewModel(
        captureService: CaptureService(),
        transcriptionService: PythonMLXTranscriptionService()
    )
    @State private var runtimeSetupViewModel = RuntimeSetupViewModel()
    @State private var meetingAutoRecorder = MeetingAutoRecorder()

    var body: some Scene {
        Window("app.title", id: "main") {
            RootView(
                recordingViewModel: viewModel,
                runtimeSetupViewModel: runtimeSetupViewModel,
                meetingAutoRecorder: meetingAutoRecorder
            )
                .background(WindowCloseHider())
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

                Button("transcription.action.start") {
                    Task { await viewModel.transcribeLatestRecording() }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!viewModel.canTranscribe)
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
                meetingAutoRecorder: meetingAutoRecorder,
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
            viewModel.transcription.status == .running ? "text.magnifyingglass" : "waveform"
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if bringExistingMainWindowForward() {
            return
        }

        openWindow(id: "main")
        Task { @MainActor in
            await Task.yield()
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
    var completeTerminationAfterRecordingStop: @MainActor (Bool) -> Void = { shouldTerminate in
        NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
    }
    private var isCompletingRecordingQuit = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isCompletingRecordingQuit {
            return .terminateLater
        }

        guard let viewModel, viewModel.state == .recording else {
            return .terminateNow
        }

        guard confirmQuitWhileRecording() else {
            return .terminateCancel
        }

        isCompletingRecordingQuit = true
        Task { @MainActor [weak self, viewModel] in
            await viewModel.stopRecording()
            self?.isCompletingRecordingQuit = false
            self?.completeTerminationAfterRecordingStop(true)
        }

        return .terminateLater
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
