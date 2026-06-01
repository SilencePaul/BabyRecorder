import SwiftUI

struct ContentView: View {
    @Bindable var recordingViewModel: RecordingViewModel
    @Bindable var meetingAutoRecorder: MeetingAutoRecorder

    private var presentation: RecordingPresentation {
        recordingViewModel.presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RecordingHeroView(
                presentation: presentation,
                canStartRecording: recordingViewModel.canStartRecording,
                startRecording: recordingViewModel.startRecording,
                stopRecording: recordingViewModel.stopRecording,
                openSystemSettings: recordingViewModel.openSystemSettings
            )

            HStack(alignment: .top, spacing: 16) {
                PermissionsPanel(
                    permissionRows: presentation.permissionRows,
                    recordingStateTitleKey: presentation.titleKey,
                    recordingStateTone: statusTone,
                    checkPermissions: recordingViewModel.checkPermissions,
                    openSystemSettings: recordingViewModel.openSystemSettings
                )

                OutputPanel(
                    outputDirectory: recordingViewModel.outputDirectory,
                    validationText: validationText,
                    validationTone: validationTone,
                    canRevealOutputDirectory: recordingViewModel.canRevealOutputDirectory,
                    revealOutputDirectory: recordingViewModel.revealOutputDirectory
                )
            }

            StatusRow(
                title: "meetingAuto.label",
                value: meetingAutoRecorder.status.localizedMessage,
                status: meetingAutoTone
            )

            if meetingAutoRecorder.shouldSuggestStop {
                Button {
                    Task { await meetingAutoRecorder.confirmStop(recordingViewModel: recordingViewModel) }
                } label: {
                    Label("meetingAuto.action.stopRecording", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            TranscriptionPanel(
                outputDirectory: recordingViewModel.outputDirectory,
                transcription: recordingViewModel.transcription,
                selectedTranscriptionMode: $recordingViewModel.selectedTranscriptionMode,
                selectedTranscriptionModel: $recordingViewModel.selectedTranscriptionModel,
                canTranscribe: recordingViewModel.canTranscribe,
                transcribeLatestRecording: recordingViewModel.transcribeLatestRecording
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

    private var meetingAutoTone: StatusTone {
        switch meetingAutoRecorder.status {
        case .recordingStarted:
            .success
        case .meetingMayHaveEnded, .blockedByRecordingPermissions, .windowMetadataUnavailable:
            .warning
        case .monitoring:
            .neutral
        }
    }
}
