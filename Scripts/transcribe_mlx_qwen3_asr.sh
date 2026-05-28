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

MODE="${QWEN3_ASR_MODE:-mixed}"
MODEL_ID="${QWEN3_ASR_MODEL:-Qwen/Qwen3-ASR-0.6B}"
LANGUAGE="${QWEN3_ASR_LANGUAGE:-Chinese}"

AUDIO_PATH="${SESSION_DIR}/mixed.wav"
ASR_AUDIO_PATH="${SESSION_DIR}/asr_input.wav"
RAW_JSON="${SESSION_DIR}/asr_input.json"
TRANSCRIPT_JSON="${SESSION_DIR}/transcript.json"
TRANSCRIPT_TXT="${SESSION_DIR}/transcript.txt"

MIC_AUDIO_PATH="${SESSION_DIR}/mic.wav"
SYSTEM_AUDIO_PATH="${SESSION_DIR}/system.wav"
MIC_ASR_AUDIO_PATH="${SESSION_DIR}/mic_asr_input.wav"
SYSTEM_ASR_AUDIO_PATH="${SESSION_DIR}/system_asr_input.wav"
MIC_RAW_JSON="${SESSION_DIR}/mic_asr.json"
SYSTEM_RAW_JSON="${SESSION_DIR}/system_asr.json"
DIALOGUE_JSON="${SESSION_DIR}/transcript_dialogue.json"
DIALOGUE_TXT="${SESSION_DIR}/transcript_dialogue.txt"
ME_TXT="${SESSION_DIR}/transcript_me.txt"
OTHER_TXT="${SESSION_DIR}/transcript_other.txt"

if [[ ! -x "${PYTHON_BIN}" || ! -x "${CLI_BIN}" ]]; then
  echo "Missing .venv-asr. Install with:" >&2
  echo "  /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13 -m venv .venv-asr" >&2
  echo "  /Users/yimingliu/.local/bin/uv pip install --python .venv-asr/bin/python --upgrade pip setuptools wheel mlx-qwen3-asr" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Missing ffmpeg runtime. Re-run install_baby_recorder_runtime.sh and retry." >&2
  exit 1
fi

require_audio() {
  local audio_path="$1"

  if [[ ! -f "${audio_path}" ]]; then
    echo "Missing audio file: ${audio_path}" >&2
    echo "Usage: Scripts/transcribe_mlx_qwen3_asr.sh /path/to/recording-session" >&2
    exit 1
  fi
}

print_runtime_info() {
  echo "Engine: mlx-qwen3-asr"
  "${PYTHON_BIN}" - <<'PY'
import importlib.metadata as metadata

for package in ("mlx-qwen3-asr", "mlx", "mlx-metal"):
    print(f"{package}: {metadata.version(package)}")
PY

  echo "Mode: ${MODE}"
  echo "Model: ${MODEL_ID}"
  echo "Language: ${LANGUAGE}"
  echo "HF_HOME: ${HF_HOME:-<default>}"
  echo "HF_ENDPOINT: ${HF_ENDPOINT:-<default>}"
}

transcribe_track() {
  local input_wav="$1"
  local asr_wav="$2"
  local raw_json="$3"
  local generated_json="${asr_wav%.wav}.json"

  echo "Audio: ${input_wav}"
  echo "Preparing ASR input: ${asr_wav}"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -y \
    -i "${input_wav}" \
    -vn \
    -ac 1 \
    -ar 16000 \
    -sample_fmt s16 \
    "${asr_wav}"

  "${CLI_BIN}" \
    "${asr_wav}" \
    --model "${MODEL_ID}" \
    --language "${LANGUAGE}" \
    --output-dir "${SESSION_DIR}" \
    --output-format json \
    --quiet \
    --verbose

  if [[ "${generated_json}" != "${raw_json}" ]]; then
    mv "${generated_json}" "${raw_json}"
  fi
}

write_mixed_outputs() {
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
}

write_dialogue_outputs() {
  "${PYTHON_BIN}" - \
    "${MIC_RAW_JSON}" \
    "${SYSTEM_RAW_JSON}" \
    "${DIALOGUE_JSON}" \
    "${DIALOGUE_TXT}" \
    "${ME_TXT}" \
    "${OTHER_TXT}" <<'PY'
import json
import re
import sys
from pathlib import Path

mic_path = Path(sys.argv[1])
system_path = Path(sys.argv[2])
dialogue_json_path = Path(sys.argv[3])
dialogue_txt_path = Path(sys.argv[4])
me_txt_path = Path(sys.argv[5])
other_txt_path = Path(sys.argv[6])


def number_or_none(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def timestamp_value(chunk, index):
    for key in ("timestamp", "timestamps"):
        value = chunk.get(key)
        if isinstance(value, (list, tuple)) and len(value) > index:
            number = number_or_none(value[index])
            if number is not None:
                return number
    key = "start" if index == 0 else "end"
    return number_or_none(chunk.get(key))


def is_filler_only(text):
    normalized = re.sub(r"[\s，。！？、,.!?…~～—-]", "", text)
    if not normalized:
        return True
    return re.fullmatch(r"[嗯恩呃额啊哦噢唔哼]+", normalized) is not None


def load_entries(path, speaker):
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = []
    for chunk in data.get("chunks", []):
        if not isinstance(chunk, dict):
            continue
        text = str(chunk.get("text", "")).strip()
        if not text:
            continue
        if is_filler_only(text):
            continue
        start = timestamp_value(chunk, 0)
        end = timestamp_value(chunk, 1)
        entries.append({
            "speaker": speaker,
            "start": 0.0 if start is None else start,
            "end": end,
            "text": text,
        })
    return entries


def format_time(seconds):
    total = max(0, int(round(seconds)))
    hours, remainder = divmod(total, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


mic_entries = load_entries(mic_path, "我")
system_entries = load_entries(system_path, "对方")
speaker_order = {"我": 0, "对方": 1}
entries = sorted(
    [*mic_entries, *system_entries],
    key=lambda entry: (entry["start"], speaker_order.get(entry["speaker"], 99)),
)

dialogue_json_path.write_text(
    json.dumps({"chunks": entries}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
dialogue_txt_path.write_text(
    "\n".join(f"[{format_time(entry['start'])}] {entry['speaker']}：{entry['text']}" for entry in entries) + "\n",
    encoding="utf-8",
)
me_txt_path.write_text("\n".join(entry["text"] for entry in mic_entries).strip() + "\n", encoding="utf-8")
other_txt_path.write_text("\n".join(entry["text"] for entry in system_entries).strip() + "\n", encoding="utf-8")
PY
}

print_runtime_info

case "${MODE}" in
  mixed)
    require_audio "${AUDIO_PATH}"
    transcribe_track "${AUDIO_PATH}" "${ASR_AUDIO_PATH}" "${RAW_JSON}"
    write_mixed_outputs
    echo "Outputs:"
    echo "  ${TRANSCRIPT_TXT}"
    echo "  ${TRANSCRIPT_JSON}"
    ;;
  dialogue)
    require_audio "${MIC_AUDIO_PATH}"
    require_audio "${SYSTEM_AUDIO_PATH}"
    transcribe_track "${MIC_AUDIO_PATH}" "${MIC_ASR_AUDIO_PATH}" "${MIC_RAW_JSON}"
    transcribe_track "${SYSTEM_AUDIO_PATH}" "${SYSTEM_ASR_AUDIO_PATH}" "${SYSTEM_RAW_JSON}"
    write_dialogue_outputs
    echo "Outputs:"
    echo "  ${DIALOGUE_TXT}"
    echo "  ${DIALOGUE_JSON}"
    echo "  ${ME_TXT}"
    echo "  ${OTHER_TXT}"
    ;;
  *)
    echo "Unsupported QWEN3_ASR_MODE: ${MODE}. Use mixed or dialogue." >&2
    exit 1
    ;;
esac
