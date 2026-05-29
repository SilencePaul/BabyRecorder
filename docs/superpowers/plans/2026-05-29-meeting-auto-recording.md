# Meeting Auto Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start recording automatically when BabyRecorder detects an active Tencent Meeting, Feishu/Lark, or DingTalk meeting, then ask the user to confirm before stopping after the meeting disappears.

**Architecture:** Add a small `MeetingDetection` area that keeps detection pure and testable, then add a `MeetingAutoRecorder` controller that reuses `RecordingViewModel.startRecording()` and `RecordingViewModel.stopRecording()`. System APIs stay behind `MeetingApplicationProviding` so tests use fake snapshots instead of real installed apps or macOS Accessibility permission state.

**Tech Stack:** Swift 6.2, SwiftUI Observation, AppKit `NSWorkspace`, CoreGraphics window-list APIs, ApplicationServices Accessibility APIs, XCTest.

---

## File Structure

- Create `Sources/BabyRecorder/MeetingDetection/MeetingApp.swift`
  - Defines supported meeting apps, app IDs, display names, bundle ID allowlists, and conservative meeting keywords.
- Create `Sources/BabyRecorder/MeetingDetection/MeetingDetector.swift`
  - Defines `RunningApplicationSnapshot`, `MeetingDetectionSnapshot`, `MeetingDetectionStatus`, `MeetingApplicationProviding`, and pure detection logic.
- Create `Sources/BabyRecorder/MeetingDetection/SystemMeetingApplicationProvider.swift`
  - Reads running app metadata and window titles from public macOS APIs.
- Create `Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift`
  - Polls detection, auto-starts recording, and exposes UI state for stop confirmation.
- Create `Tests/BabyRecorderTests/MeetingDetectorTests.swift`
  - Tests supported app and window-title matching without system dependencies.
- Create `Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift`
  - Tests auto-start and stop-suggestion behavior with fakes.
- Modify `Sources/BabyRecorder/BabyRecorderApp.swift`
  - Own a single `MeetingAutoRecorder` state object and pass it to main/status UI.
- Modify `Sources/BabyRecorder/UI/RootView.swift`
  - Start/stop auto detection only after runtime setup is ready.
- Modify `Sources/BabyRecorder/UI/ContentView.swift`
  - Show auto recording status and stop confirmation action.
- Modify `Sources/BabyRecorder/UI/StatusBarMenuView.swift`
  - Show auto recording status and stop confirmation action in the menu bar.
- Modify `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`
  - Add Chinese UI strings.
- Modify `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`
  - Add English UI strings.
- Modify `README.md`
  - Document automatic meeting recording, permission limitations, and confirmation-before-stop behavior.

---

### Task 1: Pure Meeting Detection

**Files:**
- Create: `Sources/BabyRecorder/MeetingDetection/MeetingApp.swift`
- Create: `Sources/BabyRecorder/MeetingDetection/MeetingDetector.swift`
- Test: `Tests/BabyRecorderTests/MeetingDetectorTests.swift`

- [ ] **Step 1: Write the failing detector tests**

Create `Tests/BabyRecorderTests/MeetingDetectorTests.swift`:

```swift
import XCTest
@testable import BabyRecorder

final class MeetingDetectorTests: XCTestCase {
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
                windowTitles: ["腾讯会议 - 项目同步会议"],
                canReadWindowMetadata: true
            )
        ])

        XCTAssertEqual(snapshot.status, .inMeeting)
        XCTAssertEqual(snapshot.app, .tencentMeeting)
        XCTAssertEqual(snapshot.displayName, "腾讯会议")
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
```

- [ ] **Step 2: Run the detector tests to verify they fail**

Run:

```bash
swift test --filter MeetingDetectorTests
```

Expected: FAIL because `MeetingDetector`, `RunningApplicationSnapshot`, and related types do not exist.

- [ ] **Step 3: Add the minimal detector implementation**

Create `Sources/BabyRecorder/MeetingDetection/MeetingApp.swift`:

```swift
import Foundation

enum MeetingApp: String, CaseIterable, Equatable, Sendable {
    case tencentMeeting
    case feishu
    case dingTalk

    var displayName: String {
        switch self {
        case .tencentMeeting:
            "腾讯会议"
        case .feishu:
            "飞书"
        case .dingTalk:
            "钉钉"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .tencentMeeting:
            ["com.tencent.meeting"]
        case .feishu:
            ["com.electron.lark"]
        case .dingTalk:
            ["com.alibaba.dingtalkmac", "com.alibaba.DingTalkMac"]
        }
    }

    var meetingKeywords: [String] {
        switch self {
        case .tencentMeeting:
            ["腾讯会议", "会议中", "共享屏幕", "Tencent Meeting", "Meeting"]
        case .feishu:
            ["飞书会议", "Lark Meeting", "Feishu Meeting", "会议中", "共享屏幕"]
        case .dingTalk:
            ["钉钉会议", "DingTalk Meeting", "会议中", "共享屏幕"]
        }
    }

    static func app(for bundleIdentifier: String) -> MeetingApp? {
        allCases.first { app in
            app.bundleIdentifiers.contains { candidate in
                candidate.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }
        }
    }
}
```

Create `Sources/BabyRecorder/MeetingDetection/MeetingDetector.swift`:

```swift
import Foundation

struct RunningApplicationSnapshot: Equatable, Sendable {
    var bundleIdentifier: String
    var localizedName: String
    var windowTitles: [String]
    var canReadWindowMetadata: Bool
}

enum MeetingDetectionStatus: Equatable, Sendable {
    case notInMeeting
    case inMeeting
    case windowMetadataUnavailable
}

struct MeetingDetectionSnapshot: Equatable, Sendable {
    var status: MeetingDetectionStatus
    var app: MeetingApp?
    var displayName: String?

    static let notInMeeting = MeetingDetectionSnapshot(status: .notInMeeting, app: nil, displayName: nil)
}

protocol MeetingApplicationProviding: Sendable {
    func runningApplications() async -> [RunningApplicationSnapshot]
}

struct MeetingDetector: Sendable {
    func detect(from applications: [RunningApplicationSnapshot]) -> MeetingDetectionSnapshot {
        var sawSupportedAppWithoutMetadata: (MeetingApp, String)?

        for application in applications {
            guard let app = MeetingApp.app(for: application.bundleIdentifier) else {
                continue
            }

            let displayName = application.localizedName.isEmpty ? app.displayName : application.localizedName
            guard application.canReadWindowMetadata else {
                sawSupportedAppWithoutMetadata = sawSupportedAppWithoutMetadata ?? (app, displayName)
                continue
            }

            if containsMeetingKeyword(in: application.windowTitles, for: app) {
                return MeetingDetectionSnapshot(status: .inMeeting, app: app, displayName: displayName)
            }
        }

        if let blocked = sawSupportedAppWithoutMetadata {
            return MeetingDetectionSnapshot(status: .windowMetadataUnavailable, app: blocked.0, displayName: blocked.1)
        }

        return .notInMeeting
    }

    private func containsMeetingKeyword(in titles: [String], for app: MeetingApp) -> Bool {
        titles.contains { title in
            app.meetingKeywords.contains { keyword in
                title.localizedCaseInsensitiveContains(keyword)
            }
        }
    }
}
```

- [ ] **Step 4: Run the detector tests to verify they pass**

Run:

```bash
swift test --filter MeetingDetectorTests
```

Expected: PASS.

- [ ] **Step 5: Commit pure detector work**

Run:

```bash
git add Sources/BabyRecorder/MeetingDetection/MeetingApp.swift Sources/BabyRecorder/MeetingDetection/MeetingDetector.swift Tests/BabyRecorderTests/MeetingDetectorTests.swift
git commit -m "feat: detect active meeting windows"
```

---

### Task 2: Auto Recording Controller

**Files:**
- Create: `Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift`
- Test: `Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift`

- [ ] **Step 1: Write failing auto-recorder tests**

Create `Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift`:

```swift
import XCTest
@testable import BabyRecorder

@MainActor
final class MeetingAutoRecorderTests: XCTestCase {
    func testDetectedMeetingStartsRecordingWhenReady() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [[
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["腾讯会议 - 语文课"],
                canReadWindowMetadata: true
            )
        ]])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.startCallCount, 1)
        XCTAssertEqual(viewModel.state, .recording)
        XCTAssertEqual(autoRecorder.status, .recordingStarted(appName: "腾讯会议"))
    }

    func testNoDuplicateStartWhileAlreadyRecording() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        await viewModel.startRecording()
        let provider = FakeMeetingApplicationProvider(snapshots: [[
            RunningApplicationSnapshot(
                bundleIdentifier: "com.electron.lark",
                localizedName: "飞书",
                windowTitles: ["飞书会议 - 产品评审"],
                canReadWindowMetadata: true
            )
        ]])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.startCallCount, 1)
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }

    func testMissingPermissionsDoNotAutoStart() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: false, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [[
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["腾讯会议 - 课程"],
                canReadWindowMetadata: true
            )
        ]])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.startCallCount, 0)
        XCTAssertEqual(autoRecorder.status, .blockedByRecordingPermissions)
    }

    func testMeetingDisappearsAfterAutoStartSuggestsStopWithoutStopping() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [
            [
                RunningApplicationSnapshot(
                    bundleIdentifier: "com.tencent.meeting",
                    localizedName: "腾讯会议",
                    windowTitles: ["腾讯会议 - 数学课"],
                    canReadWindowMetadata: true
                )
            ],
            [],
            []
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.stopCallCount, 0)
        XCTAssertTrue(autoRecorder.shouldSuggestStop)
        XCTAssertEqual(autoRecorder.status, .meetingMayHaveEnded(appName: "腾讯会议"))
    }

    func testConfirmSuggestedStopStopsRecordingAndClearsSuggestion() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [
            [
                RunningApplicationSnapshot(
                    bundleIdentifier: "com.tencent.meeting",
                    localizedName: "腾讯会议",
                    windowTitles: ["腾讯会议 - 英语课"],
                    canReadWindowMetadata: true
                )
            ],
            [],
            []
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.confirmStop(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.stopCallCount, 1)
        XCTAssertFalse(autoRecorder.shouldSuggestStop)
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }
}

private final class FakeMeetingApplicationProvider: MeetingApplicationProviding, @unchecked Sendable {
    private var snapshots: [[RunningApplicationSnapshot]]
    private var index = 0

    init(snapshots: [[RunningApplicationSnapshot]]) {
        self.snapshots = snapshots
    }

    func runningApplications() async -> [RunningApplicationSnapshot] {
        guard snapshots.isEmpty == false else {
            return []
        }
        let current = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return current
    }
}

private final class FakeAutoRecordingPermissionService: PermissionServicing, @unchecked Sendable {
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

private final class FakeAutoRecordingCaptureService: CaptureServicing, @unchecked Sendable {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        startCallCount += 1
    }

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
```

- [ ] **Step 2: Run the auto-recorder tests to verify they fail**

Run:

```bash
swift test --filter MeetingAutoRecorderTests
```

Expected: FAIL because `MeetingAutoRecorder` and `MeetingAutoRecordingStatus` do not exist.

- [ ] **Step 3: Implement the minimal auto-recorder controller**

Create `Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift`:

```swift
import Foundation
import Observation

enum MeetingAutoRecordingStatus: Equatable, Sendable {
    case monitoring
    case recordingStarted(appName: String)
    case meetingMayHaveEnded(appName: String)
    case blockedByRecordingPermissions
    case windowMetadataUnavailable(appName: String)
}

@MainActor
@Observable
final class MeetingAutoRecorder {
    private let provider: MeetingApplicationProviding
    private let detector: MeetingDetector
    private let endSuggestionMissThreshold: Int
    private var autoStartedAppName: String?
    private var consecutiveMisses = 0
    private var isPolling = false

    private(set) var status: MeetingAutoRecordingStatus = .monitoring

    init(
        provider: MeetingApplicationProviding = SystemMeetingApplicationProvider(),
        detector: MeetingDetector = MeetingDetector(),
        endSuggestionMissThreshold: Int = 3
    ) {
        self.provider = provider
        self.detector = detector
        self.endSuggestionMissThreshold = endSuggestionMissThreshold
    }

    var shouldSuggestStop: Bool {
        if case .meetingMayHaveEnded = status {
            return true
        }
        return false
    }

    func tick(recordingViewModel: RecordingViewModel) async {
        let applications = await provider.runningApplications()
        let detection = detector.detect(from: applications)

        switch detection.status {
        case .inMeeting:
            consecutiveMisses = 0
            let appName = detection.displayName ?? detection.app?.displayName ?? String(localized: "meetingAuto.app.unknown")
            if recordingViewModel.canStartRecording {
                await recordingViewModel.startRecording()
                autoStartedAppName = appName
                status = .recordingStarted(appName: appName)
            } else if recordingViewModel.state == .recording {
                if autoStartedAppName != nil {
                    status = .recordingStarted(appName: autoStartedAppName ?? appName)
                } else {
                    status = .monitoring
                }
            } else {
                status = .blockedByRecordingPermissions
            }

        case .windowMetadataUnavailable:
            if recordingViewModel.state != .recording {
                status = .windowMetadataUnavailable(appName: detection.displayName ?? detection.app?.displayName ?? String(localized: "meetingAuto.app.unknown"))
            }

        case .notInMeeting:
            guard autoStartedAppName != nil, recordingViewModel.state == .recording else {
                consecutiveMisses = 0
                status = .monitoring
                return
            }
            consecutiveMisses += 1
            if consecutiveMisses >= endSuggestionMissThreshold {
                status = .meetingMayHaveEnded(appName: autoStartedAppName!)
            }
        }
    }

    func confirmStop(recordingViewModel: RecordingViewModel) async {
        guard shouldSuggestStop else {
            return
        }
        await recordingViewModel.stopRecording()
        clearAutoStartedState()
    }

    func clearAutoStartedState() {
        autoStartedAppName = nil
        consecutiveMisses = 0
        status = .monitoring
    }
}
```

- [ ] **Step 4: Run auto-recorder tests to verify they pass**

Run:

```bash
swift test --filter MeetingAutoRecorderTests
```

Expected: PASS.

- [ ] **Step 5: Commit auto-recorder controller**

Run:

```bash
git add Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift
git commit -m "feat: add meeting auto recorder controller"
```

---

### Task 3: System Meeting Application Provider

**Files:**
- Create: `Sources/BabyRecorder/MeetingDetection/SystemMeetingApplicationProvider.swift`
- Test: extend `Tests/BabyRecorderTests/MeetingDetectorTests.swift`

- [ ] **Step 1: Write a small construction test**

Append to `MeetingDetectorTests`:

```swift
func testSystemProviderCanBeConstructed() {
    let provider = SystemMeetingApplicationProvider()
    XCTAssertNotNil(provider)
}
```

- [ ] **Step 2: Run the provider construction test to verify it fails**

Run:

```bash
swift test --filter MeetingDetectorTests/testSystemProviderCanBeConstructed
```

Expected: FAIL because `SystemMeetingApplicationProvider` does not exist.

- [ ] **Step 3: Implement the system provider**

Create `Sources/BabyRecorder/MeetingDetection/SystemMeetingApplicationProvider.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SystemMeetingApplicationProvider: MeetingApplicationProviding {
    func runningApplications() async -> [RunningApplicationSnapshot] {
        let applications = NSWorkspace.shared.runningApplications
        let windowTitles = Self.visibleWindowTitlesByProcessID()
        let accessibilityTrusted = AXIsProcessTrusted()

        return applications.compactMap { application in
            guard let bundleIdentifier = application.bundleIdentifier,
                  MeetingApp.app(for: bundleIdentifier) != nil else {
                return nil
            }

            let titles = windowTitles[application.processIdentifier] ?? []
            let accessibilityTitles = accessibilityTrusted ? Self.accessibilityWindowTitles(for: application.processIdentifier) : []
            let mergedTitles = Array(Set(titles + accessibilityTitles))

            return RunningApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                localizedName: application.localizedName ?? "",
                windowTitles: mergedTitles,
                canReadWindowMetadata: accessibilityTrusted || mergedTitles.isEmpty == false
            )
        }
    }

    private static func visibleWindowTitlesByProcessID() -> [pid_t: [String]] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var titlesByPID: [pid_t: [String]] = [:]
        for window in windowInfo {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let title = window[kCGWindowName as String] as? String,
                  title.isEmpty == false else {
                continue
            }
            titlesByPID[ownerPID, default: []].append(title)
        }
        return titlesByPID
    }

    private static func accessibilityWindowTitles(for processIdentifier: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window in
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String,
                  title.isEmpty == false else {
                return nil
            }
            return title
        }
    }
}
```

- [ ] **Step 4: Run provider test and detector tests**

Run:

```bash
swift test --filter MeetingDetectorTests
```

Expected: PASS.

- [ ] **Step 5: Commit system provider**

Run:

```bash
git add Sources/BabyRecorder/MeetingDetection/SystemMeetingApplicationProvider.swift Tests/BabyRecorderTests/MeetingDetectorTests.swift
git commit -m "feat: read meeting app window metadata"
```

---

### Task 4: Wire Auto Recorder Into App Lifecycle

**Files:**
- Modify: `Sources/BabyRecorder/BabyRecorderApp.swift`
- Modify: `Sources/BabyRecorder/UI/RootView.swift`
- Test: extend `Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift`

- [ ] **Step 1: Write a lifecycle-oriented controller test**

Append to `MeetingAutoRecorderTests`:

```swift
func testPollingCanBeStartedAndStoppedWithoutStartingWhenNoMeetingExists() async {
    let captureService = FakeAutoRecordingCaptureService()
    let viewModel = RecordingViewModel(
        permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
        captureService: captureService
    )
    await viewModel.checkPermissions()
    let provider = FakeMeetingApplicationProvider(snapshots: [[]])
    let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

    await autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
    await Task.yield()
    autoRecorder.stopMonitoring()

    XCTAssertEqual(captureService.startCallCount, 0)
}
```

- [ ] **Step 2: Run the lifecycle test to verify it fails**

Run:

```bash
swift test --filter MeetingAutoRecorderTests/testPollingCanBeStartedAndStoppedWithoutStartingWhenNoMeetingExists
```

Expected: FAIL because `startMonitoring` and `stopMonitoring` do not exist.

- [ ] **Step 3: Add polling lifecycle methods**

Modify `MeetingAutoRecorder`:

```swift
private var pollingTask: Task<Void, Never>?

func startMonitoring(
    recordingViewModel: RecordingViewModel,
    intervalNanoseconds: UInt64 = 5_000_000_000
) {
    guard pollingTask == nil else {
        return
    }

    pollingTask = Task { @MainActor [weak self, weak recordingViewModel] in
        while !Task.isCancelled {
            guard let self, let recordingViewModel else {
                return
            }
            await self.tick(recordingViewModel: recordingViewModel)
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}

func stopMonitoring() {
    pollingTask?.cancel()
    pollingTask = nil
    clearAutoStartedState()
}
```

- [ ] **Step 4: Wire app state**

Modify `BabyRecorderApp`:

```swift
@State private var meetingAutoRecorder = MeetingAutoRecorder()
```

Pass it to `RootView` and `StatusBarMenuView`:

```swift
RootView(
    recordingViewModel: viewModel,
    runtimeSetupViewModel: runtimeSetupViewModel,
    meetingAutoRecorder: meetingAutoRecorder
)
```

```swift
StatusBarMenuView(
    viewModel: viewModel,
    meetingAutoRecorder: meetingAutoRecorder,
    openMainWindow: openMainWindow,
    quit: {
        NSApp.terminate(nil)
    }
)
```

Modify `RootView` initializer properties and start monitoring only when ready:

```swift
struct RootView: View {
    @Bindable var recordingViewModel: RecordingViewModel
    @Bindable var runtimeSetupViewModel: RuntimeSetupViewModel
    @Bindable var meetingAutoRecorder: MeetingAutoRecorder

    var body: some View {
        switch runtimeSetupViewModel.phase {
        case .ready:
            ContentView(recordingViewModel: recordingViewModel, meetingAutoRecorder: meetingAutoRecorder)
                .task {
                    await recordingViewModel.checkPermissions()
                    meetingAutoRecorder.startMonitoring(recordingViewModel: recordingViewModel)
                }
                .onDisappear {
                    meetingAutoRecorder.stopMonitoring()
                }
        case .checking, .installing, .failed:
            RuntimeSetupView(viewModel: runtimeSetupViewModel)
                .task {
                    await runtimeSetupViewModel.prepareIfNeeded()
                }
        }
    }
}
```

- [ ] **Step 5: Run lifecycle tests**

Run:

```bash
swift test --filter MeetingAutoRecorderTests
```

Expected: PASS.

- [ ] **Step 6: Commit lifecycle wiring**

Run:

```bash
git add Sources/BabyRecorder/BabyRecorderApp.swift Sources/BabyRecorder/UI/RootView.swift Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift Tests/BabyRecorderTests/MeetingAutoRecorderTests.swift
git commit -m "feat: monitor meetings after runtime setup"
```

---

### Task 5: Add UI Status And Confirmation Actions

**Files:**
- Modify: `Sources/BabyRecorder/UI/ContentView.swift`
- Modify: `Sources/BabyRecorder/UI/StatusBarMenuView.swift`
- Modify: `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`
- Test: existing UI compile tests via `swift test`

- [ ] **Step 1: Add UI-facing text helper**

Add to `MeetingAutoRecorder.swift`:

```swift
extension MeetingAutoRecordingStatus {
    var localizedMessage: String {
        switch self {
        case .monitoring:
            String(localized: "meetingAuto.status.monitoring")
        case .recordingStarted(let appName):
            String(format: NSLocalizedString("meetingAuto.status.recordingStarted %@", comment: ""), appName)
        case .meetingMayHaveEnded(let appName):
            String(format: NSLocalizedString("meetingAuto.status.mayHaveEnded %@", comment: ""), appName)
        case .blockedByRecordingPermissions:
            String(localized: "meetingAuto.status.blockedByPermissions")
        case .windowMetadataUnavailable(let appName):
            String(format: NSLocalizedString("meetingAuto.status.windowMetadataUnavailable %@", comment: ""), appName)
        }
    }
}
```

- [ ] **Step 2: Modify main window UI**

Change `ContentView` signature:

```swift
struct ContentView: View {
    @Bindable var recordingViewModel: RecordingViewModel
    @Bindable var meetingAutoRecorder: MeetingAutoRecorder
```

Replace `viewModel` references with `recordingViewModel`, then insert after the permissions/output `HStack`:

```swift
StatusRow(
    title: "meetingAuto.label",
    value: meetingAutoRecorder.status.localizedMessage,
    status: meetingAutoTone
)

if meetingAutoRecorder.shouldSuggestStop {
    Button {
        Task { await meetingAutoRecorder.confirmStop(recordingViewModel: recordingViewModel) }
    } label: {
        Label("meetingAuto.action.stopRecording", systemImage: "stop.circle")
    }
    .buttonStyle(.borderedProminent)
}
```

Add tone helper:

```swift
private var meetingAutoTone: StatusTone {
    switch meetingAutoRecorder.status {
    case .recordingStarted:
        .success
    case .meetingMayHaveEnded, .blockedByRecordingPermissions, .windowMetadataUnavailable:
        .warning
    case .monitoring:
        .neutral
    }
}
```

- [ ] **Step 3: Modify status bar menu**

Change `StatusBarMenuView` signature:

```swift
struct StatusBarMenuView: View {
    let viewModel: RecordingViewModel
    let meetingAutoRecorder: MeetingAutoRecorder
    let openMainWindow: () -> Void
    let quit: () -> Void
```

Add near the top after the current recording status:

```swift
Text(meetingAutoRecorder.status.localizedMessage)

if meetingAutoRecorder.shouldSuggestStop {
    Button {
        Task { await meetingAutoRecorder.confirmStop(recordingViewModel: viewModel) }
    } label: {
        Label("meetingAuto.action.stopRecording", systemImage: "stop.circle")
    }
}
```

- [ ] **Step 4: Add Chinese localizations**

Append to `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`:

```text
"meetingAuto.label" = "自动检测会议";
"meetingAuto.status.monitoring" = "自动检测会议：开启";
"meetingAuto.status.recordingStarted %@" = "检测到%@，已自动开始录制";
"meetingAuto.status.mayHaveEnded %@" = "%@可能已结束，是否停止录制？";
"meetingAuto.status.blockedByPermissions" = "检测到会议，但录制权限不足";
"meetingAuto.status.windowMetadataUnavailable %@" = "需要辅助功能权限才能自动识别%@";
"meetingAuto.action.stopRecording" = "停止录制";
"meetingAuto.app.unknown" = "会议 App";
```

- [ ] **Step 5: Add English localizations**

Append to `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`:

```text
"meetingAuto.label" = "Meeting Detection";
"meetingAuto.status.monitoring" = "Automatic meeting detection: On";
"meetingAuto.status.recordingStarted %@" = "Detected %@ and started recording";
"meetingAuto.status.mayHaveEnded %@" = "%@ may have ended. Stop recording?";
"meetingAuto.status.blockedByPermissions" = "Meeting detected, but recording permissions are missing";
"meetingAuto.status.windowMetadataUnavailable %@" = "Accessibility permission is needed to detect %@ meetings";
"meetingAuto.action.stopRecording" = "Stop Recording";
"meetingAuto.app.unknown" = "Meeting App";
```

- [ ] **Step 6: Run tests to catch compile failures**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit UI integration**

Run:

```bash
git add Sources/BabyRecorder/UI/ContentView.swift Sources/BabyRecorder/UI/StatusBarMenuView.swift Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings Sources/BabyRecorder/Resources/en.lproj/Localizable.strings Sources/BabyRecorder/MeetingDetection/MeetingAutoRecorder.swift
git commit -m "feat: show meeting auto recording status"
```

---

### Task 6: Documentation And Verification

**Files:**
- Modify: `README.md`
- Verify: full test suite and shell syntax checks

- [ ] **Step 1: Update README**

Add a bullet under "当前实现":

```markdown
- 支持自动识别腾讯会议、飞书/Lark、钉钉的会议窗口，并在检测到会议中时自动开始录制；会议可能结束时会提示用户确认停止，不会自动切断录音。
```

Add a note under "注意事项":

```markdown
- 自动会议识别依赖 macOS 允许 App 读取会议窗口标题。如果系统未授予辅助功能相关权限，BabyRecorder 会保守地不自动开始，手动录制仍可正常使用。
```

- [ ] **Step 2: Run full tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Run script syntax checks**

Run:

```bash
bash -n Scripts/install_baby_recorder_runtime.sh Scripts/transcribe_mlx_qwen3_asr.sh Sources/BabyRecorder/Resources/Scripts/transcribe_mlx_qwen3_asr.sh Sources/BabyRecorder/Resources/Scripts/setup_baby_recorder_runtime.sh Scripts/make_distribution.sh
```

Expected: no output and exit code 0.

- [ ] **Step 4: Optional local app launch smoke check**

Run:

```bash
Scripts/package_app.sh
```

Expected: prints a path ending in `BabyRecorder.app`.

Open the app manually from the printed path, launch Tencent Meeting or Feishu/Lark, and confirm:

- Ordinary app home/chat windows do not auto-start recording.
- Meeting-like windows trigger automatic recording.
- Closing or leaving the meeting shows a stop suggestion instead of stopping immediately.

- [ ] **Step 5: Commit docs and verification updates**

Run:

```bash
git add README.md
git commit -m "docs: document automatic meeting recording"
```

---

## Self-Review

- Spec coverage: Task 1 covers app allowlists and conservative keyword matching. Task 2 covers auto-start, duplicate prevention, missing permissions, and stop suggestion. Task 3 covers public macOS API integration and privacy-safe degradation. Task 4 covers runtime-ready lifecycle wiring. Task 5 covers main window and status bar UI. Task 6 covers README and verification.
- Red-flag scan: no forbidden markers are present.
- Type consistency: `MeetingApp`, `RunningApplicationSnapshot`, `MeetingDetector`, `MeetingDetectionSnapshot`, `MeetingAutoRecordingStatus`, `MeetingAutoRecorder`, and `MeetingApplicationProviding` are introduced before use and reused consistently across later tasks.
