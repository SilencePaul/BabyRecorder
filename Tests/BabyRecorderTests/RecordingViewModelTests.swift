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

    func testReadyStartRecordingCallsCaptureOnceAndEntersRecording() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()

        await viewModel.startRecording()

        let state = await viewModel.state
        XCTAssertEqual(state, .recording)
        XCTAssertEqual(captureService.startCallCount, 1)
    }

    func testMissingPermissionsDoesNotCallStart() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: false, mic: true), captureService: captureService)
        await viewModel.checkPermissions()

        await viewModel.startRecording()

        let state = await viewModel.state
        XCTAssertEqual(state, .permissionsMissing)
        XCTAssertEqual(captureService.startCallCount, 0)
    }

    func testStartFromRecordingDoesNotCallCaptureAgainAndPreservesState() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()

        await viewModel.startRecording()

        let state = await viewModel.state
        XCTAssertEqual(state, .recording)
        XCTAssertEqual(captureService.startCallCount, 1)
    }

    func testStopFromNonRecordingDoesNotCallCaptureAndPreservesState() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()

        await viewModel.stopRecording()

        let state = await viewModel.state
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(captureService.stopCallCount, 0)
    }

    func testRecordingStopStoresCompletionAndEntersFinished() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/finished", isDirectory: true)
        let validation = Self.validation(passed: true)
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(outputDirectory: outputDirectory, validation: validation, mixFailed: false)
        )
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()

        await viewModel.stopRecording()

        let state = await viewModel.state
        let storedOutputDirectory = await viewModel.outputDirectory
        let storedValidation = await viewModel.validation
        XCTAssertEqual(state, .finished)
        XCTAssertEqual(storedOutputDirectory, outputDirectory)
        XCTAssertEqual(storedValidation, validation)
        XCTAssertEqual(captureService.stopCallCount, 1)
    }

    func testRecordingStopWithMixFailureEntersFinishedWithMixFailure() async {
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: FileManager.default.temporaryDirectory,
                validation: Self.validation(passed: false),
                mixFailed: true
            )
        )
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()

        await viewModel.stopRecording()

        let state = await viewModel.state
        XCTAssertEqual(state, .finishedWithMixFailure)
        XCTAssertEqual(captureService.stopCallCount, 1)
    }

    fileprivate static func validation(passed: Bool) -> ValidationResult {
        ValidationResult(
            passed: passed,
            checks: ValidationChecks(
                systemFileNonEmpty: passed,
                micFileNonEmpty: passed,
                mixedFileNonEmpty: passed,
                systemBuffersPresent: passed,
                micBuffersPresent: passed
            )
        )
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

private final class FakeCaptureService: CaptureServicing, @unchecked Sendable {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var stopResult: RecordingCompletion

    init(
        stopResult: RecordingCompletion = RecordingCompletion(
            outputDirectory: FileManager.default.temporaryDirectory,
            validation: RecordingViewModelTests.validation(passed: true),
            mixFailed: false
        )
    ) {
        self.stopResult = stopResult
    }

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        startCallCount += 1
    }

    func stop() async throws -> RecordingCompletion {
        stopCallCount += 1
        return stopResult
    }
}
