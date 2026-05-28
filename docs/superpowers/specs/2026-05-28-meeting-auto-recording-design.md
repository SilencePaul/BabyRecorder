# Meeting Auto Recording Design

## Goal

BabyRecorder should automatically start recording when it detects that a supported meeting app is actually in a meeting, then prompt the user to stop when the meeting appears to have ended.

The first version should be conservative. It is better to miss some meetings than to start recording during ordinary chat, file browsing, or video playback.

## Supported Apps

The first implementation targets these meeting clients:

- Tencent Meeting: `com.tencent.meeting`
- Feishu/Lark: `com.electron.lark`
- DingTalk: `com.alibaba.dingtalkmac`, plus a small allowlist that can be expanded after observing installed app metadata

Detection is based on running applications and their visible window metadata. The app should not depend on BlackHole, private meeting SDKs, or audio-level inference.

## User Experience

Automatic meeting detection is enabled while BabyRecorder is running and the transcription runtime setup view has finished.

When a supported meeting app enters a detected in-meeting state:

1. If recording permissions are ready and BabyRecorder is idle, BabyRecorder starts recording automatically.
2. If permissions are missing, BabyRecorder does not start recording and shows that automatic recording is blocked by missing permissions.
3. If BabyRecorder is already recording, it does not start another session.

When a meeting that triggered automatic recording is no longer detected, BabyRecorder should not stop automatically. It should show a clear confirmation prompt in the app UI and status bar menu:

> 会议可能已结束，是否停止录制？

The user must explicitly stop recording. This avoids cutting off a class or meeting during a temporary detection failure.

## Detection Model

Create a `MeetingDetection` area with small, testable types:

- `MeetingApp`: known app identity, localized display name, bundle ID candidates, and meeting keyword candidates.
- `RunningApplicationSnapshot`: bundle ID, localized name, and visible window titles or metadata discovered for that app.
- `MeetingDetectionSnapshot`: current high-level result, including whether a supported app is in a detected meeting and which app triggered it.
- `MeetingApplicationProviding`: protocol that returns snapshots for currently running applications.
- `MeetingDetector`: pure evaluator that maps running app snapshots to a detection snapshot.

The detector should require two signals:

1. A supported app bundle ID is running.
2. At least one window title or metadata string for that app matches conservative meeting keywords.

Example keywords may include Chinese and English meeting terms such as `会议`, `腾讯会议`, `飞书会议`, `DingTalk Meeting`, `Meeting`, `共享屏幕`, and similar client-specific strings. The implementation should avoid generic terms that commonly appear outside meetings unless combined with a supported app identity.

## macOS Integration

The provider can use public macOS APIs:

- `NSWorkspace.shared.runningApplications` for running app bundle IDs and names.
- Accessibility APIs or window-list APIs for visible window titles.

If macOS does not allow BabyRecorder to read window titles, detection should degrade safely:

- Do not auto-start from app-running alone.
- Report a state that the UI can present as "需要辅助功能权限才能自动识别会议".
- Keep manual recording fully available.

The design intentionally avoids attempting to bypass macOS privacy controls.

## Auto Recording Controller

Create a small controller named `MeetingAutoRecorder` that owns detection polling and calls the existing `RecordingViewModel` actions.

Responsibilities:

- Poll the detector on a modest interval while the main recording UI is active.
- Start recording only when the detection state transitions from not-in-meeting to in-meeting and `RecordingViewModel.canStartRecording` is true.
- Remember that the current recording was auto-started by meeting detection.
- After an auto-started meeting is no longer detected for several consecutive polls, enter a "stop suggested" state instead of stopping.
- Clear the stop suggestion when the user stops recording, starts a new recording, or the meeting is detected again.

The controller should not know how to capture audio. It should reuse `RecordingViewModel.startRecording()` and `RecordingViewModel.stopRecording()` so manual and automatic recording share one state machine.

## UI Surface

Add a small automatic recording status to the existing window and status bar menu.

Recommended copy:

- `自动检测会议：开启`
- `检测到%@，已自动开始录制`
- `需要辅助功能权限才能自动识别会议`
- `会议可能已结束，是否停止录制？`

The first version should not add a full settings page. A persistent on/off setting can be added later if automatic detection feels too noisy in real use.

## Error Handling

- If runtime setup is still checking or installing, do not start detection.
- If permissions are missing, do not auto-start; surface the existing permission recovery path.
- If the detector cannot read window titles because of macOS privacy restrictions, show a helpful status and continue allowing manual recording.
- If automatic start fails, keep the failure in the normal recording failure UI.
- Never auto-stop recording without user confirmation.

## Testing

Use TDD and keep detection logic independent from real installed apps.

Focused tests should cover:

- Supported app running without a meeting-like window does not auto-start.
- Supported app running with a meeting-like window does auto-start.
- Unsupported apps with meeting-like titles do not auto-start.
- Existing recording state prevents duplicate auto-start.
- Missing recording permissions prevent auto-start.
- Meeting disappearance after auto-start sets a stop suggestion but does not stop recording.
- Inability to read window titles reports a blocked or unavailable detection state.

Manual verification should include launching BabyRecorder alongside Tencent Meeting and Feishu/Lark. DingTalk detection should be verified when an installed DingTalk bundle ID is available.

## Out Of Scope

- Automatically stopping a recording without confirmation.
- Audio-level inference of meeting state.
- Speaker diarization or transcript changes.
- A settings window for managing app allowlists.
- Support for browser-based meetings.
