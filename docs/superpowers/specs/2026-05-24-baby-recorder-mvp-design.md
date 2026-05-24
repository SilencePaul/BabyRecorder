# Baby Recorder MVP Design

## Goal

Build a small native macOS app that reliably proves we can capture both system audio and microphone audio on macOS Tahoe 26.4.1 and 26.5 without BlackHole, Aggregate Device, or Multi-Output Device routing.

The MVP prioritizes diagnostic clarity over features. It should make it obvious whether a failure happened in system audio capture, microphone capture, WAV writing, mixing, permissions, or validation.

## Target Workspace

`/Users/yimingliu/Desktop/宝宝录音App`

## Supported Systems

- Primary test machine: macOS Tahoe 26.5
- Girlfriend's machine: macOS Tahoe 26.4.1
- Minimum supported system for the MVP: macOS Tahoe 26.4.1+

Older macOS versions are out of scope for this MVP.

## In Scope

- A normal macOS window app.
- Startup permission readiness flow for Screen Recording and Microphone.
- A minimal UI with:
  - Permission status.
  - Re-check permissions action.
  - Open System Settings action.
  - Start Recording action.
  - Stop Recording action.
  - Current state.
  - Most recent output directory.
  - Final validation result.
- ScreenCaptureKit as the single realtime capture pipeline.
- Capture from the main display.
- System audio capture from ScreenCaptureKit `.audio`.
- Default microphone capture from ScreenCaptureKit `.microphone`.
- One timestamped output directory per recording session.
- Output files:
  - `system.wav`
  - `mic.wav`
  - `mixed.wav`
  - `session.json`
- Lightweight validation after stopping.

## Out of Scope

- Speech-to-text.
- BlackHole.
- Aggregate Device.
- Multi-Output Device.
- AVAudioEngine in the primary implementation.
- Microphone device selection.
- Menu bar app behavior.
- Realtime waveform display.
- Realtime level meters.
- Advanced loudness normalization.
- Backward compatibility with older macOS releases.

## Primary Architecture

The MVP uses one ScreenCaptureKit stream for both system audio and microphone audio.

`SCStreamConfiguration` should enable:

- `capturesAudio = true`
- `captureMicrophone = true`
- default microphone input by leaving `microphoneCaptureDeviceID` unset
- `sampleRate = 48000`
- `channelCount = 2`
- `excludesCurrentProcessAudio = true`

The app adds separate stream outputs for:

- `.audio`, routed to the system track writer
- `.microphone`, routed to the microphone track writer

This is preferred over combining ScreenCaptureKit with AVAudioEngine because both captured tracks come from the same framework and timing model.

## Fallback Architecture

If ScreenCaptureKit `.microphone` is unavailable, empty, or unstable on the target Tahoe machines, the fallback design is:

- ScreenCaptureKit `.audio` for system audio.
- AVAudioEngine or AVFoundation for microphone audio.

That fallback is explicitly not part of the initial MVP implementation. It should only be used after `session.json` proves that ScreenCaptureKit microphone capture is the failing layer.

## Components

### RecordingViewModel

Owns UI state and user actions.

Expected states:

- `checkingPermissions`
- `permissionsMissing`
- `ready`
- `starting`
- `recording`
- `stopping`
- `finished`
- `finishedWithMixFailure`
- `failed`

Responsibilities:

- Check and expose permission readiness.
- Enable Start Recording only when permissions are ready.
- Start and stop recording through `CaptureService`.
- Display output directory and validation result.
- Surface specific failure messages.

### CaptureService

Owns ScreenCaptureKit lifecycle.

Responsibilities:

- Fetch `SCShareableContent`.
- Select the main display.
- Create an `SCContentFilter`.
- Build `SCStreamConfiguration`.
- Create and start `SCStream`.
- Register `.audio` and `.microphone` outputs.
- Stop the stream.
- Forward sample buffers to the correct audio writer.
- Report lifecycle errors with specific error codes.

### AudioTrackWriter

Writes one audio track to one WAV file.

MVP instances:

- system writer for `system.wav`
- microphone writer for `mic.wav`

Responsibilities:

- Accept `CMSampleBuffer` audio buffers.
- Validate that each buffer contains audio data.
- Read presentation timestamps.
- Convert to the app's canonical PCM format.
- Write WAV data.
- Track buffer count.
- Track frame count.
- Track byte count.
- Track first and last presentation timestamps.
- Record per-track write errors.

### Mixer

Creates `mixed.wav` after recording stops.

Responsibilities:

- Read `system.wav` and `mic.wav`.
- Convert both inputs to the same PCM format if needed.
- Align tracks using captured timing metadata.
- Mix by linear summing with clipping protection.
- Write `mixed.wav`.
- Report mix failure without destroying or hiding the original track outputs.

The MVP mixer runs offline after capture. It must not run inside the realtime ScreenCaptureKit callback path.

### SessionDiagnostics

Owns diagnostic data and validation.

Responsibilities:

- Record session metadata.
- Record permission state at recording start.
- Record capture configuration.
- Record per-track statistics.
- Record errors.
- Write `session.json`.
- Validate output files and buffer counts.

## Permission Flow

The app should prepare permissions before recording starts.

On app/window startup:

1. Enter `checkingPermissions`.
2. Check Screen Recording permission readiness.
3. Check Microphone permission readiness.
4. If both are ready, enter `ready` and enable Start Recording.
5. If either is missing, enter `permissionsMissing` and disable Start Recording.

The UI should provide:

- Re-check permissions.
- Open System Settings.

When the user clicks Start Recording:

- If permissions are ready, start recording.
- If permissions are missing, do not start recording and show the missing permission names.

The recording start path should not be blocked by first-time permission prompts.

## Recording Data Flow

When recording starts:

1. Create a timestamped session directory:

   `Recordings/YYYY-MM-DD_HH-mm-ss/`

2. Prepare output paths:

   - `system.wav`
   - `mic.wav`
   - `mixed.wav`
   - `session.json`

3. Create system and microphone `AudioTrackWriter` instances.

4. Fetch shareable content and select the main display.

5. Create the ScreenCaptureKit stream and outputs.

6. Start capture.

7. For each `.audio` sample buffer:

   - Validate buffer.
   - Extract presentation timestamp.
   - Convert to canonical PCM.
   - Write to `system.wav`.
   - Update system track diagnostics.

8. For each `.microphone` sample buffer:

   - Validate buffer.
   - Extract presentation timestamp.
   - Convert to canonical PCM.
   - Write to `mic.wav`.
   - Update microphone track diagnostics.

When recording stops:

1. Stop `SCStream`.
2. Close the system and microphone writers.
3. Generate `mixed.wav` offline from `system.wav` and `mic.wav`.
4. Write `session.json`.
5. Run lightweight validation.
6. Update UI with success or specific failure.

## Output Layout

All recordings are saved under the app workspace:

`/Users/yimingliu/Desktop/宝宝录音App/Recordings/`

Each recording creates one timestamped directory:

```text
Recordings/
  2026-05-24_13-45-10/
    system.wav
    mic.wav
    mixed.wav
    session.json
```

## Diagnostic JSON

`session.json` should follow this shape:

```json
{
  "sessionId": "2026-05-24_13-45-10",
  "app": {
    "name": "BabyRecorder",
    "version": "0.1.0"
  },
  "system": {
    "macOS": "Tahoe 26.5",
    "machine": "Mac"
  },
  "permissions": {
    "screenRecording": "granted",
    "microphone": "granted",
    "checkedAt": "2026-05-24T13:45:00+08:00"
  },
  "recording": {
    "startedAt": "2026-05-24T13:45:10+08:00",
    "endedAt": "2026-05-24T13:45:22+08:00",
    "durationSeconds": 12.34,
    "outputDirectory": "/Users/yimingliu/Desktop/宝宝录音App/Recordings/2026-05-24_13-45-10"
  },
  "configuration": {
    "captureSource": "mainDisplay",
    "systemAudio": "ScreenCaptureKit.audio",
    "microphone": "ScreenCaptureKit.microphone.defaultInput",
    "sampleRate": 48000,
    "channelCount": 2,
    "excludesCurrentProcessAudio": true
  },
  "tracks": {
    "system": {
      "path": "system.wav",
      "bufferCount": 120,
      "framesWritten": 576000,
      "bytesWritten": 2304000,
      "firstPTS": 0.123,
      "lastPTS": 12.123
    },
    "microphone": {
      "path": "mic.wav",
      "bufferCount": 121,
      "framesWritten": 580800,
      "bytesWritten": 2323200,
      "firstPTS": 0.120,
      "lastPTS": 12.125
    },
    "mixed": {
      "path": "mixed.wav",
      "bytesWritten": 2304000
    }
  },
  "validation": {
    "passed": true,
    "checks": {
      "systemFileNonEmpty": true,
      "micFileNonEmpty": true,
      "mixedFileNonEmpty": true,
      "systemBuffersPresent": true,
      "micBuffersPresent": true
    }
  },
  "errors": []
}
```

The implementation may add fields, but it should not remove these core fields without updating this spec.

## Error Codes

The app should record specific error codes where possible:

- `screenRecordingPermissionMissing`
- `microphonePermissionMissing`
- `shareableContentFailed`
- `mainDisplayUnavailable`
- `streamCreateFailed`
- `streamStartFailed`
- `streamStopFailed`
- `systemAudioNoBuffers`
- `microphoneNoBuffers`
- `systemWavWriteFailed`
- `microphoneWavWriteFailed`
- `mixedWavWriteFailed`
- `validationFailed`

Errors should include enough context to identify the affected file, track, or API call.

## Validation

After stopping, validation passes only when:

- `system.wav` exists and is non-empty.
- `mic.wav` exists and is non-empty.
- `mixed.wav` exists and is non-empty.
- system buffer count is greater than 0.
- microphone buffer count is greater than 0.

If validation fails, the UI should say which check failed.

## Testing Strategy

### Unit Tests

`SessionDiagnostics`:

- Produces valid JSON with required fields.
- Records permission state.
- Records track stats.
- Records errors.
- Computes validation pass/fail correctly.

`Mixer`:

- Mixes two short PCM inputs into a non-empty output.
- Prevents PCM clipping overflow.
- Reports failure when an input file is missing.

`AudioTrackWriter` pure logic:

- Increments buffer count.
- Tracks first and last presentation timestamps.
- Tracks frames and bytes written.
- Records write errors.

`RecordingViewModel`:

- Disables Start Recording when permissions are missing.
- Enables Start Recording when permissions are ready.
- Moves through starting, recording, stopping, and finished states.
- Surfaces validation failures.

### Real Recording Test

Run on both target machines:

1. Launch the app.
2. Confirm the app shows permission status before recording.
3. Grant Screen Recording and Microphone permissions if needed.
4. Use Re-check Permissions until the app enters `ready`.
5. Play system audio.
6. Speak into the microphone.
7. Record for 10 to 20 seconds.
8. Stop recording.
9. Confirm the app shows the output directory and validation result.
10. Confirm the output directory contains:

    - `system.wav`
    - `mic.wav`
    - `mixed.wav`
    - `session.json`

11. Confirm `session.json` reports:

    - system buffer count > 0
    - microphone buffer count > 0
    - validation passed = true

12. Listen to the outputs:

    - `system.wav` should primarily contain computer playback.
    - `mic.wav` should primarily contain microphone speech.
    - `mixed.wav` should contain both.

Failure is acceptable during MVP testing only if the failure is clearly localized by the UI and `session.json`.

## Key Product Principle

The MVP is successful when it gives us trustworthy evidence about both capture paths. A broken recording with precise diagnostics is more useful than a vague success message.
