import XCTest
@testable import BabyRecorder

final class RecordingPresentationTests: XCTestCase {
    func testReadyPresentationUsesStartAction() {
        let presentation = RecordingPresentation(
            state: .ready,
            permissions: PermissionStatus(screenRecordingGranted: true, microphoneGranted: true),
            validation: nil,
            outputDirectory: nil
        )

        XCTAssertEqual(presentation.kind, .ready)
        XCTAssertEqual(presentation.titleKey, "recording.state.ready.title")
        XCTAssertEqual(presentation.subtitleKey, "recording.state.ready.subtitle")
        XCTAssertEqual(presentation.primaryAction, .start)
        XCTAssertFalse(presentation.showsFailureMessage)
    }

    func testRecordingPresentationUsesStopAction() {
        let presentation = RecordingPresentation(
            state: .recording,
            permissions: PermissionStatus(screenRecordingGranted: true, microphoneGranted: true),
            validation: nil,
            outputDirectory: nil
        )

        XCTAssertEqual(presentation.kind, .recording)
        XCTAssertEqual(presentation.titleKey, "recording.state.recording.title")
        XCTAssertEqual(presentation.primaryAction, .stop)
    }

    func testMissingPermissionPresentationNamesMissingPermissions() {
        let presentation = RecordingPresentation(
            state: .permissionsMissing,
            permissions: PermissionStatus(screenRecordingGranted: false, microphoneGranted: true),
            validation: nil,
            outputDirectory: nil
        )

        XCTAssertEqual(presentation.kind, .permissionsMissing)
        XCTAssertEqual(presentation.titleKey, "recording.state.permissionsMissing.title")
        XCTAssertEqual(presentation.primaryAction, .openSettings)
        XCTAssertEqual(presentation.permissionRows[0].status, .missing)
        XCTAssertEqual(presentation.permissionRows[1].status, .ready)
    }

    func testFinishedWithMixFailurePresentationShowsWarning() {
        let validation = ValidationResult(
            passed: false,
            checks: ValidationChecks(
                systemFileNonEmpty: true,
                micFileNonEmpty: true,
                mixedFileNonEmpty: false,
                systemBuffersPresent: true,
                micBuffersPresent: true
            )
        )

        let presentation = RecordingPresentation(
            state: .finishedWithMixFailure,
            permissions: PermissionStatus(screenRecordingGranted: true, microphoneGranted: true),
            validation: validation,
            outputDirectory: URL(fileURLWithPath: "/tmp/recording", isDirectory: true)
        )

        XCTAssertEqual(presentation.kind, .finishedWithMixFailure)
        XCTAssertEqual(presentation.titleKey, "recording.state.mixFailure.title")
        XCTAssertEqual(presentation.primaryAction, .start)
        XCTAssertEqual(presentation.validationStatus, .failed)
        XCTAssertTrue(presentation.canRevealOutput)
    }

    func testFailedPresentationKeepsFailureMessage() {
        let presentation = RecordingPresentation(
            state: .failed("Stream failed"),
            permissions: PermissionStatus(screenRecordingGranted: true, microphoneGranted: true),
            validation: nil,
            outputDirectory: nil
        )

        XCTAssertEqual(presentation.kind, .failed)
        XCTAssertEqual(presentation.titleKey, "recording.state.failed.title")
        XCTAssertEqual(presentation.failureMessage, "Stream failed")
        XCTAssertTrue(presentation.showsFailureMessage)
    }
}
