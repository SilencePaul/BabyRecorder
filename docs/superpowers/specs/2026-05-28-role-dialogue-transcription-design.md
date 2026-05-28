# Role Dialogue Transcription Design

## Goal

Generate a time-ordered dialogue transcript that labels microphone audio as "我" and system audio as "对方", optimized for Tencent Meeting recordings where the local user speaks through the microphone and remote participants arrive through system audio.

## Scope

The first version does not perform multi-speaker diarization inside the system audio track. It treats all `system.wav` speech as "对方" and all `mic.wav` speech as "我".

## Approach

BabyRecorder already records three synchronized tracks in each session:

- `mic.wav`: local microphone, labeled `我`
- `system.wav`: app/system audio, labeled `对方`
- `mixed.wav`: mixed audio, kept for the existing full transcript path

The transcription runtime will support two modes:

- Mixed mode: current behavior, transcribes `mixed.wav` and writes `transcript.txt` / `transcript.json`.
- Dialogue mode: transcribes `mic.wav` and `system.wav` separately with timestamps, then merges chunks by start time.

Qwen3-ASR's JSON output already contains chunk-level `start` and `end` fields. The first implementation will merge chunk-level entries instead of word-level timestamps because it is stable, lightweight, and enough for readable meeting notes.

## Outputs

Dialogue mode writes:

- `transcript_me.txt`: local microphone text only.
- `transcript_other.txt`: system audio text only.
- `transcript_dialogue.txt`: time-ordered transcript with speaker labels.
- `transcript_dialogue.json`: structured merged entries.
- `mic_asr_input.wav` and `system_asr_input.wav`: normalized ASR input files.
- `mic_asr.json` and `system_asr.json`: raw Qwen JSON outputs.

Example dialogue text:

```text
[00:00:02] 我：我们开始测试一下。
[00:00:06] 对方：可以，我这边听得到。
```

## UI

Add a transcription mode picker next to the model picker:

- `完整转写`: existing mixed transcript.
- `分角色对话`: new dialogue transcript.

Default mode remains `完整转写` to preserve current behavior. Users can switch to `分角色对话` before clicking transcribe.

## Error Handling

Dialogue mode requires both `mic.wav` and `system.wav`. If either is missing, the service should fail before starting the process with a clear localized error. If one track produces no non-empty chunks, still write the other track's transcript and dialogue output.

## Future Extension

If meetings often include multiple remote participants, system audio can later run Qwen diarization or a separate diarization model to split `对方` into `对方 A`, `对方 B`, etc. That is intentionally out of scope for the first version.
