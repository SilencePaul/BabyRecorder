import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel

    private var presentation: RecordingPresentation {
        viewModel.presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero

            HStack(alignment: .top, spacing: 16) {
                statusPanel
                outputPanel
            }

            if presentation.showsFailureMessage, let message = presentation.failureMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(Text("app.title"))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
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

            primaryActionButton
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch presentation.primaryAction {
        case .start:
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("recording.action.start", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartRecording)
            .accessibilityLabel(Text("recording.action.start"))
        case .stop:
            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("recording.action.stop", systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .accessibilityLabel(Text("recording.action.stop"))
        case .openSettings:
            Button {
                viewModel.openSystemSettings()
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

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.permissions")
                .font(.headline)

            ForEach(presentation.permissionRows, id: \.labelKey) { row in
                labeledRow(
                    title: LocalizedStringKey(row.labelKey),
                    value: LocalizedStringKey(row.statusKey),
                    status: row.status == .ready ? .success : .warning
                )
            }

            labeledRow(
                title: "label.recordingState",
                value: LocalizedStringKey(presentation.titleKey),
                status: statusTone
            )

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.checkPermissions() }
                } label: {
                    Label("recording.action.recheck", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.openSystemSettings()
                } label: {
                    Label("menu.openSystemSettings", systemImage: "gear")
                }
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.output")
                .font(.headline)

            labeledRow(
                title: "label.outputDirectory",
                value: viewModel.outputDirectory?.lastPathComponent ?? String(localized: "label.noOutput"),
                status: viewModel.outputDirectory == nil ? .neutral : .success
            )

            labeledRow(
                title: "label.validation",
                value: validationText,
                status: validationTone
            )

            labeledRow(
                title: "label.diagnostics",
                value: LocalizedStringKey("diagnostics.sessionJSON"),
                status: viewModel.outputDirectory == nil ? .neutral : .success
            )

            Button {
                viewModel.revealOutputDirectory()
            } label: {
                Label("recording.action.showInFinder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRevealOutputDirectory)
        }
        .panelStyle()
    }

    private enum StatusTone {
        case neutral
        case success
        case warning
        case failure
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

    private func labeledRow(
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        status: StatusTone
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Label {
                Text(value)
            } icon: {
                Image(systemName: symbolName(for: status))
                    .foregroundStyle(color(for: status))
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    private func labeledRow(
        title: LocalizedStringKey,
        value: String,
        status: StatusTone
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Label {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: symbolName(for: status))
                    .foregroundStyle(color(for: status))
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    private func symbolName(for tone: StatusTone) -> String {
        switch tone {
        case .neutral:
            "circle"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.circle.fill"
        }
    }

    private func color(for tone: StatusTone) -> Color {
        switch tone {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
