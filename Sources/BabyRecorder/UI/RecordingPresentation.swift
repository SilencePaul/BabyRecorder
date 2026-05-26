import Foundation

struct RecordingPresentation: Equatable {
    enum Kind: Equatable {
        case checkingPermissions
        case permissionsMissing
        case ready
        case starting
        case recording
        case stopping
        case finished
        case finishedWithMixFailure
        case failed
    }

    enum PrimaryAction: Equatable {
        case start
        case stop
        case openSettings
        case none
    }

    enum PermissionStatusKind: Equatable {
        case ready
        case missing
    }

    enum ValidationStatus: Equatable {
        case notAvailable
        case passed
        case failed
    }

    struct PermissionRow: Equatable {
        var labelKey: String
        var status: PermissionStatusKind

        var statusKey: String {
            switch status {
            case .ready:
                "permission.status.ready"
            case .missing:
                "permission.status.missing"
            }
        }
    }

    let kind: Kind
    let titleKey: String
    let subtitleKey: String
    let primaryAction: PrimaryAction
    let permissionRows: [PermissionRow]
    let validationStatus: ValidationStatus
    let outputDirectory: URL?
    let failureMessage: String?

    init(
        state: RecordingState,
        permissions: PermissionStatus,
        validation: ValidationResult?,
        outputDirectory: URL?
    ) {
        self.kind = Self.kind(for: state)
        self.titleKey = Self.titleKey(for: state)
        self.subtitleKey = Self.subtitleKey(for: state)
        self.primaryAction = Self.primaryAction(for: state)
        self.permissionRows = [
            PermissionRow(
                labelKey: "permission.screenRecording",
                status: permissions.screenRecordingGranted ? .ready : .missing
            ),
            PermissionRow(
                labelKey: "permission.microphone",
                status: permissions.microphoneGranted ? .ready : .missing
            )
        ]
        self.validationStatus = Self.validationStatus(for: validation)
        self.outputDirectory = outputDirectory
        if case .failed(let message) = state {
            self.failureMessage = message
        } else {
            self.failureMessage = nil
        }
    }

    var canRevealOutput: Bool {
        outputDirectory != nil
    }

    var showsFailureMessage: Bool {
        failureMessage?.isEmpty == false
    }

    private static func kind(for state: RecordingState) -> Kind {
        switch state {
        case .checkingPermissions:
            .checkingPermissions
        case .permissionsMissing:
            .permissionsMissing
        case .ready:
            .ready
        case .starting:
            .starting
        case .recording:
            .recording
        case .stopping:
            .stopping
        case .finished:
            .finished
        case .finishedWithMixFailure:
            .finishedWithMixFailure
        case .failed:
            .failed
        }
    }

    private static func titleKey(for state: RecordingState) -> String {
        switch state {
        case .checkingPermissions:
            "recording.state.checkingPermissions.title"
        case .permissionsMissing:
            "recording.state.permissionsMissing.title"
        case .ready:
            "recording.state.ready.title"
        case .starting:
            "recording.state.starting.title"
        case .recording:
            "recording.state.recording.title"
        case .stopping:
            "recording.state.stopping.title"
        case .finished:
            "recording.state.finished.title"
        case .finishedWithMixFailure:
            "recording.state.mixFailure.title"
        case .failed:
            "recording.state.failed.title"
        }
    }

    private static func subtitleKey(for state: RecordingState) -> String {
        switch state {
        case .checkingPermissions:
            "recording.state.checkingPermissions.subtitle"
        case .permissionsMissing:
            "recording.state.permissionsMissing.subtitle"
        case .ready:
            "recording.state.ready.subtitle"
        case .starting:
            "recording.state.starting.subtitle"
        case .recording:
            "recording.state.recording.subtitle"
        case .stopping:
            "recording.state.stopping.subtitle"
        case .finished:
            "recording.state.finished.subtitle"
        case .finishedWithMixFailure:
            "recording.state.mixFailure.subtitle"
        case .failed:
            "recording.state.failed.subtitle"
        }
    }

    private static func primaryAction(for state: RecordingState) -> PrimaryAction {
        switch state {
        case .ready, .finished, .finishedWithMixFailure:
            .start
        case .recording:
            .stop
        case .permissionsMissing:
            .openSettings
        case .checkingPermissions, .starting, .stopping, .failed:
            .none
        }
    }

    private static func validationStatus(for validation: ValidationResult?) -> ValidationStatus {
        guard let validation else {
            return .notAvailable
        }
        return validation.passed ? .passed : .failed
    }
}
