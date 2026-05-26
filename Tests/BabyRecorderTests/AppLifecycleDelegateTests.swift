import AppKit
import XCTest
@testable import BabyRecorder

@MainActor
final class AppLifecycleDelegateTests: XCTestCase {
    func testClosingLastWindowDoesNotTerminateApp() {
        let delegate = AppLifecycleDelegate()

        let reply = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)

        XCTAssertFalse(reply)
    }

    func testQuitWhenNotRecordingTerminatesImmediately() {
        let delegate = AppLifecycleDelegate()
        let viewModel = RecordingViewModel(
            permissionService: FakeLifecyclePermissionService(screen: true, mic: true),
            captureService: FakeLifecycleCaptureService()
        )
        delegate.viewModel = viewModel

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateNow)
    }

    func testQuitWhileRecordingCancelsWhenConfirmationDeclines() async {
        let delegate = AppLifecycleDelegate()
        let viewModel = RecordingViewModel(
            permissionService: FakeLifecyclePermissionService(screen: true, mic: true),
            captureService: FakeLifecycleCaptureService()
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        delegate.viewModel = viewModel
        delegate.confirmQuitWhileRecording = { false }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateCancel)
    }

    func testQuitWhileRecordingStopsBeforeCompletingAcceptedTermination() async {
        let delegate = AppLifecycleDelegate()
        let captureService = FakeLifecycleCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeLifecyclePermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        delegate.viewModel = viewModel
        delegate.confirmQuitWhileRecording = { true }
        let terminationCompleted = expectation(description: "termination reply completes")
        delegate.completeTerminationAfterRecordingStop = { shouldTerminate in
            XCTAssertTrue(shouldTerminate)
            XCTAssertEqual(captureService.stopCallCount, 1)
            terminationCompleted.fulfill()
        }

        let reply = delegate.applicationShouldTerminate(NSApplication.shared)

        XCTAssertEqual(reply, .terminateLater)
        await fulfillment(of: [terminationCompleted], timeout: 1)
        XCTAssertEqual(captureService.stopCallCount, 1)
        XCTAssertEqual(viewModel.state, .finished)
    }
}

private final class FakeLifecyclePermissionService: PermissionServicing, @unchecked Sendable {
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

private final class FakeLifecycleCaptureService: CaptureServicing, @unchecked Sendable {
    private(set) var stopCallCount = 0

    func start(permissionSnapshot: PermissionSnapshot) async throws {}

    func stop() async throws -> RecordingCompletion {
        stopCallCount += 1
        return RecordingCompletion(
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
