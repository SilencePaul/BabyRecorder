# BabyRecorder

BabyRecorder 是一个面向中文用户的 macOS 本地录音与语音转文字工具。它的目标很简单：在 Mac 上稳定录制麦克风与系统声音，录完后按需转写，不把模型长期驻留在内存里。

## 项目来由

这个项目最初是为了帮女朋友解决一个很具体的问题：在 Mac 上录下课程、会议或资料声音时，经常需要同时保留自己的声音和系统声音，录完以后还要能尽快整理成文字。现成方案要么依赖额外声卡/虚拟音频设备，要么安装和权限步骤太绕，要么转写流程不够省心，所以 BabyRecorder 的目标从一开始就是做成一个“她能直接用”的小工具。

早期重点先解决 macOS 上最麻烦的部分：屏幕/系统音频权限、麦克风权限、耳机设备切换、录音文件校验和稳定的 App 身份。它不追求复杂工作流，优先保证打开就能录、合上主窗口也能留在状态栏、录完后按需在本地完成语音转文字。

目前的实现已经去掉了对 BlackHole 的依赖，改为使用 macOS 的系统录屏与系统录音能力；对于 AirPods、有线耳机麦克风等设备，App 会优先选择可用输入设备。语音转文字使用 Qwen3-ASR + MLX，在 Apple Silicon 上本地运行。

## 当前实现

- macOS SwiftUI 原生 App，默认中文界面，同时保留英文本地化。
- 稳定 Bundle ID：`com.yimingliu.BabyRecorder`，用于固定系统权限项。
- 支持麦克风 + 系统声音录制。
- 支持状态栏驻留，关闭主窗口后继续留在菜单栏中控制。
- 支持自动识别腾讯会议、飞书/Lark、钉钉的会议窗口，并在检测到会议中时自动开始录制；会议可能结束时会提示用户确认停止，不会自动切断录音。
- 录音完成后生成会话目录、音频文件和诊断文件，默认保存到当前用户的 `~/Library/Application Support/BabyRecorder/Recordings`。
- 支持录音文件校验，便于定位权限或设备问题。
- 支持按需语音转文字，不常驻加载模型，节省内存。
- 支持“完整转写”和“分角色对话”两种转写模式；分角色模式会把 `mic.wav` 标为“我”，把 `system.wav` 标为“对方”，按时间顺序合并成对话稿。
- 默认转写模型：`Qwen/Qwen3-ASR-0.6B`。
- 可切换高精度模型：`Qwen/Qwen3-ASR-1.7B`。
- Python/MLX 运行环境放在 `~/Library/Application Support/BabyRecorder`，不依赖开发目录。
- 安装脚本适配中国大陆网络环境：Python、PyPI、Hugging Face 均配置了可用镜像或 fallback。
- 转写所需的 `ffmpeg` 会随 Python 运行时一起准备，不要求最终用户单独安装 Homebrew。

## 一键安装

给最终用户安装时，不建议让她 clone 源码后自己编译。推荐从 GitHub Release 下载 `BabyRecorder.dmg`。

安装步骤：

- 打开 `BabyRecorder.dmg`。
- 把 `BabyRecorder.app` 拖到 `Applications`。
- 第一次打开 App 时，它会在应用内自动准备 Python、MLX 依赖、`ffmpeg` 和默认模型。
- 准备完成后，按 macOS 提示授予“麦克风”和“录屏与系统录音”权限。

第一次启动会下载 Python 3.13、MLX ASR 依赖和默认模型。之后 App 只有在点击“开始转写”时才会启动转写进程。

## 开发者打包

在仓库根目录运行：

```bash
Scripts/make_distribution.sh
```

脚本会生成：

```text
dist/BabyRecorder.dmg
```

这个 DMG 可以上传到 GitHub Release，最终用户下载后拖拽安装即可。

## 本地开发

项目级开发规则见 [`AGENTS.md`](AGENTS.md)。其中记录了当前 workspace 路径、开发流程、测试/打包命令，以及“项目描述必须随功能实时更新”的要求。

构建和测试：

```bash
swift test
Scripts/package_app.sh
```

安装到当前用户的 Applications：

```bash
Scripts/install_app.sh
```

准备开发机上的转写运行环境：

```bash
Scripts/install_baby_recorder_runtime.sh
```

最终用户不需要运行这个脚本；正式安装包会在 App 首次启动时自动准备转写运行环境。

## 语音转文字架构

当前采用“省内存版”设计：

1. App 录制完成后只保存音频与诊断文件。
2. 用户点击“开始转写”。
3. Swift App 启动一次 Python MLX 转写进程。
4. Python 进程加载 Qwen3-ASR 模型，完成转写后退出。
5. App 读取 `transcript.txt` 和 `transcript.json` 并展示状态。

这样不会像常驻服务一样长期占用统一内存，更适合日常 Mac 使用。

转写模式：

- `完整转写`：转写混合音轨 `mixed.wav`，输出 `transcript.txt` 和 `transcript.json`。
- `分角色对话`：分别转写 `mic.wav` 和 `system.wav`，再按 Qwen JSON 中的 chunk 时间戳合并，输出 `transcript_dialogue.txt`、`transcript_dialogue.json`、`transcript_me.txt` 和 `transcript_other.txt`。

分角色对话模式不做复杂的多人声纹识别。它依赖 BabyRecorder 录制时天然分开的两条音轨：本机麦克风是“我”，系统声音是“对方”。这比在混合音频里猜说话人更稳定，也更适合腾讯会议这类场景。

## 目录说明

- `Sources/BabyRecorder`：SwiftUI App 主代码。
- `Sources/BabyRecorder/Audio`：音频混音与文件写入。
- `Sources/BabyRecorder/Capture`：系统音频、屏幕录制与麦克风捕获。
- `Sources/BabyRecorder/Permissions`：macOS 权限检测。
- `Sources/BabyRecorder/Transcription`：Swift 到 Python/MLX 的转写桥接。
- `Sources/BabyRecorder/UI`：主窗口与状态栏 UI。
- `Sources/BabyRecorder/Resources`：本地化文案和内置脚本。
- `Scripts`：开发、打包、安装和转写脚本。
- `Tests/BabyRecorderTests`：单元测试。
- `docs/superpowers`：设计和实现计划记录。

## 注意事项

- 本项目当前主要面向 Apple Silicon Mac。
- 语音模型首次下载体积较大，需要稳定网络。
- 由于 App 目前使用 ad-hoc 签名，首次打开时 macOS 可能提示未认证开发者，需要手动允许。
- 录屏与系统录音权限由 macOS 控制，首次授权后可能需要重新打开 App。
- 自动会议识别依赖 macOS 允许 App 读取会议窗口标题。如果系统未授予辅助功能相关权限，BabyRecorder 会保守地不自动开始，手动录制仍可正常使用。
