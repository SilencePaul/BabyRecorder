#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="${BABY_RECORDER_INSTALL_DIR:-$HOME/Applications}"
APP_DEST="$INSTALL_ROOT/BabyRecorder.app"
RUNTIME_ROOT="${BABY_RECORDER_RUNTIME_DIR:-$HOME/Library/Application Support/BabyRecorder}"
SCRIPT_DEST="$RUNTIME_ROOT/Scripts/transcribe_mlx_qwen3_asr.sh"
PYTHON_BIN="${BABY_RECORDER_PYTHON:-}"
PYTHON_VERSION="${BABY_RECORDER_PYTHON_VERSION:-3.13.2}"
PYTHON_INSTALL_METHOD="${BABY_RECORDER_PYTHON_INSTALL_METHOD:-auto}"
PYTHON_PKG_URLS="${BABY_RECORDER_PYTHON_PKG_URLS:-https://repo.huaweicloud.com/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-macos11.pkg https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-macos11.pkg}"
PYPI_INDEX="${BABY_RECORDER_PYPI_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PYPI_FALLBACK_INDEXES="${BABY_RECORDER_PYPI_FALLBACK_INDEXES:-https://mirrors.aliyun.com/pypi/simple https://pypi.org/simple}"
HF_ENDPOINT_VALUE="${HF_ENDPOINT:-https://hf-mirror.com}"
WARM_MODEL="${BABY_RECORDER_WARM_MODEL:-1}"

is_python_313() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[:2] == (3, 13) else 1)
PY
}

find_existing_python() {
  if [[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]]; then
    if is_python_313 "$PYTHON_BIN"; then
      echo "$PYTHON_BIN"
      return
    fi
    echo "BABY_RECORDER_PYTHON is set but is not Python 3.13: $PYTHON_BIN" >&2
    exit 1
  fi

  for candidate in \
    "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13" \
    "/opt/homebrew/bin/python3.13" \
    "/usr/local/bin/python3.13" \
    "/usr/bin/python3"
  do
    if is_python_313 "$candidate"; then
      echo "$candidate"
      return
    fi
  done
}

install_python_with_brew() {
  command -v brew >/dev/null 2>&1 || return 1
  echo "Installing Python 3.13 with Homebrew..." >&2
  brew install python@3.13 >&2
}

install_python_with_pkg() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local pkg_path="$tmp_dir/python-${PYTHON_VERSION}-macos11.pkg"
  local url

  for url in $PYTHON_PKG_URLS; do
    echo "Downloading Python ${PYTHON_VERSION} from: $url" >&2
    if /usr/bin/curl -fL --connect-timeout 20 --retry 2 --retry-delay 2 -o "$pkg_path" "$url" >&2; then
      echo "Installing Python ${PYTHON_VERSION}. macOS may ask for your password." >&2
      /usr/bin/sudo /usr/sbin/installer -pkg "$pkg_path" -target / >&2
      rm -rf "$tmp_dir"
      return
    fi
    echo "Python download failed, trying next source..." >&2
  done

  rm -rf "$tmp_dir"
  echo "Failed to download Python ${PYTHON_VERSION} from all configured sources." >&2
  exit 1
}

ensure_python() {
  local existing
  existing="$(find_existing_python || true)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi

  case "$PYTHON_INSTALL_METHOD" in
    auto)
      if install_python_with_brew; then
        :
      else
        install_python_with_pkg
      fi
      ;;
    brew)
      install_python_with_brew || {
        echo "Homebrew is not available or failed to install python@3.13." >&2
        exit 1
      }
      ;;
    pkg)
      install_python_with_pkg
      ;;
    skip)
      echo "Python 3.13 was not found and BABY_RECORDER_PYTHON_INSTALL_METHOD=skip." >&2
      exit 1
      ;;
    *)
      echo "Unknown BABY_RECORDER_PYTHON_INSTALL_METHOD: $PYTHON_INSTALL_METHOD" >&2
      exit 1
      ;;
  esac

  existing="$(find_existing_python || true)"
  if [[ -z "$existing" ]]; then
    echo "Python 3.13 installation finished, but python3.13 was not found." >&2
    exit 1
  fi
  echo "$existing"
}

run_pip_install_once() {
  local venv_python="$1"
  local index_url="$2"
  if command -v uv >/dev/null 2>&1; then
    uv pip install \
      --python "$venv_python" \
      --index-url "$index_url" \
      --upgrade pip setuptools wheel mlx-qwen3-asr imageio-ffmpeg
  else
    "$venv_python" -m pip install \
      --index-url "$index_url" \
      --upgrade pip setuptools wheel mlx-qwen3-asr imageio-ffmpeg
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

install_ffmpeg_wrapper() {
  local venv_python="$1"
  local wrapper="$RUNTIME_ROOT/bin/ffmpeg"

  mkdir -p "$RUNTIME_ROOT/bin"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec "$venv_python" - "\$@" <<'PY'
import os
import sys
import imageio_ffmpeg

ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
os.execv(ffmpeg, [ffmpeg, *sys.argv[1:]])
PY
EOF
  chmod +x "$wrapper"

  "$wrapper" -version >/dev/null
  echo "ffmpeg runtime ready: $wrapper"
}

verify_runtime() {
  local venv_python="$1"
  local cli="$RUNTIME_ROOT/.venv-asr/bin/mlx-qwen3-asr"

  echo "Verifying transcription runtime..."
  "$venv_python" - <<'PY'
import importlib.metadata as metadata
import imageio_ffmpeg

for package in ("mlx-qwen3-asr", "mlx", "mlx-metal", "imageio-ffmpeg", "huggingface-hub"):
    print(f"{package}: {metadata.version(package)}")

print(f"imageio ffmpeg: {imageio_ffmpeg.get_ffmpeg_exe()}")
PY
  "$cli" --help >/dev/null
  PATH="$RUNTIME_ROOT/bin:$PATH" ffmpeg -version >/dev/null
  echo "Transcription runtime verification passed."
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

PYTHON="$(ensure_python)"
if [[ ! -x "$RUNTIME_ROOT/.venv-asr/bin/python" ]]; then
  echo "Creating Python environment with: $PYTHON"
  "$PYTHON" -m venv "$RUNTIME_ROOT/.venv-asr"
fi

echo "Installing MLX ASR dependencies..."
run_pip_install "$RUNTIME_ROOT/.venv-asr/bin/python"
install_ffmpeg_wrapper "$RUNTIME_ROOT/.venv-asr/bin/python"
verify_runtime "$RUNTIME_ROOT/.venv-asr/bin/python"

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
