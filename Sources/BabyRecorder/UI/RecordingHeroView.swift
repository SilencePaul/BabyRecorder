import SwiftUI

struct RecordingHeroView: View {
    let presentation: RecordingPresentation
    let canStartRecording: Bool
    let startRecording: () async -> Void
    let stopRecording: () async -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(presentation.titleKey))
                    .font(.title)
                    .fontWeight(.semibold)
                Text(LocalizedStringKey(presentation.subtitleKey))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            PrimaryActionButton(
                action: presentation.primaryAction,
                canStartRecording: canStartRecording,
                startRecording: startRecording,
                stopRecording: stopRecording,
                openSystemSettings: openSystemSettings
            )
        }
    }
}
