# Python MLX Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-demand local speech-to-text to BabyRecorder using the already verified Python MLX Qwen3-ASR bridge.

**Architecture:** Keep the Swift app independent from the engine implementation by adding a `TranscriptionServicing` protocol and a `PythonMLXTranscriptionService` implementation. The ViewModel owns user-facing transcription state while the process-based engine starts only when the user clicks transcribe and exits when the job finishes.

**Tech Stack:** SwiftUI, Swift concurrency, `Process`, Python `.venv-asr`, `mlx-qwen3-asr`, Qwen3-ASR-0.6B default with 1.7B override support.

---

### Task 1: Domain Model And Engine Boundary

**Files:**
- Create: `Sources/BabyRecorder/Transcription/TranscriptionService.swift`
- Test: `Tests/BabyRecorderTests/RecordingViewModelTests.swift`

- [ ] Add `TranscriptionModel`, `TranscriptionStatus`, `TranscriptionResult`, and `TranscriptionServicing`.
- [ ] Add fake transcription service tests covering completed, failed, and duplicate-start behavior.
- [ ] Run `swift test --filter RecordingViewModelTests` and confirm the new tests fail before implementation.

### Task 2: Python MLX Process Runner

**Files:**
- Modify: `Sources/BabyRecorder/Transcription/TranscriptionService.swift`
- Test: `Tests/BabyRecorderTests/TranscriptionServiceTests.swift`

- [ ] Implement a process-backed service that calls `Scripts/transcribe_mlx_qwen3_asr.sh <session-dir>`.
- [ ] Read `transcript.txt` and `transcript.json` after the process exits.
- [ ] Report missing `mixed.wav`, missing `.venv-asr`, non-zero process exit, and missing transcript files as localized errors.
- [ ] Add tests for command construction and result-file parsing using a temporary fake script.

### Task 3: ViewModel And UI Integration

**Files:**
- Modify: `Sources/BabyRecorder/UI/RecordingViewModel.swift`
- Modify: `Sources/BabyRecorder/UI/RecordingPresentation.swift`
- Modify: `Sources/BabyRecorder/UI/ContentView.swift`
- Modify: `Sources/BabyRecorder/UI/StatusBarMenuView.swift`
- Modify: `Sources/BabyRecorder/BabyRecorderApp.swift`

- [ ] Inject the transcription service into the app ViewModel.
- [ ] Expose `canTranscribe`, `transcriptionStatus`, `transcriptionText`, and `transcribeLatestRecording()`.
- [ ] Add a "Start Transcription" button in the output panel after a recording exists.
- [ ] Add a "Transcribe Latest Recording" command in the menu bar and status bar.
- [ ] Show loading and elapsed guidance so users know the local model can take a few seconds.

### Task 4: Localization And Verification

**Files:**
- Modify: `Sources/BabyRecorder/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/BabyRecorder/Resources/en.lproj/Localizable.strings`
- Modify: `Scripts/transcribe_mlx_qwen3_asr.sh`

- [ ] Default the script to `Qwen/Qwen3-ASR-0.6B`.
- [ ] Add Chinese and English strings for transcription actions and states.
- [ ] Run `swift test`.
- [ ] Run `bash -n Scripts/transcribe_mlx_qwen3_asr.sh`.
- [ ] Build and install the app with `bash Scripts/install_app.sh`.
