import AVFoundation
import XCTest
@testable import BabyRecorder

final class PermissionServiceTests: XCTestCase {
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
