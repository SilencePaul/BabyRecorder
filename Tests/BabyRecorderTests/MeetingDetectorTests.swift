import XCTest
@testable import BabyRecorder

final class MeetingDetectorTests: XCTestCase {
    func testSystemProviderCanBeConstructed() {
        let provider = SystemMeetingApplicationProvider()
        XCTAssertNotNil(provider)
    }

    func testSystemProviderCanReadMetadataWhenCGTitlesArePresent() {
        let metadata = SystemMeetingApplicationProvider.mergedWindowMetadata(
            visibleTitles: ["会议中 - 项目同步会议"],
            accessibilityRead: .init(titles: [], readSucceeded: false)
        )

        XCTAssertEqual(metadata.titles, ["会议中 - 项目同步会议"])
        XCTAssertTrue(metadata.canReadWindowMetadata)
    }

    func testSystemProviderCanReadEmptyMetadataWhenAXReadSucceeds() {
        let metadata = SystemMeetingApplicationProvider.mergedWindowMetadata(
            visibleTitles: [],
            accessibilityRead: .init(titles: [], readSucceeded: true)
        )

        XCTAssertEqual(metadata.titles, [])
        XCTAssertTrue(metadata.canReadWindowMetadata)
    }

    func testSystemProviderCannotReadMetadataWhenNoTitlesAndAXReadFails() {
        let metadata = SystemMeetingApplicationProvider.mergedWindowMetadata(
            visibleTitles: [],
            accessibilityRead: .init(titles: [], readSucceeded: false)
        )

        XCTAssertEqual(metadata.titles, [])
        XCTAssertFalse(metadata.canReadWindowMetadata)
    }

    func testSystemProviderTreatsNoAXWindowsAsReadableEmptyMetadata() {
        let read = SystemMeetingApplicationProvider.accessibilityWindowTitleRead(from: [])

        XCTAssertEqual(read.titles, [])
        XCTAssertTrue(read.readSucceeded)
    }

    func testSystemProviderTreatsAllFailedAXTitleReadsAsUnavailable() {
        let read = SystemMeetingApplicationProvider.accessibilityWindowTitleRead(from: [nil, nil])
        let metadata = SystemMeetingApplicationProvider.mergedWindowMetadata(
            visibleTitles: [],
            accessibilityRead: read
        )

        XCTAssertEqual(read.titles, [])
        XCTAssertFalse(read.readSucceeded)
        XCTAssertFalse(metadata.canReadWindowMetadata)
    }

    func testSystemProviderPreservesStableMergedTitleOrder() {
        let metadata = SystemMeetingApplicationProvider.mergedWindowMetadata(
            visibleTitles: ["A", "B"],
            accessibilityRead: .init(titles: ["B", "C", "A", "D"], readSucceeded: true)
        )

        XCTAssertEqual(metadata.titles, ["A", "B", "C", "D"])
    }

    func testSupportedAppWithoutMeetingWindowDoesNotDetectMeeting() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["主界面"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .notInMeeting)
        XCTAssertNil(snapshot.app)
    }

    func testSupportedAppWithMeetingWindowDetectsMeeting() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["会议中 - 项目同步会议"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .inMeeting)
        XCTAssertEqual(snapshot.app, .tencentMeeting)
        XCTAssertEqual(snapshot.displayName, "腾讯会议")
    }

    func testTencentMeetingAppNameOnlyWindowDoesNotDetectMeeting() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["腾讯会议"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .notInMeeting)
        XCTAssertNil(snapshot.app)
    }

    func testNegatedMeetingStatusTitlesDoNotDetectMeeting() {
        let detector = MeetingDetector()

        for title in ["当前未在会议中", "不在会议中"] {
            let snapshot = detector.detect(from: [
                RunningApplicationSnapshot(
                    bundleIdentifier: "com.tencent.meeting",
                    localizedName: "腾讯会议",
                    windowTitles: [title],
                    canReadWindowMetadata: true
                )
            ])

            XCTAssertEqual(snapshot.status, .notInMeeting, "Title should not detect meeting: \(title)")
            XCTAssertNil(snapshot.app, "Title should not detect meeting: \(title)")
        }
    }

    func testScreenSharingSettingsTitleDoesNotDetectMeeting() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.electron.lark",
                localizedName: "飞书",
                windowTitles: ["共享屏幕设置"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .notInMeeting)
        XCTAssertNil(snapshot.app)
    }

    func testUnsupportedAppWithMeetingTitleDoesNotDetectMeeting() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.apple.Notes",
                localizedName: "Notes",
                windowTitles: ["会议纪要"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .notInMeeting)
        XCTAssertNil(snapshot.app)
    }

    func testSupportedAppWithoutReadableWindowMetadataReportsPermissionNeeded() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.electron.lark",
                localizedName: "飞书",
                windowTitles: [],
                canReadWindowMetadata: false
            )
        ])

        XCTAssertEqual(snapshot.status, .windowMetadataUnavailable)
        XCTAssertEqual(snapshot.app, .feishu)
    }

    func testActiveMeetingTakesPrecedenceOverUnreadableSupportedAppMetadata() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.electron.lark",
                localizedName: "飞书",
                windowTitles: [],
                canReadWindowMetadata: false
            ),
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["会议中 - 项目同步会议"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .inMeeting)
        XCTAssertEqual(snapshot.app, .tencentMeeting)
        XCTAssertEqual(snapshot.displayName, "腾讯会议")
    }

    func testDingTalkBundleIdIsSupported() {
        let detector = MeetingDetector()
        let snapshot = detector.detect(from: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.alibaba.dingtalkmac",
                localizedName: "钉钉",
                windowTitles: ["DingTalk Meeting - 周会"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .inMeeting)
        XCTAssertEqual(snapshot.app, .dingTalk)
    }
}
