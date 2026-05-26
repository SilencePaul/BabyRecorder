# Baby Recorder UI and Status Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Baby Recorder MVP into a localized Chinese-first macOS utility with a polished single-window UI, menu bar controls, and close-to-hide window behavior.

**Architecture:** Preserve the existing recording pipeline and `RecordingViewModel -> CaptureService` boundary. Add a small presentation layer for testable UI state, a file reveal service for Finder actions, localized resources for Chinese/English UI text, and an app shell that shares one `RecordingViewModel` between the main window, commands, and status bar menu.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, XCTest, ScreenCaptureKit.

---

## File Structure

- Modify `Package.swift`: add processed resources for localization files.
- Modify `Scripts/package_app.sh`: copy localized `.lproj` resources into the packaged `.app`.
- Modify `Sources/BabyRecorder/BabyRecorderApp.swift`: add shared app shell, status bar scene, commands, and app delegate wiring.
- Modify `Sources/BabyRecorder/UI/ContentView.swift`: replace the minimal MVP UI with the refined Chinese-first console UI.
- Modify `Sources/BabyRecorder/UI/RecordingViewModel.swift`: add presentation helpers and Finder reveal action without changing capture behavior.
- Create `Sources/BabyRecorder/UI/RecordingPresentation.swift`: maps recording state and permissions to stable UI categories and localization keys.
- Create `Sources/BabyRecorder/UI/StatusBarMenuView.swift`: status bar menu surface that calls the same view model actions.
- Create `Sources/BabyRecorder/UI/WindowCloseHider.swift`: AppKit bridge that turns red close into hide.
- Create `Sources/BabyRecorder/Support/FilePresenter.swift`: injectable Finder reveal service.
- Create `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`: Simplified Chinese UI text.
- Create `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`: English UI text.
- Create `Tests/BabyRecorderTests/RecordingPresentationTests.swift`: unit tests for presentation mapping.
- Modify `Tests/BabyRecorderTests/RecordingViewModelTests.swift`: add Finder reveal behavior tests and update fake dependencies.

## Task 1: Presentation Mapping

**Files:**
- Create: `Sources/BabyRecorder/UI/RecordingPresentation.swift`
- Test: `Tests/BabyRecorderTests/RecordingPresentationTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Create `Tests/BabyRecorderTests/RecordingPresentationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the presentation tests and verify they fail**

Run:

```bash
swift test --filter RecordingPresentationTests
```

Expected: FAIL because `RecordingPresentation` does not exist.

- [ ] **Step 3: Implement the minimal presentation model**

Create `Sources/BabyRecorder/UI/RecordingPresentation.swift`:

```swift
import Foundation

struct RecordingPresentation: Equatable {
    enum Kind: Equatable {
        case checkingPermissions
        case permissionsMissing
        case ready
        case starting
        case recording
        case stopping
        case finished
        case finishedWithMixFailure
        case failed
    }

    enum PrimaryAction: Equatable {
        case start
        case stop
        case openSettings
        case none
    }

    enum PermissionStatusKind: Equatable {
        case ready
        case missing
    }

    enum ValidationStatus: Equatable {
        case notAvailable
        case passed
        case failed
    }

    struct PermissionRow: Equatable {
        var labelKey: String
        var status: PermissionStatusKind

        var statusKey: String {
            switch status {
            case .ready:
                "permission.status.ready"
            case .missing:
                "permission.status.missing"
            }
        }
    }

    let kind: Kind
    let titleKey: String
    let subtitleKey: String
    let primaryAction: PrimaryAction
    let permissionRows: [PermissionRow]
    let validationStatus: ValidationStatus
    let outputDirectory: URL?
    let failureMessage: String?

    init(
        state: RecordingState,
        permissions: PermissionStatus,
        validation: ValidationResult?,
        outputDirectory: URL?
    ) {
        self.kind = Self.kind(for: state)
        self.titleKey = Self.titleKey(for: state)
        self.subtitleKey = Self.subtitleKey(for: state)
        self.primaryAction = Self.primaryAction(for: state)
        self.permissionRows = [
            PermissionRow(
                labelKey: "permission.screenRecording",
                status: permissions.screenRecordingGranted ? .ready : .missing
            ),
            PermissionRow(
                labelKey: "permission.microphone",
                status: permissions.microphoneGranted ? .ready : .missing
            )
        ]
        self.validationStatus = Self.validationStatus(for: validation)
        self.outputDirectory = outputDirectory
        if case .failed(let message) = state {
            self.failureMessage = message
        } else {
            self.failureMessage = nil
        }
    }

    var canRevealOutput: Bool {
        outputDirectory != nil
    }

    var showsFailureMessage: Bool {
        failureMessage?.isEmpty == false
    }

    private static func kind(for state: RecordingState) -> Kind {
        switch state {
        case .checkingPermissions:
            .checkingPermissions
        case .permissionsMissing:
            .permissionsMissing
        case .ready:
            .ready
        case .starting:
            .starting
        case .recording:
            .recording
        case .stopping:
            .stopping
        case .finished:
            .finished
        case .finishedWithMixFailure:
            .finishedWithMixFailure
        case .failed:
            .failed
        }
    }

    private static func titleKey(for state: RecordingState) -> String {
        switch state {
        case .checkingPermissions:
            "recording.state.checkingPermissions.title"
        case .permissionsMissing:
            "recording.state.permissionsMissing.title"
        case .ready:
            "recording.state.ready.title"
        case .starting:
            "recording.state.starting.title"
        case .recording:
            "recording.state.recording.title"
        case .stopping:
            "recording.state.stopping.title"
        case .finished:
            "recording.state.finished.title"
        case .finishedWithMixFailure:
            "recording.state.mixFailure.title"
        case .failed:
            "recording.state.failed.title"
        }
    }

    private static func subtitleKey(for state: RecordingState) -> String {
        switch state {
        case .checkingPermissions:
            "recording.state.checkingPermissions.subtitle"
        case .permissionsMissing:
            "recording.state.permissionsMissing.subtitle"
        case .ready:
            "recording.state.ready.subtitle"
        case .starting:
            "recording.state.starting.subtitle"
        case .recording:
            "recording.state.recording.subtitle"
        case .stopping:
            "recording.state.stopping.subtitle"
        case .finished:
            "recording.state.finished.subtitle"
        case .finishedWithMixFailure:
            "recording.state.mixFailure.subtitle"
        case .failed:
            "recording.state.failed.subtitle"
        }
    }

    private static func primaryAction(for state: RecordingState) -> PrimaryAction {
        switch state {
        case .ready, .finished, .finishedWithMixFailure:
            .start
        case .recording:
            .stop
        case .permissionsMissing:
            .openSettings
        case .checkingPermissions, .starting, .stopping, .failed:
            .none
        }
    }

    private static func validationStatus(for validation: ValidationResult?) -> ValidationStatus {
        guard let validation else {
            return .notAvailable
        }
        return validation.passed ? .passed : .failed
    }
}
```

- [ ] **Step 4: Run the presentation tests and verify they pass**

Run:

```bash
swift test --filter RecordingPresentationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabyRecorder/UI/RecordingPresentation.swift Tests/BabyRecorderTests/RecordingPresentationTests.swift
git commit -m "test: add recording presentation mapping"
```

## Task 2: Finder Reveal Action

**Files:**
- Create: `Sources/BabyRecorder/Support/FilePresenter.swift`
- Modify: `Sources/BabyRecorder/UI/RecordingViewModel.swift`
- Modify: `Tests/BabyRecorderTests/RecordingViewModelTests.swift`

- [ ] **Step 1: Add failing view-model tests for output reveal**

Append these tests inside `RecordingViewModelTests`:

```swift
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
```

Append this fake below `FakeCaptureService`:

```swift
private final class FakeFilePresenter: FilePresenting, @unchecked Sendable {
    private(set) var revealedURLs: [URL] = []

    func revealInFinder(_ url: URL) {
        revealedURLs.append(url)
    }
}
```

- [ ] **Step 2: Run the reveal tests and verify they fail**

Run:

```bash
swift test --filter RecordingViewModelTests/testRevealOutput
```

Expected: FAIL because `FilePresenting`, the new initializer argument, and `revealOutputDirectory()` do not exist.

- [ ] **Step 3: Implement the file presenter service**

Create `Sources/BabyRecorder/Support/FilePresenter.swift`:

```swift
import AppKit
import Foundation

protocol FilePresenting: Sendable {
    func revealInFinder(_ url: URL)
}

struct FinderFilePresenter: FilePresenting {
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
```

- [ ] **Step 4: Add reveal support to the view model**

Modify `Sources/BabyRecorder/UI/RecordingViewModel.swift`:

```swift
@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .checkingPermissions
    @Published private(set) var permissionStatus = PermissionStatus(screenRecordingGranted: false, microphoneGranted: false)
    @Published private(set) var outputDirectory: URL?
    @Published private(set) var validation: ValidationResult?

    private let permissionService: PermissionServicing
    private let captureService: CaptureServicing
    private let filePresenter: FilePresenting

    init(
        permissionService: PermissionServicing = PermissionService(),
        captureService: CaptureServicing,
        filePresenter: FilePresenting = FinderFilePresenter()
    ) {
        self.permissionService = permissionService
        self.captureService = captureService
        self.filePresenter = filePresenter
    }

    var canStartRecording: Bool {
        isStartableState && permissionStatus.isReady
    }

    var canRevealOutputDirectory: Bool {
        outputDirectory != nil
    }

    var presentation: RecordingPresentation {
        RecordingPresentation(
            state: state,
            permissions: permissionStatus,
            validation: validation,
            outputDirectory: outputDirectory
        )
    }

    func revealOutputDirectory() {
        guard let outputDirectory else {
            return
        }
        filePresenter.revealInFinder(outputDirectory)
    }

    func checkPermissions() async {
        let preservesActiveState = state == .starting || state == .recording || state == .stopping
        if !preservesActiveState {
            state = .checkingPermissions
        }

        let status = await permissionService.checkPermissions()
        permissionStatus = status
        guard !preservesActiveState else {
            return
        }

        state = status.isReady ? .ready : .permissionsMissing
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func startRecording() async {
        guard state != .starting && state != .recording && state != .stopping else {
            return
        }

        guard isStartableState else {
            if !permissionStatus.isReady {
                state = .permissionsMissing
            }
            return
        }

        guard permissionStatus.isReady else {
            state = .permissionsMissing
            return
        }

        do {
            state = .starting
            outputDirectory = nil
            validation = nil
            try await captureService.start(permissionSnapshot: permissionStatus.snapshot)
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard state == .recording else {
            return
        }

        do {
            state = .stopping
            let completion = try await captureService.stop()
            outputDirectory = completion.outputDirectory
            validation = completion.validation
            state = completion.mixFailed ? .finishedWithMixFailure : .finished
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var isStartableState: Bool {
        state == .ready || state == .finished || state == .finishedWithMixFailure
    }
}
```

- [ ] **Step 5: Run the reveal tests and full view-model tests**

Run:

```bash
swift test --filter RecordingViewModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/BabyRecorder/Support/FilePresenter.swift Sources/BabyRecorder/UI/RecordingViewModel.swift Tests/BabyRecorderTests/RecordingViewModelTests.swift
git commit -m "feat: add output reveal action"
```

## Task 3: Localization Resources

**Files:**
- Modify: `Package.swift`
- Modify: `Scripts/package_app.sh`
- Create: `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`

- [ ] **Step 1: Add localization resource files**

Create `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`:

```text
"app.title" = "宝宝录音";
"menu.recording" = "录制";
"menu.openMainWindow" = "打开主窗口";
"menu.recheckPermissions" = "重新检查权限";
"menu.openSystemSettings" = "打开系统设置";
"menu.revealLatestOutput" = "显示最近输出";
"menu.quit" = "退出宝宝录音";
"menu.status" = "状态";

"recording.action.start" = "开始";
"recording.action.stop" = "停止";
"recording.action.openSettings" = "打开设置";
"recording.action.recheck" = "重新检查";
"recording.action.showInFinder" = "在 Finder 显示";

"recording.state.checkingPermissions.title" = "正在检查权限";
"recording.state.checkingPermissions.subtitle" = "正在确认屏幕录制和麦克风权限。";
"recording.state.permissionsMissing.title" = "权限不足";
"recording.state.permissionsMissing.subtitle" = "请开启屏幕录制和麦克风权限，然后重新检查。";
"recording.state.ready.title" = "准备录制";
"recording.state.ready.subtitle" = "系统声音和麦克风已就绪。点击开始后，窗口可关闭，录制会继续在状态栏运行。";
"recording.state.starting.title" = "正在开始";
"recording.state.starting.subtitle" = "正在准备录音文件和系统音频捕获。";
"recording.state.recording.title" = "正在录制";
"recording.state.recording.subtitle" = "可以关闭窗口，录制会继续在状态栏运行。";
"recording.state.stopping.title" = "正在停止";
"recording.state.stopping.subtitle" = "正在保存音频、混音并写入诊断文件。";
"recording.state.finished.title" = "录制完成";
"recording.state.finished.subtitle" = "音频文件已保存，可以在 Finder 中查看。";
"recording.state.mixFailure.title" = "录制完成，混音失败";
"recording.state.mixFailure.subtitle" = "原始系统声音和麦克风文件已保留，请查看输出目录。";
"recording.state.failed.title" = "录制失败";
"recording.state.failed.subtitle" = "录制没有完成，请查看错误信息后重试。";

"permission.screenRecording" = "屏幕录制权限";
"permission.microphone" = "麦克风权限";
"permission.status.ready" = "已就绪";
"permission.status.missing" = "缺失";

"section.permissions" = "权限和状态";
"section.output" = "最近输出";
"label.recordingState" = "录制状态";
"label.validation" = "校验结果";
"label.diagnostics" = "诊断文件";
"label.outputDirectory" = "保存位置";
"label.noOutput" = "还没有输出";
"validation.notAvailable" = "未生成";
"validation.passed" = "通过";
"validation.failed" = "失败";
"diagnostics.sessionJSON" = "session.json";

"quit.confirm.title" = "正在录制";
"quit.confirm.message" = "退出会停止当前录制。确定要退出吗？";
"quit.confirm.quit" = "退出";
"quit.confirm.cancel" = "继续录制";
```

Create `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`:

```text
"app.title" = "Baby Recorder";
"menu.recording" = "Recording";
"menu.openMainWindow" = "Open Main Window";
"menu.recheckPermissions" = "Re-check Permissions";
"menu.openSystemSettings" = "Open System Settings";
"menu.revealLatestOutput" = "Reveal Latest Output";
"menu.quit" = "Quit Baby Recorder";
"menu.status" = "Status";

"recording.action.start" = "Start";
"recording.action.stop" = "Stop";
"recording.action.openSettings" = "Open Settings";
"recording.action.recheck" = "Re-check";
"recording.action.showInFinder" = "Show in Finder";

"recording.state.checkingPermissions.title" = "Checking Permissions";
"recording.state.checkingPermissions.subtitle" = "Confirming Screen Recording and Microphone access.";
"recording.state.permissionsMissing.title" = "Permissions Missing";
"recording.state.permissionsMissing.subtitle" = "Enable Screen Recording and Microphone access, then re-check.";
"recording.state.ready.title" = "Ready to Record";
"recording.state.ready.subtitle" = "System audio and microphone are ready. Recording continues from the menu bar if you close the window.";
"recording.state.starting.title" = "Starting";
"recording.state.starting.subtitle" = "Preparing audio files and system capture.";
"recording.state.recording.title" = "Recording";
"recording.state.recording.subtitle" = "You can close the window; recording continues from the menu bar.";
"recording.state.stopping.title" = "Stopping";
"recording.state.stopping.subtitle" = "Saving audio, mixing tracks, and writing diagnostics.";
"recording.state.finished.title" = "Recording Finished";
"recording.state.finished.subtitle" = "Audio files are saved and ready to reveal in Finder.";
"recording.state.mixFailure.title" = "Recorded, Mix Failed";
"recording.state.mixFailure.subtitle" = "Original system and microphone files were preserved in the output folder.";
"recording.state.failed.title" = "Recording Failed";
"recording.state.failed.subtitle" = "The recording did not finish. Review the error and try again.";

"permission.screenRecording" = "Screen Recording";
"permission.microphone" = "Microphone";
"permission.status.ready" = "Ready";
"permission.status.missing" = "Missing";

"section.permissions" = "Permissions and Status";
"section.output" = "Latest Output";
"label.recordingState" = "Recording State";
"label.validation" = "Validation";
"label.diagnostics" = "Diagnostics";
"label.outputDirectory" = "Save Location";
"label.noOutput" = "No output yet";
"validation.notAvailable" = "Not generated";
"validation.passed" = "Passed";
"validation.failed" = "Failed";
"diagnostics.sessionJSON" = "session.json";

"quit.confirm.title" = "Recording in Progress";
"quit.confirm.message" = "Quitting will stop the current recording. Are you sure you want to quit?";
"quit.confirm.quit" = "Quit";
"quit.confirm.cancel" = "Keep Recording";
```

- [ ] **Step 2: Configure SwiftPM resources**

Modify `Package.swift` executable target:

```swift
        .executableTarget(
            name: "BabyRecorder",
            path: "Sources/BabyRecorder",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
```

- [ ] **Step 3: Copy localization resources into the packaged app**

Modify `Scripts/package_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/build"
APP_DIR="$BUILD_ROOT/BabyRecorder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c debug
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
if [ -d "$ROOT/Sources/BabyRecorder/Resources" ]; then
  cp -R "$ROOT/Sources/BabyRecorder/Resources/"* "$RESOURCES/"
fi
xattr -cr "$BUILD_ROOT"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
```

- [ ] **Step 4: Build and run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Package the app and verify localized resources are copied**

Run:

```bash
bash Scripts/package_app.sh
find build/BabyRecorder.app/Contents/Resources -maxdepth 2 -type f -name Localizable.strings -print
```

Expected output includes:

```text
build/BabyRecorder.app/Contents/Resources/en.lproj/Localizable.strings
build/BabyRecorder.app/Contents/Resources/zh-Hans.lproj/Localizable.strings
```

- [ ] **Step 6: Commit**

```bash
git add Package.swift Scripts/package_app.sh Sources/BabyRecorder/Resources
git commit -m "feat: add Chinese and English localization resources"
```

## Task 4: Refined Main Window UI

**Files:**
- Modify: `Sources/BabyRecorder/UI/ContentView.swift`

- [ ] **Step 1: Replace the minimal content view with the refined console UI**

Modify `Sources/BabyRecorder/UI/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel

    private var presentation: RecordingPresentation {
        viewModel.presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero

            HStack(alignment: .top, spacing: 16) {
                statusPanel
                outputPanel
            }

            if presentation.showsFailureMessage, let message = presentation.failureMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(Text("app.title"))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(presentation.titleKey))
                    .font(.title)
                    .fontWeight(.semibold)
                Text(LocalizedStringKey(presentation.subtitleKey))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            primaryActionButton
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch presentation.primaryAction {
        case .start:
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("recording.action.start", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartRecording)
            .accessibilityLabel(Text("recording.action.start"))
        case .stop:
            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("recording.action.stop", systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .accessibilityLabel(Text("recording.action.stop"))
        case .openSettings:
            Button {
                viewModel.openSystemSettings()
            } label: {
                Label("recording.action.openSettings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(Text("recording.action.openSettings"))
        case .none:
            ProgressView()
                .controlSize(.large)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.permissions")
                .font(.headline)

            ForEach(presentation.permissionRows, id: \.labelKey) { row in
                labeledRow(
                    title: LocalizedStringKey(row.labelKey),
                    value: LocalizedStringKey(row.statusKey),
                    status: row.status == .ready ? .success : .warning
                )
            }

            labeledRow(
                title: "label.recordingState",
                value: LocalizedStringKey(presentation.titleKey),
                status: statusTone
            )

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.checkPermissions() }
                } label: {
                    Label("recording.action.recheck", systemImage: "arrow.clockwise")
                }

                Button {
                    viewModel.openSystemSettings()
                } label: {
                    Label("menu.openSystemSettings", systemImage: "gear")
                }
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.output")
                .font(.headline)

            labeledRow(
                title: "label.outputDirectory",
                value: viewModel.outputDirectory?.lastPathComponent ?? String(localized: "label.noOutput"),
                status: viewModel.outputDirectory == nil ? .neutral : .success
            )

            labeledRow(
                title: "label.validation",
                value: validationText,
                status: validationTone
            )

            labeledRow(
                title: "label.diagnostics",
                value: "diagnostics.sessionJSON",
                status: viewModel.outputDirectory == nil ? .neutral : .success
            )

            Button {
                viewModel.revealOutputDirectory()
            } label: {
                Label("recording.action.showInFinder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRevealOutputDirectory)
        }
        .panelStyle()
    }

    private enum StatusTone {
        case neutral
        case success
        case warning
        case failure
    }

    private var statusTone: StatusTone {
        switch presentation.kind {
        case .ready, .finished:
            .success
        case .permissionsMissing, .finishedWithMixFailure:
            .warning
        case .failed:
            .failure
        case .checkingPermissions, .starting, .recording, .stopping:
            .neutral
        }
    }

    private var validationText: LocalizedStringKey {
        switch presentation.validationStatus {
        case .notAvailable:
            "validation.notAvailable"
        case .passed:
            "validation.passed"
        case .failed:
            "validation.failed"
        }
    }

    private var validationTone: StatusTone {
        switch presentation.validationStatus {
        case .notAvailable:
            .neutral
        case .passed:
            .success
        case .failed:
            .failure
        }
    }

    private func labeledRow(
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        status: StatusTone
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Label {
                Text(value)
            } icon: {
                Image(systemName: symbolName(for: status))
                    .foregroundStyle(color(for: status))
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    private func labeledRow(
        title: LocalizedStringKey,
        value: String,
        status: StatusTone
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Label {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: symbolName(for: status))
                    .foregroundStyle(color(for: status))
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    private func symbolName(for tone: StatusTone) -> String {
        switch tone {
        case .neutral:
            "circle"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.circle.fill"
        }
    }

    private func color(for tone: StatusTone) -> Color {
        switch tone {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Build to catch SwiftUI compile errors**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/BabyRecorder/UI/ContentView.swift
git commit -m "feat: polish main recording window"
```

## Task 5: Status Bar Menu and App Commands

**Files:**
- Create: `Sources/BabyRecorder/UI/StatusBarMenuView.swift`
- Modify: `Sources/BabyRecorder/BabyRecorderApp.swift`

- [ ] **Step 1: Create the shared status bar menu view**

Create `Sources/BabyRecorder/UI/StatusBarMenuView.swift`:

```swift
import SwiftUI

struct StatusBarMenuView: View {
    @ObservedObject var viewModel: RecordingViewModel
    let openMainWindow: () -> Void
    let quit: () -> Void

    private var presentation: RecordingPresentation {
        viewModel.presentation
    }

    var body: some View {
        Text(LocalizedStringKey(presentation.titleKey))

        Divider()

        switch presentation.primaryAction {
        case .start:
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                Label("recording.action.start", systemImage: "record.circle")
            }
            .disabled(!viewModel.canStartRecording)
        case .stop:
            Button {
                Task { await viewModel.stopRecording() }
            } label: {
                Label("recording.action.stop", systemImage: "stop.circle")
            }
        case .openSettings:
            Button {
                viewModel.openSystemSettings()
            } label: {
                Label("recording.action.openSettings", systemImage: "gear")
            }
        case .none:
            EmptyView()
        }

        Button {
            openMainWindow()
        } label: {
            Label("menu.openMainWindow", systemImage: "macwindow")
        }

        Button {
            viewModel.revealOutputDirectory()
        } label: {
            Label("menu.revealLatestOutput", systemImage: "folder")
        }
        .disabled(!viewModel.canRevealOutputDirectory)

        Button {
            Task { await viewModel.checkPermissions() }
        } label: {
            Label("menu.recheckPermissions", systemImage: "arrow.clockwise")
        }

        Button {
            viewModel.openSystemSettings()
        } label: {
            Label("menu.openSystemSettings", systemImage: "gear")
        }

        Divider()

        Button {
            quit()
        } label: {
            Label("menu.quit", systemImage: "power")
        }
    }
}
```

- [ ] **Step 2: Add status bar scene and commands to the app**

Modify `Sources/BabyRecorder/BabyRecorderApp.swift`:

```swift
import AppKit
import SwiftUI

@main
struct BabyRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var viewModel = RecordingViewModel(captureService: CaptureService())

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .background(WindowCloseHider())
                .task {
                    await viewModel.checkPermissions()
                }
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 460)
        .commands {
            CommandMenu("menu.recording") {
                Button("recording.action.start") {
                    Task { await viewModel.startRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!viewModel.canStartRecording)

                Button("recording.action.stop") {
                    Task { await viewModel.stopRecording() }
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(viewModel.state != .recording)

                Divider()

                Button("menu.recheckPermissions") {
                    Task { await viewModel.checkPermissions() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("menu.revealLatestOutput") {
                    viewModel.revealOutputDirectory()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!viewModel.canRevealOutputDirectory)
            }

            CommandGroup(after: .windowArrangement) {
                Button("menu.openMainWindow") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            StatusBarMenuView(
                viewModel: viewModel,
                openMainWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        } label: {
            Label("app.title", systemImage: statusBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var statusBarSymbolName: String {
        switch viewModel.state {
        case .recording:
            "record.circle.fill"
        case .permissionsMissing, .failed, .finishedWithMixFailure:
            "exclamationmark.circle"
        default:
            "waveform"
        }
    }
}
```

- [ ] **Step 3: Build to identify missing lifecycle types**

Run:

```bash
swift build
```

Expected: FAIL because `WindowCloseHider` and `AppLifecycleDelegate` do not exist yet. This verifies the app shell references the lifecycle work in the next task.

- [ ] **Step 4: Commit only if the build failure is exactly the missing lifecycle types**

Do not commit this task yet. Task 6 completes the build by adding lifecycle support, and both tasks should be committed together if intermediate broken commits are not desired.

## Task 6: Close-to-Hide and Quit Confirmation

**Files:**
- Create: `Sources/BabyRecorder/UI/WindowCloseHider.swift`
- Modify: `Sources/BabyRecorder/BabyRecorderApp.swift`

- [ ] **Step 1: Add close-to-hide window bridge**

Create `Sources/BabyRecorder/UI/WindowCloseHider.swift`:

```swift
import AppKit
import SwiftUI

struct WindowCloseHider: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            attachCoordinator(context.coordinator, to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            attachCoordinator(context.coordinator, to: nsView.window)
        }
    }

    private func attachCoordinator(_ coordinator: Coordinator, to window: NSWindow?) {
        guard let window else {
            return
        }
        window.delegate = coordinator
        window.minSize = NSSize(width: 640, height: 420)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }
}
```

- [ ] **Step 2: Add app lifecycle delegate for quit behavior**

Append this type to `Sources/BabyRecorder/BabyRecorderApp.swift`:

```swift
@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: RecordingViewModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel?.state == .recording else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "quit.confirm.title")
        alert.informativeText = String(localized: "quit.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "quit.confirm.quit"))
        alert.addButton(withTitle: String(localized: "quit.confirm.cancel"))

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
```

- [ ] **Step 3: Build app shell**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit status bar and lifecycle work**

```bash
git add Sources/BabyRecorder/BabyRecorderApp.swift Sources/BabyRecorder/UI/StatusBarMenuView.swift Sources/BabyRecorder/UI/WindowCloseHider.swift
git commit -m "feat: add status bar controls and close-to-hide window"
```

## Task 7: Full Verification and App Packaging

**Files:**
- Existing verification only unless a compile or packaging issue is found.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS with all test cases passing.

- [ ] **Step 2: Build the executable**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Package the app**

Run:

```bash
bash Scripts/package_app.sh
```

Expected: prints:

```text
/Users/yimingliu/Desktop/宝宝录音App/build/BabyRecorder.app
```

- [ ] **Step 4: Inspect packaged localization resources**

Run:

```bash
find build/BabyRecorder.app/Contents/Resources -maxdepth 2 -type f -name Localizable.strings -print
```

Expected output includes:

```text
build/BabyRecorder.app/Contents/Resources/en.lproj/Localizable.strings
build/BabyRecorder.app/Contents/Resources/zh-Hans.lproj/Localizable.strings
```

- [ ] **Step 5: Launch manually for visual verification**

Run:

```bash
open build/BabyRecorder.app
```

Expected manual checks:

- Main window title and UI are Chinese on a Chinese system.
- Status bar item appears.
- Red close button hides the window and leaves status bar item active.
- Status bar menu can reopen the main window.
- Start/stop controls are visible in both window and status bar menu.
- Reveal latest output is disabled before a recording creates output.

- [ ] **Step 6: Commit any verification fixes**

If Task 7 required code changes, commit them:

```bash
git add Package.swift Scripts Sources Tests
git commit -m "fix: complete ui status bar verification"
```

If Task 7 required no code changes, do not create an empty commit.

## Self-Review

- Spec coverage: Task 1 covers presentation mapping; Task 2 covers Finder reveal; Task 3 covers Chinese and English localization; Task 4 covers the refined single-window UI; Task 5 covers status bar and app commands; Task 6 covers close-to-hide and quit confirmation; Task 7 covers build, tests, packaging, and manual visual checks.
- Placeholder scan: no TODO, TBD, or "implement later" steps remain.
- Type consistency: `RecordingPresentation`, `FilePresenting`, `FinderFilePresenter`, `StatusBarMenuView`, `WindowCloseHider`, and `AppLifecycleDelegate` are introduced before later tasks rely on them.
