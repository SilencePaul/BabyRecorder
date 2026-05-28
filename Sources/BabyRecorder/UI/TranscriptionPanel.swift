import SwiftUI

struct TranscriptionPanel: View {
    let outputDirectory: URL?
    let transcription: TranscriptionSnapshot
    @Binding var selectedTranscriptionMode: TranscriptionMode
    @Binding var selectedTranscriptionModel: TranscriptionModel
    let canTranscribe: Bool
    let transcribeLatestRecording: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("section.transcription")
                    .font(.headline)
                Spacer()

                Picker("label.transcriptionMode", selection: $selectedTranscriptionMode) {
                    Text("transcription.mode.mixed")
                        .tag(TranscriptionMode.mixed)
                    Text("transcription.mode.dialogue")
                        .tag(TranscriptionMode.dialogue)
                }
                .labelsHidden()
                .frame(width: 150)
                .disabled(transcription.status == .running)

                Picker("label.transcriptionModel", selection: $selectedTranscriptionModel) {
                    Text("transcription.model.fast")
                        .tag(TranscriptionModel.fast)
                    Text("transcription.model.accurate")
                        .tag(TranscriptionModel.accurate)
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(transcription.status == .running)

                Button {
                    Task { await transcribeLatestRecording() }
                } label: {
                    Label(transcriptionActionKey, systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(!canTranscribe)
            }

            StatusRow(
                title: "label.transcriptionState",
                value: transcriptionStatusKey,
                status: transcriptionTone
            )

            Text(transcriptionMessageKey)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if transcription.status == .failed,
               let errorMessage = transcription.errorMessage,
               errorMessage.isEmpty == false {
                TranscriptionDetailText(text: errorMessage, lineLimit: 8)
                    .foregroundStyle(.red)
            }

            if transcription.text.isEmpty == false {
                TranscriptionDetailText(text: transcription.text, lineLimit: 5)
                    .font(.body)
            }
        }
        .panelStyle()
    }

    private var transcriptionActionKey: LocalizedStringKey {
        transcription.status == .failed ? "transcription.action.retry" : "transcription.action.start"
    }

    private var transcriptionStatusKey: LocalizedStringKey {
        switch transcription.status {
        case .idle:
            "transcription.status.idle"
        case .running:
            "transcription.status.running"
        case .completed:
            "transcription.status.completed"
        case .failed:
            "transcription.status.failed"
        }
    }

    private var transcriptionMessageKey: LocalizedStringKey {
        switch transcription.status {
        case .idle:
            outputDirectory == nil ? "transcription.message.waitingForRecording" : "transcription.message.ready"
        case .running:
            "transcription.message.running"
        case .completed:
            "transcription.message.completed"
        case .failed:
            "transcription.message.failed"
        }
    }

    private var transcriptionTone: StatusTone {
        switch transcription.status {
        case .idle:
            .neutral
        case .running:
            .warning
        case .completed:
            .success
        case .failed:
            .failure
        }
    }
}
