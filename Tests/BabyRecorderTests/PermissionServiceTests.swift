import AVFoundation
import XCTest
@testable import BabyRecorder

final class PermissionServiceTests: XCTestCase {
    func testUsesScreenRecordingAuthorizerWhenCheckingPermissions() async {
        let screen = FakeScreenRecordingPermissionAuthorizer(granted: true)
        let microphone = FakeMicrophonePermissionAuthorizer(status: .authorized, requestResult: false)
        let service = PermissionService(
            screenRecordingAuthorizer: screen,
            microphoneAuthorizer: microphone,
            openSettings: {}
        )

        let status = await service.checkPermissions()

        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertTrue(status.microphoneGranted)
        XCTAssertEqual(screen.isGrantedCallCount, 1)
    }

    func testRequestsMicrophoneAccessWhenStatusIsNotDetermined() async {
        let microphone = FakeMicrophonePermissionAuthorizer(status: .notDetermined, requestResult: true)
        let service = PermissionService(
            screenRecordingGranted: { true },
            microphoneAuthorizer: microphone,
            openSettings: {}
        )

        let status = await service.checkPermissions()

        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertTrue(status.microphoneGranted)
        XCTAssertEqual(microphone.requestAccessCallCount, 1)
    }

    func testDoesNotRequestMicrophoneAccessWhenStatusIsDenied() async {
        let microphone = FakeMicrophonePermissionAuthorizer(status: .denied, requestResult: true)
        let service = PermissionService(
            screenRecordingGranted: { true },
            microphoneAuthorizer: microphone,
            openSettings: {}
        )

        let status = await service.checkPermissions()

        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertFalse(status.microphoneGranted)
        XCTAssertEqual(microphone.requestAccessCallCount, 0)
    }
}

private final class FakeScreenRecordingPermissionAuthorizer: ScreenRecordingPermissionAuthorizing, @unchecked Sendable {
    private let granted: Bool
    private(set) var isGrantedCallCount = 0

    init(granted: Bool) {
        self.granted = granted
    }

    func isGranted() async -> Bool {
        isGrantedCallCount += 1
        return granted
    }
}

private final class FakeMicrophonePermissionAuthorizer: MicrophonePermissionAuthorizing, @unchecked Sendable {
    private let status: AVAuthorizationStatus
    private let requestResult: Bool
    private(set) var requestAccessCallCount = 0

    init(status: AVAuthorizationStatus, requestResult: Bool) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        return requestResult
    }
}
