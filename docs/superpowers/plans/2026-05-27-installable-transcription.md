# Installable Transcription Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make BabyRecorder usable on another Mac without depending on the developer project directory.

**Architecture:** Bundle the transcription shell script inside the app resources, and store mutable runtime assets in `~/Library/Application Support/BabyRecorder`: `.venv-asr`, Hugging Face cache, and logs. Provide an installer script that copies the app, creates the runtime directory, installs Python MLX dependencies through China-friendly mirrors, and warms the Qwen3-ASR-0.6B model cache.

**Tech Stack:** Swift, Swift Package Manager app resources, zsh installer script, Python 3.13 venv, uv/pip with Tsinghua PyPI mirror, Hugging Face endpoint/cache configuration.

---

### Task 1: Runtime Path Resolver

- [ ] Add a small resolver so `PythonMLXTranscriptionService()` defaults to Application Support instead of `/Users/yimingliu/Desktop/宝宝录音App`.
- [ ] Update tests to assert the default root is overrideable and script command targets the runtime root.

### Task 2: Bundle Transcription Script

- [ ] Move/copy `transcribe_mlx_qwen3_asr.sh` into Swift package resources.
- [ ] Update package/install scripts to include the script in `BabyRecorder.app/Contents/Resources/Scripts`.
- [ ] Make runtime service prefer the script copied into Application Support, and fall back to bundle resources when needed.

### Task 3: China-Friendly Installer

- [ ] Create `Scripts/install_baby_recorder_runtime.sh`.
- [ ] Copy `BabyRecorder.app` to `~/Applications`.
- [ ] Copy transcription script to `~/Library/Application Support/BabyRecorder/Scripts`.
- [ ] Create `~/Library/Application Support/BabyRecorder/.venv-asr`.
- [ ] Install `mlx-qwen3-asr` with `uv` or `pip` using `https://pypi.tuna.tsinghua.edu.cn/simple`.
- [ ] Set Hugging Face cache under Application Support and default `HF_ENDPOINT=https://hf-mirror.com`.
- [ ] Optionally warm the 0.6B model if network is available.

### Task 4: Verification

- [ ] Run targeted transcription service tests.
- [ ] Run full Swift tests.
- [ ] Run shell syntax checks for all scripts.
- [ ] Run installer in the local user account and verify app signature.
