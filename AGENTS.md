# BabyRecorder Project Rules

These rules apply to the whole repository.

## Project Location

- Primary local workspace: `/Users/yimingliu/Desktop/宝宝录音App`
- GitHub repository: `git@github.com:SilencePaul/BabyRecorder.git`
- Active development branch: `codex/baby-recorder-mvp`
- GitHub `main` is updated by pushing `codex/baby-recorder-mvp:main`.

Do not assume another similarly named directory is the active workspace. If the shell starts elsewhere, change to `/Users/yimingliu/Desktop/宝宝录音App` before running project commands. In particular, `/Users/yimingliu/Documents/mac端录音&转文字` is obsolete and must not be used for this project.

## Product Context

BabyRecorder is a macOS SwiftUI app for Chinese users. It records microphone audio and system audio, stays available from the menu bar, and transcribes recordings locally with Qwen3-ASR + MLX on Apple Silicon.

The project started to help the user's girlfriend reliably record meetings/classes and turn them into text. Keep the product practical, low-friction, and friendly for non-developer installation.

## Development Flow

1. Inspect the existing code and follow current patterns before changing behavior.
2. Use TDD for behavior changes:
   - Add or update a focused failing test first.
   - Verify the failure is meaningful.
   - Implement the smallest change that passes.
   - Re-run targeted tests.
3. For macOS UI work, keep the app consistent with macOS conventions and the existing SwiftUI design.
4. Keep the app default language Chinese; maintain English localization when adding user-facing strings.
5. Do not revert unrelated changes. Assume unrecognized local edits may be user work.
6. Keep BlackHole out of the app path; the app should rely on macOS ScreenCaptureKit/system audio capture.
7. Keep transcription memory-friendly: no long-running ASR daemon unless explicitly requested. Load the model only when the user starts transcription.

## Documentation Must Stay Current

Every product, installation, packaging, or architecture change must update project descriptions in the same change set.

At minimum, check:

- `README.md`
- `AGENTS.md` when the development flow or project rules change
- `Scripts/make_distribution.sh`, if user installation steps change
- `docs/superpowers/specs` and `docs/superpowers/plans` for major feature designs/plans

When a new release DMG is generated, remind the user that `dist/BabyRecorder.dmg` is local and must be uploaded/replaced in GitHub Release manually.

## Verification Before Completion

Use the smallest verification set that proves the change, then broaden when risk is higher.

Common commands:

```bash
swift test
bash -n Scripts/install_distribution.sh Scripts/install_baby_recorder_runtime.sh Scripts/transcribe_mlx_qwen3_asr.sh Sources/BabyRecorder/Resources/Scripts/transcribe_mlx_qwen3_asr.sh Sources/BabyRecorder/Resources/Scripts/setup_baby_recorder_runtime.sh Scripts/make_distribution.sh
Scripts/make_distribution.sh
```

For transcription changes, also test with a real recording directory when feasible:

```bash
RUNTIME="$HOME/Library/Application Support/BabyRecorder"
SESSION="$RUNTIME/Recordings/<session-id>"
QWEN3_ASR_MODE=mixed "$RUNTIME/Scripts/transcribe_mlx_qwen3_asr.sh" "$SESSION"
QWEN3_ASR_MODE=dialogue "$RUNTIME/Scripts/transcribe_mlx_qwen3_asr.sh" "$SESSION"
```

## Packaging And Release

- Build the distributable with `Scripts/make_distribution.sh`.
- The generated DMG is `dist/BabyRecorder.dmg`.
- `dist/` is intentionally not committed.
- Source pushes do not update GitHub Release assets. The release DMG must be uploaded manually after packaging.

## Git Flow

After verified changes:

```bash
git add <changed files>
git commit -m "<type>: <summary>"
git push origin codex/baby-recorder-mvp:main
```

Use concise commit messages such as:

- `feat: add role dialogue transcription`
- `fix: normalize audio before qwen transcription`
- `docs: update project development rules`
