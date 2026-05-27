#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${BABY_RECORDER_INSTALL_DIR:-$HOME/Applications}"
APP_DEST="$INSTALL_ROOT/BabyRecorder.app"
RUNTIME_ROOT="${BABY_RECORDER_RUNTIME_DIR:-$HOME/Library/Application Support/BabyRecorder}"
SCRIPT_DEST="$RUNTIME_ROOT/Scripts/transcribe_mlx_qwen3_asr.sh"
PYTHON_BIN="${BABY_RECORDER_PYTHON:-}"
PYPI_INDEX="${BABY_RECORDER_PYPI_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PYPI_FALLBACK_INDEXES="${BABY_RECORDER_PYPI_FALLBACK_INDEXES:-https://mirrors.aliyun.com/pypi/simple https://pypi.org/simple}"
HF_ENDPOINT_VALUE="${HF_ENDPOINT:-https://hf-mirror.com}"
WARM_MODEL="${BABY_RECORDER_WARM_MODEL:-1}"

find_python() {
  if [[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]]; then
    echo "$PYTHON_BIN"
    return
  fi

  for candidate in \
    "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13" \
    "/opt/homebrew/bin/python3.13" \
    "/usr/local/bin/python3.13" \
    "/opt/homebrew/bin/python3.12" \
    "/usr/local/bin/python3.12" \
    "/usr/bin/python3"
  do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  echo "Python 3.12 or 3.13 was not found. Install Python first, then rerun this script." >&2
  exit 1
}

run_pip_install_once() {
  local venv_python="$1"
  local index_url="$2"
  if command -v uv >/dev/null 2>&1; then
    uv pip install \
      --python "$venv_python" \
      --index-url "$index_url" \
      --upgrade pip setuptools wheel mlx-qwen3-asr
  else
    "$venv_python" -m pip install \
      --index-url "$index_url" \
      --upgrade pip setuptools wheel mlx-qwen3-asr
  fi
}

run_pip_install() {
  local venv_python="$1"
  local indexes=("$PYPI_INDEX")
  local fallback
  for fallback in $PYPI_FALLBACK_INDEXES; do
    indexes+=("$fallback")
  done

  local index
  for index in "${indexes[@]}"; do
    echo "Trying PyPI index: $index"
    if run_pip_install_once "$venv_python" "$index"; then
      echo "Installed dependencies via: $index"
      return
    fi
    echo "PyPI index failed, trying next mirror..." >&2
  done

  echo "Failed to install Python dependencies from all configured PyPI mirrors." >&2
  exit 1
}

echo "Installing BabyRecorder app..."
bash "$ROOT/Scripts/install_app.sh" >/dev/null

echo "Preparing runtime at: $RUNTIME_ROOT"
mkdir -p "$RUNTIME_ROOT/Scripts" "$RUNTIME_ROOT/huggingface"

if [[ -f "$APP_DEST/Contents/Resources/Scripts/transcribe_mlx_qwen3_asr.sh" ]]; then
  cp "$APP_DEST/Contents/Resources/Scripts/transcribe_mlx_qwen3_asr.sh" "$SCRIPT_DEST"
else
  cp "$ROOT/Scripts/transcribe_mlx_qwen3_asr.sh" "$SCRIPT_DEST"
fi
chmod +x "$SCRIPT_DEST"

PYTHON="$(find_python)"
if [[ ! -x "$RUNTIME_ROOT/.venv-asr/bin/python" ]]; then
  echo "Creating Python environment with: $PYTHON"
  "$PYTHON" -m venv "$RUNTIME_ROOT/.venv-asr"
fi

echo "Installing MLX ASR dependencies..."
run_pip_install "$RUNTIME_ROOT/.venv-asr/bin/python"

if [[ "$WARM_MODEL" == "1" ]]; then
  echo "Warming Qwen3-ASR-0.6B model cache via: $HF_ENDPOINT_VALUE"
  HF_HOME="$RUNTIME_ROOT/huggingface" \
  HF_HUB_CACHE="$RUNTIME_ROOT/huggingface/hub" \
  HF_ENDPOINT="$HF_ENDPOINT_VALUE" \
  "$RUNTIME_ROOT/.venv-asr/bin/python" - <<'PY'
from huggingface_hub import snapshot_download

snapshot_download(repo_id="Qwen/Qwen3-ASR-0.6B")
print("Qwen/Qwen3-ASR-0.6B cache ready")
PY
else
  echo "Skipping model warmup because BABY_RECORDER_WARM_MODEL=$WARM_MODEL"
fi

echo
echo "BabyRecorder is installed:"
echo "  $APP_DEST"
echo "Runtime is ready:"
echo "  $RUNTIME_ROOT"
echo
echo "Open the app, grant Microphone and Screen Recording permissions, then record and click Start Transcription."
