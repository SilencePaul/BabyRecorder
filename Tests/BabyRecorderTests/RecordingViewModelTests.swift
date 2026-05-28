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

    func testCheckPermissionsWhileRecordingPreservesRecordingStateAndDoesNotAllowSecondStart() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()

        await viewModel.checkPermissions()

        let stateAfterCheck = await viewModel.state
        XCTAssertEqual(stateAfterCheck, .recording)

        await viewModel.startRecording()

        let stateAfterSecondStart = await viewModel.state
        XCTAssertEqual(stateAfterSecondStart, .recording)
        XCTAssertEqual(captureService.startCallCount, 1)
    }

    func testStartWhileRecordingWithMissingPermissionsPreservesRecordingState() async {
        let permissionService = FakePermissionService(screen: true, mic: true)
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: permissionService, captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()

        permissionService.screen = false
        await viewModel.checkPermissions()

        let stateAfterCheck = await viewModel.state
        XCTAssertEqual(stateAfterCheck, .recording)

        await viewModel.startRecording()

        let stateAfterSecondStart = await viewModel.state
        XCTAssertEqual(stateAfterSecondStart, .recording)
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

    func testFinishedRecordingCanStartAgainWithoutRestartingApp() async {
        let captureService = FakeCaptureService()
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: captureService)
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()

        let canStartAfterFinished = await viewModel.canStartRecording
        await viewModel.startRecording()

        let state = await viewModel.state
        XCTAssertTrue(canStartAfterFinished)
        XCTAssertEqual(state, .recording)
        XCTAssertEqual(captureService.startCallCount, 2)
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

    func testFinishedWithMixFailureCanStartAgainWithoutRestartingApp() async {
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

        let canStartAfterFinished = await viewModel.canStartRecording
        await viewModel.startRecording()

        let state = await viewModel.state
        XCTAssertTrue(canStartAfterFinished)
        XCTAssertEqual(state, .recording)
        XCTAssertEqual(captureService.startCallCount, 2)
    }

    func testRevealOutputDoesNothingWhenNoOutputDirectoryExists() async {
        let filePresenter = FakeFilePresenter()
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: FakeCaptureService(),
            filePresenter: filePresenter
        )

        await viewModel.revealOutputDirectory()

        XCTAssertEqual(filePresenter.revealedURLs, [])
    }

    func testRevealOutputPresentsStoredOutputDirectory() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/reveal", isDirectory: true)
        let filePresenter = FakeFilePresenter()
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: outputDirectory,
                validation: Self.validation(passed: true),
                mixFailed: false
            )
        )
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: captureService,
            filePresenter: filePresenter
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()

        await viewModel.revealOutputDirectory()

        XCTAssertEqual(filePresenter.revealedURLs, [outputDirectory])
    }

    func testFinishedRecordingCanBeTranscribed() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/transcribe", isDirectory: true)
        let transcriptionService = FakeTranscriptionService(
            result: TranscriptionResult(
                text: "开始录音测试。",
                transcriptURL: outputDirectory.appendingPathComponent("transcript.txt"),
                metadataURL: outputDirectory.appendingPathComponent("transcript.json")
            )
        )
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: outputDirectory,
                validation: Self.validation(passed: true),
                mixFailed: false
            )
        )
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: captureService,
            transcriptionService: transcriptionService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()

        await viewModel.transcribeLatestRecording()

        let transcription = await viewModel.transcription
        XCTAssertEqual(transcriptionService.requests, [
            TranscriptionRequest(sessionDirectory: outputDirectory, model: .fast)
        ])
        XCTAssertEqual(transcription.status, .completed)
        XCTAssertEqual(transcription.text, "开始录音测试。")
        XCTAssertEqual(transcription.transcriptURL, outputDirectory.appendingPathComponent("transcript.txt"))
    }

    func testDialogueTranscriptionModeIsPassedToService() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/dialogue", isDirectory: true)
        let transcriptionService = FakeTranscriptionService(
            result: TranscriptionResult(
                text: "[00:00:01] 我：你好",
                transcriptURL: outputDirectory.appendingPathComponent("transcript_dialogue.txt"),
                metadataURL: outputDirectory.appendingPathComponent("transcript_dialogue.json")
            )
        )
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: outputDirectory,
                validation: Self.validation(passed: true),
                mixFailed: false
            )
        )
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: captureService,
            transcriptionService: transcriptionService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()
        await MainActor.run {
            viewModel.selectedTranscriptionMode = .dialogue
        }

        await viewModel.transcribeLatestRecording()

        XCTAssertEqual(transcriptionService.requests.map(\.mode), [.dialogue])
    }

    func testTranscriptionFailureStoresRetryableError() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/transcribe-fail", isDirectory: true)
        let transcriptionService = FakeTranscriptionService(error: FakeTranscriptionError.failed)
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: outputDirectory,
                validation: Self.validation(passed: true),
                mixFailed: false
            )
        )
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: captureService,
            transcriptionService: transcriptionService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()

        await viewModel.transcribeLatestRecording()

        let transcription = await viewModel.transcription
        let canTranscribe = await viewModel.canTranscribe
        XCTAssertEqual(transcription.status, .failed)
        XCTAssertEqual(transcription.errorMessage, "转写失败")
        XCTAssertTrue(canTranscribe)
    }

    func testTranscriptionCannotStartWithoutOutputDirectory() async {
        let transcriptionService = FakeTranscriptionService()
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: FakeCaptureService(),
            transcriptionService: transcriptionService
        )
        await viewModel.checkPermissions()

        await viewModel.transcribeLatestRecording()

        let transcription = await viewModel.transcription
        XCTAssertEqual(transcriptionService.requests, [])
        XCTAssertEqual(transcription.status, .idle)
    }

    func testTranscriptionDoesNotStartTwiceWhileRunning() async {
        let outputDirectory = URL(fileURLWithPath: "/tmp/baby-recorder-tests/transcribe-running", isDirectory: true)
        let transcriptionService = FakeTranscriptionService(delayNanoseconds: 50_000_000)
        let captureService = FakeCaptureService(
            stopResult: RecordingCompletion(
                outputDirectory: outputDirectory,
                validation: Self.validation(passed: true),
                mixFailed: false
            )
        )
        let viewModel = await RecordingViewModel(
            permissionService: FakePermissionService(screen: true, mic: true),
            captureService: captureService,
            transcriptionService: transcriptionService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        await viewModel.stopRecording()

        async let first: Void = viewModel.transcribeLatestRecording()
        async let second: Void = viewModel.transcribeLatestRecording()
        _ = await (first, second)

        XCTAssertEqual(transcriptionService.requests.count, 1)
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

private final class FakePermissionService: PermissionServicing, @unchecked Sendable {
    var screen: Bool
    var mic: Bool

    init(screen: Bool, mic: Bool) {
        self.screen = screen
        self.mic = mic
    }

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

private final class FakeFilePresenter: FilePresenting, @unchecked Sendable {
    private(set) var revealedURLs: [URL] = []

    func revealInFinder(_ url: URL) {
        revealedURLs.append(url)
    }
}

private enum FakeTranscriptionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "转写失败"
    }
}

private final class FakeTranscriptionService: TranscriptionServicing, @unchecked Sendable {
    private(set) var requests: [TranscriptionRequest] = []
    var result: TranscriptionResult
    var error: Error?
    var delayNanoseconds: UInt64

    init(
        result: TranscriptionResult = TranscriptionResult(
            text: "默认转写文本",
            transcriptURL: FileManager.default.temporaryDirectory.appendingPathComponent("transcript.txt"),
            metadataURL: FileManager.default.temporaryDirectory.appendingPathComponent("transcript.json")
        ),
        error: Error? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        return result
    }
}
