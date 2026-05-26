import SwiftUI

struct StatusBarMenuView: View {
    @ObservedObject var viewModel: RecordingViewModel
    let openMainWindow: () -> Void
    let quit: () -> Void

    private var presentation: RecordingPresentation {
        viewModel.presentation
    }

    var body: some View {
        Text(LocalizedStringKey(presentation.titleKey))

        Divider()

        primaryAction

        Button {
            openMainWindow()
        } label: {
            Label("menu.openMainWindow", systemImage: "macwindow")
        }

        Button {
            viewModel.revealOutputDirectory()
        } label: {
            Label("menu.revealLatestOutput", systemImage: "folder")
        }
        .disabled(!viewModel.canRevealOutputDirectory)

        Button {
            Task { await viewModel.checkPermissions() }
        } label: {
            Label("menu.recheckPermissions", systemImage: "arrow.clockwise")
        }

        Button {
            viewModel.openSystemSettings()
        } label: {
            Label("menu.openSystemSettings", systemImage: "gear")
        }

        Divider()

        Button {
            quit()
        } label: {
            Label("menu.quit", systemImage: "power")
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch presentation.primaryAction {
        case .start:
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("recording.action.start", systemImage: "record.circle")
            }
            .disabled(!viewModel.canStartRecording)
        case .stop:
            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("recording.action.stop", systemImage: "stop.circle")
            }
        case .openSettings:
            Button {
                viewModel.openSystemSettings()
            } label: {
                Label("recording.action.openSettings", systemImage: "gear")
            }
        case .none:
            EmptyView()
        }
    }
}
