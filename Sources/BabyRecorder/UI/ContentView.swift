import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Baby Recorder")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("State: \(stateText)")
                Text("Screen Recording: \(viewModel.permissionStatus.screenRecordingGranted ? "Ready" : "Missing")")
                Text("Microphone: \(viewModel.permissionStatus.microphoneGranted ? "Ready" : "Missing")")
            }

            HStack {
                Button("Re-check Permissions") {
                    Task { await viewModel.checkPermissions() }
                }
                Button("Open System Settings") {
                    viewModel.openSystemSettings()
                }
            }

            HStack {
                Button("Start Recording") {
                    Task { await viewModel.startRecording() }
                }
                .disabled(!viewModel.canStartRecording)

                Button("Stop Recording") {
                    Task { await viewModel.stopRecording() }
                }
                .disabled(viewModel.state != .recording)
            }

            if let outputDirectory = viewModel.outputDirectory {
                Text("Output: \(outputDirectory.path)")
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let validation = viewModel.validation {
                Text(validation.passed ? "Validation passed" : "Validation failed")
                    .foregroundStyle(validation.passed ? .green : .red)
            }

            Spacer()
        }
        .padding(24)
    }

    private var stateText: String {
        switch viewModel.state {
        case .checkingPermissions: "checking permissions"
        case .permissionsMissing: "permissions missing"
        case .ready: "ready"
        case .starting: "starting"
        case .recording: "recording"
        case .stopping: "stopping"
        case .finished: "finished"
        case .finishedWithMixFailure: "finished with mix failure"
        case .failed(let message): "failed: \(message)"
        }
    }
}
