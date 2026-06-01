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
                windowTitles: ["会议中 - 语文课"],
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
                windowTitles: ["会议中 - 课程"],
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
                    windowTitles: ["会议中 - 数学课"],
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
                    windowTitles: ["会议中 - 英语课"],
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

    func testExternalStopClearsAutoStartedOwnershipBeforeLaterManualRecording() async {
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
                    windowTitles: ["会议中 - 物理课"],
                    canReadWindowMetadata: true
                )
            ],
            [],
            [],
            []
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)
        await viewModel.stopRecording()
        await Task.yield()
        await viewModel.startRecording()
        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertFalse(autoRecorder.shouldSuggestStop)
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }

    func testFailedAutoStartDoesNotClaimRecordingOwnership() async {
        let captureService = FakeAutoRecordingCaptureService()
        captureService.startError = FakeAutoRecordingCaptureError.startFailed
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
                    windowTitles: ["会议中 - 化学课"],
                    canReadWindowMetadata: true
                )
            ],
            [],
            []
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(captureService.startCallCount, 1)
        XCTAssertEqual(viewModel.state, .failed("startFailed"))
        XCTAssertEqual(autoRecorder.status, .monitoring)

        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertFalse(autoRecorder.shouldSuggestStop)
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }

    func testFailedAutoStartWithMeetingStillDetectedDoesNotReportPermissionBlock() async {
        let captureService = FakeAutoRecordingCaptureService()
        captureService.startError = FakeAutoRecordingCaptureError.startFailed
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
                    windowTitles: ["会议中 - 历史课"],
                    canReadWindowMetadata: true
                )
            ],
            [
                RunningApplicationSnapshot(
                    bundleIdentifier: "com.tencent.meeting",
                    localizedName: "腾讯会议",
                    windowTitles: ["会议中 - 历史课"],
                    canReadWindowMetadata: true
                )
            ]
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        await autoRecorder.tick(recordingViewModel: viewModel)
        await autoRecorder.tick(recordingViewModel: viewModel)

        XCTAssertEqual(viewModel.permissionStatus.isReady, true)
        XCTAssertEqual(viewModel.state, .failed("startFailed"))
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }

    func testPollingCanBeStartedAndStoppedWithoutStartingWhenNoMeetingExists() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [[]])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
        await Task.yield()
        autoRecorder.stopMonitoring()

        XCTAssertEqual(captureService.startCallCount, 0)
    }

    func testStoppedPollingDoesNotStartRecordingAfterDelayedProviderReturnsMeeting() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = DelayedMeetingApplicationProvider(applications: [
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["会议中 - 生物课"],
                canReadWindowMetadata: true
            )
        ])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
        await provider.waitUntilEntryCount(1)
        autoRecorder.stopMonitoring()
        await provider.releaseAll()
        try? await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertEqual(captureService.startCallCount, 0)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(autoRecorder.status, .monitoring)
    }

    func testStoppedPollingStopsRecordingStartedAfterDelayedCaptureReturns() async {
        let captureService = DelayedAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = FakeMeetingApplicationProvider(snapshots: [[
            RunningApplicationSnapshot(
                bundleIdentifier: "com.tencent.meeting",
                localizedName: "腾讯会议",
                windowTitles: ["会议中 - 地理课"],
                canReadWindowMetadata: true
            )
        ]])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
        await captureService.waitUntilStartCount(1)
        autoRecorder.stopMonitoring()
        await captureService.releaseStarts()
        try? await Task.sleep(nanoseconds: 1_000_000)
        let startCallCount = await captureService.startCallCount
        let stopCallCount = await captureService.stopCallCount

        XCTAssertEqual(startCallCount, 1)
        XCTAssertEqual(stopCallCount, 1)
        XCTAssertEqual(viewModel.state, .finished)
        XCTAssertEqual(autoRecorder.status, .monitoring)
        XCTAssertFalse(autoRecorder.shouldSuggestStop)
    }

    func testStartMonitoringDoesNotCreateDuplicatePollingTasks() async {
        let captureService = FakeAutoRecordingCaptureService()
        let viewModel = RecordingViewModel(
            permissionService: FakeAutoRecordingPermissionService(screen: true, mic: true),
            captureService: captureService
        )
        await viewModel.checkPermissions()
        let provider = DelayedMeetingApplicationProvider(applications: [])
        let autoRecorder = MeetingAutoRecorder(provider: provider, endSuggestionMissThreshold: 2)

        autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
        autoRecorder.startMonitoring(recordingViewModel: viewModel, intervalNanoseconds: 1_000_000)
        await provider.waitUntilEntryCount(1)
        try? await Task.sleep(nanoseconds: 1_000_000)
        let entryCount = await provider.entryCount
        autoRecorder.stopMonitoring()
        await provider.releaseAll()

        XCTAssertEqual(entryCount, 1)
        XCTAssertEqual(captureService.startCallCount, 0)
    }
}

private actor DelayedAutoRecordingCaptureService: CaptureServicing {
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var startEntryContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        await withCheckedContinuation { continuation in
            startCallCount += 1
            startContinuations.append(continuation)
            resumeSatisfiedStartEntryContinuations()
        }
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

    func waitUntilStartCount(_ expectedStartCount: Int) async {
        if startCallCount >= expectedStartCount {
            return
        }

        await withCheckedContinuation { continuation in
            startEntryContinuations.append((expectedStartCount, continuation))
        }
    }

    func releaseStarts() {
        let continuations = startContinuations
        startContinuations = []
        continuations.forEach { continuation in
            continuation.resume()
        }
    }

    private func resumeSatisfiedStartEntryContinuations() {
        let readyContinuations = startEntryContinuations.filter { expectedStartCount, _ in
            startCallCount >= expectedStartCount
        }
        startEntryContinuations.removeAll { expectedStartCount, _ in
            startCallCount >= expectedStartCount
        }
        readyContinuations.forEach { _, continuation in
            continuation.resume()
        }
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

private actor DelayedMeetingApplicationProvider: MeetingApplicationProviding {
    private let applications: [RunningApplicationSnapshot]
    private var runningContinuations: [CheckedContinuation<[RunningApplicationSnapshot], Never>] = []
    private var entryContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var entryCount = 0

    init(applications: [RunningApplicationSnapshot]) {
        self.applications = applications
    }

    func runningApplications() async -> [RunningApplicationSnapshot] {
        await withCheckedContinuation { continuation in
            entryCount += 1
            runningContinuations.append(continuation)
            resumeSatisfiedEntryContinuations()
        }
    }

    func waitUntilEntryCount(_ expectedEntryCount: Int) async {
        if entryCount >= expectedEntryCount {
            return
        }

        await withCheckedContinuation { continuation in
            entryContinuations.append((expectedEntryCount, continuation))
        }
    }

    func releaseAll() {
        let continuations = runningContinuations
        runningContinuations = []
        continuations.forEach { continuation in
            continuation.resume(returning: applications)
        }
    }

    private func resumeSatisfiedEntryContinuations() {
        let readyContinuations = entryContinuations.filter { expectedEntryCount, _ in
            entryCount >= expectedEntryCount
        }
        entryContinuations.removeAll { expectedEntryCount, _ in
            entryCount >= expectedEntryCount
        }
        readyContinuations.forEach { _, continuation in
            continuation.resume()
        }
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

private enum FakeAutoRecordingCaptureError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        "startFailed"
    }
}

private final class FakeAutoRecordingCaptureService: CaptureServicing, @unchecked Sendable {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var startError: Error?

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
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
