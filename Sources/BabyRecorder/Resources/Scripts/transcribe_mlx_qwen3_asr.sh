#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${ROOT_DIR}/.venv-asr/bin/python"
CLI_BIN="${ROOT_DIR}/.venv-asr/bin/mlx-qwen3-asr"
export PATH="${ROOT_DIR}/bin:${PATH}"

if [[ $# -gt 0 ]]; then
  SESSION_DIR="$1"
else
  LATEST_AUDIO="$(find "${ROOT_DIR}/Recordings" -maxdepth 2 -name mixed.wav -print | sort | tail -1)"
  if [[ -z "${LATEST_AUDIO}" ]]; then
    echo "No mixed.wav files found under ${ROOT_DIR}/Recordings" >&2
    exit 1
  fi
  SESSION_DIR="$(dirname "${LATEST_AUDIO}")"
fi

AUDIO_PATH="${SESSION_DIR}/mixed.wav"
ASR_AUDIO_PATH="${SESSION_DIR}/asr_input.wav"
MODEL_ID="${QWEN3_ASR_MODEL:-Qwen/Qwen3-ASR-0.6B}"
LANGUAGE="${QWEN3_ASR_LANGUAGE:-Chinese}"
RAW_JSON="${SESSION_DIR}/asr_input.json"
TRANSCRIPT_JSON="${SESSION_DIR}/transcript.json"
TRANSCRIPT_TXT="${SESSION_DIR}/transcript.txt"

if [[ ! -x "${PYTHON_BIN}" || ! -x "${CLI_BIN}" ]]; then
  echo "Missing .venv-asr. Install with:" >&2
  echo "  /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -m venv .venv-asr" >&2
  echo "  /Users/yimingliu/.local/bin/uv pip install --python .venv-asr/bin/python --upgrade pip setuptools wheel mlx-qwen3-asr" >&2
  exit 1
fi

if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "Missing audio file: ${AUDIO_PATH}" >&2
  echo "Usage: Scripts/transcribe_mlx_qwen3_asr.sh /path/to/recording-session" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg runtime. Re-run install_baby_recorder_runtime.sh and retry." >&2
  exit 1
fi

echo "Engine: mlx-qwen3-asr"
"${PYTHON_BIN}" - <<'PY'
import importlib.metadata as metadata

for package in ("mlx-qwen3-asr", "mlx", "mlx-metal"):
    print(f"{package}: {metadata.version(package)}")
PY

echo "Audio: ${AUDIO_PATH}"
echo "Model: ${MODEL_ID}"
echo "Language: ${LANGUAGE}"
echo "HF_HOME: ${HF_HOME:-<default>}"
echo "HF_ENDPOINT: ${HF_ENDPOINT:-<default>}"
echo "Preparing ASR input: ${ASR_AUDIO_PATH}"

ffmpeg \
  -hide_banner \
  -loglevel error \
  -y \
  -i "${AUDIO_PATH}" \
  -vn \
  -ac 1 \
  -ar 16000 \
  -sample_fmt s16 \
  "${ASR_AUDIO_PATH}"

"${CLI_BIN}" \
  "${ASR_AUDIO_PATH}" \
  --model "${MODEL_ID}" \
  --language "${LANGUAGE}" \
  --output-dir "${SESSION_DIR}" \
  --output-format json \
  --quiet \
  --verbose

"${PYTHON_BIN}" - "${RAW_JSON}" "${TRANSCRIPT_JSON}" "${TRANSCRIPT_TXT}" <<'PY'
import json
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])
txt_path = Path(sys.argv[3])

data = json.loads(raw_path.read_text(encoding="utf-8"))
json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
txt_path.write_text(str(data.get("text", "")).strip() + "\n", encoding="utf-8")
PY

echo "Outputs:"
echo "  ${TRANSCRIPT_TXT}"
echo "  ${TRANSCRIPT_JSON}"
