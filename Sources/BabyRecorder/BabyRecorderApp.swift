import AppKit
import SwiftUI

@main
struct BabyRecorderApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = RecordingViewModel(captureService: CaptureService())

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .task {
                    await viewModel.checkPermissions()
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
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
