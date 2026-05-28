import SwiftUI

struct PrimaryActionButton: View {
    let action: RecordingPresentation.PrimaryAction
    let canStartRecording: Bool
    let startRecording: () async -> Void
    let stopRecording: () async -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        switch action {
        case .start:
            Button {
                Task { await startRecording() }
            } label: {
                Label("recording.action.start", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStartRecording)
            .accessibilityLabel(Text("recording.action.start"))
        case .stop:
            Button {
                Task { await stopRecording() }
            } label: {
                Label("recording.action.stop", systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .accessibilityLabel(Text("recording.action.stop"))
        case .openSettings:
            Button {
                openSystemSettings()
            } label: {
                Label("recording.action.openSettings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(Text("recording.action.openSettings"))
        case .none:
            ProgressView()
                .controlSize(.large)
        }
    }
}
