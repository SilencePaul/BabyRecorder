import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: RecordingViewModel

    private var presentation: RecordingPresentation {
        viewModel.presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RecordingHeroView(
                presentation: presentation,
                canStartRecording: viewModel.canStartRecording,
                startRecording: viewModel.startRecording,
                stopRecording: viewModel.stopRecording,
                openSystemSettings: viewModel.openSystemSettings
            )

            HStack(alignment: .top, spacing: 16) {
                PermissionsPanel(
                    permissionRows: presentation.permissionRows,
                    recordingStateTitleKey: presentation.titleKey,
                    recordingStateTone: statusTone,
                    checkPermissions: viewModel.checkPermissions,
                    openSystemSettings: viewModel.openSystemSettings
                )

                OutputPanel(
                    outputDirectory: viewModel.outputDirectory,
                    validationText: validationText,
                    validationTone: validationTone,
                    canRevealOutputDirectory: viewModel.canRevealOutputDirectory,
                    revealOutputDirectory: viewModel.revealOutputDirectory
                )
            }

            TranscriptionPanel(
                outputDirectory: viewModel.outputDirectory,
                transcription: viewModel.transcription,
                selectedTranscriptionMode: $viewModel.selectedTranscriptionMode,
                selectedTranscriptionModel: $viewModel.selectedTranscriptionModel,
                canTranscribe: viewModel.canTranscribe,
                transcribeLatestRecording: viewModel.transcribeLatestRecording
            )

            if presentation.showsFailureMessage, let message = presentation.failureMessage {
                FailureMessageView(message: message)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(Text("app.title"))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusTone: StatusTone {
        switch presentation.kind {
        case .ready, .finished:
            .success
        case .permissionsMissing, .finishedWithMixFailure:
            .warning
        case .failed:
            .failure
        case .checkingPermissions, .starting, .recording, .stopping:
            .neutral
        }
    }

    private var validationText: LocalizedStringKey {
        switch presentation.validationStatus {
        case .notAvailable:
            "validation.notAvailable"
        case .passed:
            "validation.passed"
        case .failed:
            "validation.failed"
        }
    }

    private var validationTone: StatusTone {
        switch presentation.validationStatus {
        case .notAvailable:
            .neutral
        case .passed:
            .success
        case .failed:
            .failure
        }
    }
}
