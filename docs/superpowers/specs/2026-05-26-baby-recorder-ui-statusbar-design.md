# Baby Recorder UI and Status Bar Design

## Goal

Polish the existing Baby Recorder MVP into a native-feeling macOS utility for Chinese users while preserving the proven recording pipeline.

The app should feel simple and trustworthy: users can see whether recording is ready, start or stop with one clear action, close the window without stopping the app, and control recording from the macOS menu bar.

## Target Workspace

`/Users/yimingliu/Desktop/宝宝录音App`

## Product Direction

Use the approved "refined single-window console" direction:

- Keep one focused main window rather than adding a sidebar or history browser.
- Default the interface to Simplified Chinese.
- Support English through localization fallback or system language selection.
- Add a persistent macOS status bar item for quick control.
- Treat the red window close button as "hide window", not "quit app".

## In Scope

- Refresh `ContentView` visual hierarchy and spacing.
- Add Chinese and English localizations for all user-facing UI text.
- Add status bar control with current state and common actions.
- Add app/window lifecycle behavior so closing the main window hides it.
- Add menu commands for start/stop recording, re-check permissions, open main window, and reveal latest output.
- Keep the current `RecordingViewModel`, `CaptureService`, audio, mixer, and diagnostics boundaries.
- Add focused tests for non-visual state presentation and any new view-model-facing behavior.

## Out of Scope

- Rewriting the ScreenCaptureKit capture pipeline.
- Adding recording history browsing.
- Adding realtime waveform or level meters.
- Adding transcription UI.
- Adding a full settings screen.
- Adding a sidebar or multi-page workspace.
- Changing output file structure or diagnostics JSON schema unless required by UI actions.

## Main Window Design

The window title should be localized:

- Chinese: `宝宝录音`
- English: `Baby Recorder`

The main area should have three zones:

1. Hero/status area:
   - Large localized state title such as `准备录制`, `正在录制`, `录制完成`, `权限不足`, or `录制失败`.
   - A short secondary sentence describing what the user can do next.
   - One primary action button:
     - Ready/finished state: start recording.
     - Recording state: stop recording.
     - Missing permissions state: open System Settings or re-check permissions as secondary actions.

2. Permission/status group:
   - Screen recording permission.
   - Microphone permission.
   - Current recording state.
   - Use semantic system colors and SF Symbols where useful.

3. Output/result group:
   - Latest output directory, if available.
   - Validation result, if available.
   - Button to reveal the output directory in Finder.
   - Show diagnostics presence with concise text such as `session.json`.

Use system fonts, semantic colors, system accent color, 8 pt spacing rhythm, and compact Mac control sizes. Avoid hardcoded light-only colors so Dark Mode and accessibility contrast remain reasonable.

## Status Bar Design

The app should create a status bar item at launch.

The status bar menu should contain:

- Current localized status.
- Start Recording or Stop Recording, depending on state.
- Open Main Window.
- Reveal Latest Output in Finder, disabled when no output exists.
- Re-check Permissions.
- Open System Settings.
- Quit.

The status bar item should reflect state:

- Idle/ready: neutral icon.
- Recording: visible recording indicator.
- Missing permission or failed: warning text in the menu status row, with an exclamation-style icon if the chosen status bar API supports it cleanly.

Both the status bar menu and the main window must use the same `RecordingViewModel` instance so state cannot diverge.

## Window Lifecycle

Clicking the red close button should hide the main window and leave the app running in the status bar.

Users can restore the window through:

- Status bar menu: `打开主窗口` / `Open Main Window`.
- Window menu command: `打开主窗口` / `Open Main Window`.

Quitting the app should remain explicit. If the user tries to quit while recording, the app should require confirmation before stopping or exiting.

## Localization

Chinese is the primary language. English is supported as the secondary language.

Implementation should centralize user-facing strings in localization resources. Internal diagnostics keys, file names, enum cases, and code symbols should stay English.

Initial localized text should cover:

- App title.
- Recording state titles and subtitles.
- Permission labels and values.
- Primary and secondary action labels.
- Status bar menu items.
- Output and validation labels.
- Error/failure display labels.
- Quit confirmation text.

## Architecture

The current architecture is healthy and should be preserved:

- `RecordingViewModel` owns recording state and user actions.
- `CaptureService` owns ScreenCaptureKit lifecycle.
- `AudioTrackWriter`, `Mixer`, and `SessionDiagnostics` remain separate service layers.
- The UI should not reach into capture internals.

Small additions are expected:

- A presentation helper for localized state titles, subtitles, and button availability.
- A Finder reveal action, either in the view model or a small injected service.
- A status bar scene/view that observes the shared `RecordingViewModel`.
- A window visibility coordinator only if SwiftUI scene APIs are insufficient.

The implementation should avoid duplicating start/stop logic between the main window and status bar. Both surfaces should call the same view-model methods.

## Error Handling

The UI should keep errors actionable and non-modal by default:

- Permission missing: show which permission is missing and offer System Settings plus re-check.
- Capture failure: show a concise localized failure title and the underlying error message.
- Mix failure: mark recording as completed with a mix warning, preserving access to original track outputs.
- Validation failure: show failed validation in the output group.

Use modal confirmation only when quitting during active recording.

## macOS HIG Checks

- Main window remains resizable with sensible minimum size.
- Traffic-light buttons remain native and visible.
- Status bar behavior is explicit and discoverable through the menu.
- Start/stop recording, re-check permissions, open main window, and reveal latest output should be available through buttons and through menu/status bar commands.
- Icon-only controls need accessibility labels.
- Use semantic colors throughout custom UI surfaces; use system materials for window or menu-adjacent backgrounds when the API provides them without custom window chrome.
- Closing the window should not destroy recording state.

## Testing Strategy

Add focused tests where behavior is not purely visual:

- View-model/presentation mapping returns the correct localized state category for ready, recording, missing permission, finished, mix failure, and failed states.
- Finder reveal action is disabled or unavailable when no output directory exists.
- Shared start/stop actions remain routed through `RecordingViewModel`.
- Existing recording state tests continue to pass.

Visual details should be verified by running the app and inspecting the main window and status bar in both idle and recording-capable states. If full app launch cannot be automated in the current environment, record the exact verification commands attempted and any manual verification still needed.
