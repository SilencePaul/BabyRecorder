# Role Dialogue Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a stable role dialogue transcription mode that separately transcribes `mic.wav` and `system.wav`, then merges timestamped chunks into a time-ordered `我` / `对方` transcript.

**Architecture:** Keep existing mixed transcription unchanged. Extend the transcription request with a mode, teach the shell script to run either mixed or dialogue mode, and parse/merge chunk-level Qwen JSON in Python inside the script. Swift UI only selects the mode and displays the resulting dialogue text.

**Tech Stack:** SwiftUI, Swift tests, bash, Python stdlib JSON processing, existing `mlx-qwen3-asr`, existing bundled `ffmpeg`.

---

## File Structure

- Modify `Sources/BabyRecorder/Transcription/TranscriptionService.swift`: add transcription mode, missing track errors, and shell environment variable.
- Modify `Sources/BabyRecorder/UI/RecordingViewModel.swift`: store selected transcription mode and pass it to the service.
- Modify `Sources/BabyRecorder/UI/ContentView.swift`: add mode picker in the transcription panel.
- Modify `Sources/BabyRecorder/UI/StatusBarMenuView.swift`: keep status-bar transcription using the selected/default mode.
- Modify `Sources/BabyRecorder/Resources/Scripts/transcribe_mlx_qwen3_asr.sh`: implement mixed/dialogue modes.
- Modify `Scripts/transcribe_mlx_qwen3_asr.sh`: mirror the app resource script.
- Modify localized strings in `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings` and `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`.
- Modify `Tests/BabyRecorderTests/TranscriptionServiceTests.swift`: request validation and command construction tests.
- Modify `Tests/BabyRecorderTests/RecordingViewModelTests.swift`: selected mode propagation tests.
- Modify `Tests/BabyRecorderTests/DistributionScriptTests.swift`: script behavior assertions.

## Task 1: Add Transcription Mode To Swift Request

- [ ] Write failing tests in `Tests/BabyRecorderTests/TranscriptionServiceTests.swift`:

```swift
func testPythonMLXServiceRunsDialogueModeWithSelectedModel() async throws {
    let fixture = try TemporaryTranscriptionFixture()
    try "mic".write(to: fixture.sessionDirectory.appendingPathComponent("mic.wav"), atomically: true, encoding: .utf8)
    try "system".write(to: fixture.sessionDirectory.appendingPathComponent("system.wav"), atomically: true, encoding: .utf8)
    try "对话稿\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.txt"), atomically: true, encoding: .utf8)
    try "{}\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.json"), atomically: true, encoding: .utf8)
    let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
    let service = PythonMLXTranscriptionService(runtimeRoot: fixture.runtimeRoot, scriptURL: fixture.scriptURL, processRunner: runner)

    let result = try await service.transcribe(
        TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .fast, mode: .dialogue)
    )

    XCTAssertEqual(result.text, "对话稿")
    XCTAssertEqual(result.transcriptURL, fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.txt"))
    XCTAssertTrue(runner.runs[0].arguments[1].contains("QWEN3_ASR_MODE='dialogue'"))
}
```

- [ ] Run: `swift test --filter TranscriptionServiceTests/testPythonMLXServiceRunsDialogueModeWithSelectedModel`
  Expected: compile failure because `TranscriptionMode.dialogue` and request `mode` do not exist.

- [ ] Implement:
  - Add `enum TranscriptionMode: String, Equatable, Sendable { case mixed, dialogue }`.
  - Add `var mode: TranscriptionMode = .mixed` to `TranscriptionRequest`.
  - In mixed mode validate `mixed.wav`; in dialogue mode validate `mic.wav` and `system.wav`.
  - Choose output files:
    - mixed: `transcript.txt` / `transcript.json`
    - dialogue: `transcript_dialogue.txt` / `transcript_dialogue.json`
  - Add `QWEN3_ASR_MODE='<rawValue>'` to `shellCommand`.

- [ ] Run: `swift test --filter TranscriptionServiceTests`
  Expected: all transcription service tests pass.

## Task 2: Propagate Mode Through View Model And UI

- [ ] Write failing test in `Tests/BabyRecorderTests/RecordingViewModelTests.swift`:

```swift
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
        stopResult: RecordingCompletion(outputDirectory: outputDirectory, validation: Self.validation(passed: true), mixFailed: false)
    )
    let viewModel = await RecordingViewModel(
        permissionService: FakePermissionService(screen: true, mic: true),
        captureService: captureService,
        transcriptionService: transcriptionService
    )
    await viewModel.checkPermissions()
    await viewModel.startRecording()
    await viewModel.stopRecording()
    await MainActor.run { viewModel.selectedTranscriptionMode = .dialogue }

    await viewModel.transcribeLatestRecording()

    XCTAssertEqual(transcriptionService.requests.map(\\.mode), [.dialogue])
}
```

- [ ] Run: `swift test --filter RecordingViewModelTests/testDialogueTranscriptionModeIsPassedToService`
  Expected: compile failure because `selectedTranscriptionMode` does not exist.

- [ ] Implement:
  - Add `@Published var selectedTranscriptionMode: TranscriptionMode = .mixed`.
  - Pass `selectedTranscriptionMode` into `TranscriptionRequest`.
  - Add localized labels:
    - `transcription.mode.mixed` = `完整转写`
    - `transcription.mode.dialogue` = `分角色对话`
    - English equivalents.
  - Add a compact picker in `ContentView.transcriptionPanel` beside the model picker.

- [ ] Run: `swift test --filter RecordingViewModelTests`
  Expected: all view model tests pass.

## Task 3: Implement Dialogue Mode In Script

- [ ] Write failing assertions in `Tests/BabyRecorderTests/DistributionScriptTests.swift` checking the app resource script contains:

```swift
XCTAssertTrue(text.contains("QWEN3_ASR_MODE"))
XCTAssertTrue(text.contains("transcribe_track"))
XCTAssertTrue(text.contains("mic_asr.json"))
XCTAssertTrue(text.contains("system_asr.json"))
XCTAssertTrue(text.contains("transcript_dialogue.txt"))
XCTAssertTrue(text.contains("speaker\": speaker"))
```

- [ ] Run: `swift test --filter DistributionScriptTests/testTranscriptionScriptUsesBundledRuntimeFfmpegFirst`
  Expected: failure because dialogue mode script logic does not exist.

- [ ] Implement in both script copies:
  - Add `MODE="${QWEN3_ASR_MODE:-mixed}"`.
  - Keep current mixed mode behavior.
  - Add `transcribe_track input_wav asr_wav raw_json` function that runs ffmpeg normalization and `mlx-qwen3-asr`.
  - Dialogue mode runs:
    - `mic.wav` → `mic_asr_input.wav` → `mic_asr.json`
    - `system.wav` → `system_asr_input.wav` → `system_asr.json`
  - Add Python merge step:
    - Read both raw JSON files.
    - Extract `chunks`.
    - Drop empty text chunks.
    - Add `speaker: "我"` for mic and `speaker: "对方"` for system.
    - Sort by `start`, then `speaker`.
    - Write `transcript_dialogue.json`.
    - Write formatted `transcript_dialogue.txt`.
    - Write `transcript_me.txt` and `transcript_other.txt`.

- [ ] Run: `bash -n Scripts/transcribe_mlx_qwen3_asr.sh Sources/BabyRecorder/Resources/Scripts/transcribe_mlx_qwen3_asr.sh`
  Expected: no output, exit 0.

- [ ] Run: `swift test --filter DistributionScriptTests`
  Expected: all distribution script tests pass.

## Task 4: Verify End To End Locally

- [ ] Run full test suite:

```bash
swift test
```

Expected: 0 failures.

- [ ] Run a local dialogue transcription against a recording directory with both tracks:

```bash
RUNTIME="$HOME/Library/Application Support/BabyRecorder"
SESSION="$RUNTIME/Recordings/<session-id>"
QWEN3_ASR_MODE=dialogue "$RUNTIME/Scripts/transcribe_mlx_qwen3_asr.sh" "$SESSION"
```

Expected output files:

- `transcript_me.txt`
- `transcript_other.txt`
- `transcript_dialogue.txt`
- `transcript_dialogue.json`

- [ ] Inspect `transcript_dialogue.txt` and confirm it alternates by timestamps using `我` and `对方` labels.

## Task 5: Package And Push

- [ ] Run:

```bash
Scripts/make_distribution.sh
```

Expected: `dist/BabyRecorder-Install.zip` is regenerated.

- [ ] Inspect the zip script:

```bash
ditto -x -k dist/BabyRecorder-Install.zip /private/tmp/BabyRecorderDialogueZipCheck
rg -n "QWEN3_ASR_MODE|transcript_dialogue" /private/tmp/BabyRecorderDialogueZipCheck/BabyRecorder-Install/BabyRecorder.app/Contents/Resources/Scripts/transcribe_mlx_qwen3_asr.sh
```

Expected: dialogue mode markers are present.

- [ ] Commit:

```bash
git add Sources/BabyRecorder Tests Scripts docs/superpowers
git commit -m "feat: add role dialogue transcription"
git push origin codex/baby-recorder-mvp:main
```

Expected: push succeeds.
