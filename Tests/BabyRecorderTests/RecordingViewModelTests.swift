import XCTest
@testable import BabyRecorder

final class RecordingViewModelTests: XCTestCase {
    func testStartDisabledWhenPermissionsMissing() async {
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: false, mic: true), captureService: FakeCaptureService())
        await viewModel.checkPermissions()

        let canStart = await viewModel.canStartRecording
        let state = await viewModel.state
        XCTAssertFalse(canStart)
        XCTAssertEqual(state, .permissionsMissing)
    }

    func testStartEnabledWhenPermissionsReady() async {
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: FakeCaptureService())
        await viewModel.checkPermissions()

        let canStart = await viewModel.canStartRecording
        let state = await viewModel.state
        XCTAssertTrue(canStart)
        XCTAssertEqual(state, .ready)
    }
}

private struct FakePermissionService: PermissionServicing {
    var screen: Bool
    var mic: Bool

    func checkPermissions() async -> PermissionStatus {
        PermissionStatus(screenRecordingGranted: screen, microphoneGranted: mic)
    }

    func openSystemSettings() {}
}

private final class FakeCaptureService: CaptureServicing {
    func start(permissionSnapshot: PermissionSnapshot) async throws {}

    func stop() async throws -> RecordingCompletion {
        RecordingCompletion(
            outputDirectory: FileManager.default.temporaryDirectory,
            validation: ValidationResult(
                passed: true,
                checks: ValidationChecks(
                    systemFileNonEmpty: true,
                    micFileNonEmpty: true,
                    mixedFileNonEmpty: true,
                    systemBuffersPresent: true,
                    micBuffersPresent: true
                )
            ),
            mixFailed: false
        )
    }
}
