#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_ROOT="$ROOT/dist"
PACKAGE_NAME="BabyRecorder-Install"
PACKAGE_DIR="$DIST_ROOT/$PACKAGE_NAME"
ZIP_PATH="$DIST_ROOT/$PACKAGE_NAME.zip"

cd "$ROOT"

echo "Packaging BabyRecorder.app..."
APP_PATH="$(bash "$ROOT/Scripts/package_app.sh" | tail -n 1)"

rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR"

ditto --noextattr --noqtn "$APP_PATH" "$PACKAGE_DIR/BabyRecorder.app"
cp "$ROOT/Scripts/install_distribution.sh" "$PACKAGE_DIR/install_baby_recorder_runtime.sh"
chmod +x "$PACKAGE_DIR/install_baby_recorder_runtime.sh"

cat > "$PACKAGE_DIR/README_安装说明.md" <<'EOF'
# BabyRecorder 安装说明

这是给最终用户使用的安装包，不需要安装 Xcode，也不需要自己编译源码。

## 安装步骤

1. 解压 `BabyRecorder-Install.zip`。
2. 打开解压后的 `BabyRecorder-Install` 文件夹。
3. 双击或在终端运行 `install_baby_recorder_runtime.sh`。
4. 安装脚本会自动完成：
   - 安装 `BabyRecorder.app` 到 `~/Applications`
   - 准备 Python 3.13 环境
   - 安装 MLX 语音转文字依赖
   - 通过中国大陆可用镜像下载默认模型 `Qwen/Qwen3-ASR-0.6B`
5. 打开 `~/Applications/BabyRecorder.app`。
6. 按 macOS 提示授予“麦克风”和“录屏与系统录音”权限。

## 第一次使用

第一次安装会下载 Python、Python 依赖和语音模型，时间取决于网络。之后正常录音不会常驻加载模型，只有点击“开始转写”时才会启动转写进程。

如果 macOS 提示无法打开来自未认证开发者的 App，请在“系统设置 > 隐私与安全性”中允许打开，或右键点击 App 选择“打开”。

## 常见问题

- 如果下载慢，安装脚本默认优先使用华为云 Python 镜像、清华/阿里 PyPI 镜像和 `hf-mirror.com`。
- 如果已经装过 Python 3.13，脚本会直接复用。
- 如果转写失败，重新打开 App 后点击“重新转写”；也可以重新运行本安装脚本修复运行环境。
EOF

xattr -cr "$PACKAGE_DIR"

(
  cd "$DIST_ROOT"
  ditto -c -k --norsrc --noextattr --keepParent "$PACKAGE_NAME" "$ZIP_PATH"
)

echo
echo "Distribution package created:"
echo "  $ZIP_PATH"
