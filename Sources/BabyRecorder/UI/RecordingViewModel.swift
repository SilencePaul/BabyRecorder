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
        isStartableState && permissionStatus.isReady
    }

    func checkPermissions() async {
        let preservesActiveState = state == .starting || state == .recording || state == .stopping
        if !preservesActiveState {
            state = .checkingPermissions
        }

        let status = await permissionService.checkPermissions()
        permissionStatus = status
        guard !preservesActiveState else {
            return
        }

        state = status.isReady ? .ready : .permissionsMissing
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func startRecording() async {
        guard state != .starting && state != .recording && state != .stopping else {
            return
        }

        guard isStartableState else {
            if !permissionStatus.isReady {
                state = .permissionsMissing
            }
            return
        }

        guard permissionStatus.isReady else {
            state = .permissionsMissing
            return
        }

        do {
            state = .starting
            outputDirectory = nil
            validation = nil
            try await captureService.start(permissionSnapshot: permissionStatus.snapshot)
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard state == .recording else {
            return
        }

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

    private var isStartableState: Bool {
        state == .ready || state == .finished || state == .finishedWithMixFailure
    }
}
