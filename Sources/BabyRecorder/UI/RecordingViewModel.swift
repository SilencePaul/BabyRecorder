import Combine
import Foundation

enum RecordingState: Equatable, Sendable {
    case checkingPermissions
    case permissionsMissing
    case ready
    case starting
    case recording
    case stopping
    case finished
    case finishedWithMixFailure
    case failed(String)
}

protocol CaptureServicing: Sendable {
    func start(permissionSnapshot: PermissionSnapshot) async throws
    func stop() async throws -> RecordingCompletion
}

struct RecordingCompletion: Equatable, Sendable {
    var outputDirectory: URL
    var validation: ValidationResult
    var mixFailed: Bool
}

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .checkingPermissions
    @Published private(set) var permissionStatus = PermissionStatus(screenRecordingGranted: false, microphoneGranted: false)
    @Published private(set) var outputDirectory: URL?
    @Published private(set) var validation: ValidationResult?

    private let permissionService: PermissionServicing
    private let captureService: CaptureServicing

    init(permissionService: PermissionServicing = PermissionService(), captureService: CaptureServicing) {
        self.permissionService = permissionService
        self.captureService = captureService
    }

    var canStartRecording: Bool {
        state == .ready && permissionStatus.isReady
    }

    func checkPermissions() async {
        state = .checkingPermissions
        permissionStatus = await permissionService.checkPermissions()
        state = permissionStatus.isReady ? .ready : .permissionsMissing
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func startRecording() async {
        guard canStartRecording else {
            state = .permissionsMissing
            return
        }

        do {
            state = .starting
            try await captureService.start(permissionSnapshot: permissionStatus.snapshot)
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        do {
            state = .stopping
            let completion = try await captureService.stop()
            outputDirectory = completion.outputDirectory
            validation = completion.validation
            state = completion.mixFailed ? .finishedWithMixFailure : .finished
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
