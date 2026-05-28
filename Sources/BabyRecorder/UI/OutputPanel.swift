import SwiftUI

struct OutputPanel: View {
    let outputDirectory: URL?
    let validationText: LocalizedStringKey
    let validationTone: StatusTone
    let canRevealOutputDirectory: Bool
    let revealOutputDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.output")
                .font(.headline)

            StatusRow(
                title: "label.outputDirectory",
                value: outputDirectory?.lastPathComponent ?? String(localized: "label.noOutput"),
                status: outputDirectory == nil ? .neutral : .success
            )

            StatusRow(
                title: "label.validation",
                value: validationText,
                status: validationTone
            )

            StatusRow(
                title: "label.diagnostics",
                value: LocalizedStringKey("diagnostics.sessionJSON"),
                status: outputDirectory == nil ? .neutral : .success
            )

            Button {
                revealOutputDirectory()
            } label: {
                Label("recording.action.showInFinder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(!canRevealOutputDirectory)
        }
        .panelStyle()
    }
}
