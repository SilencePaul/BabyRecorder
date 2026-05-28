import XCTest

final class DistributionScriptTests: XCTestCase {
    func testDistributionBuildsDmgWithRuntimeSetupInsideTheApp() throws {
        let root = packageRoot()
        let packager = root.appendingPathComponent("Scripts/make_distribution.sh")
        let runtimeSetup = root.appendingPathComponent("Sources/BabyRecorder/Resources/Scripts/setup_baby_recorder_runtime.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: packager.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeSetup.path))

        let packagerText = try String(contentsOf: packager, encoding: .utf8)
        XCTAssertTrue(packagerText.contains("BabyRecorder.dmg"))
        XCTAssertTrue(packagerText.contains("create-dmg"))
        XCTAssertFalse(packagerText.contains("install_baby_recorder_runtime.sh"))
        XCTAssertFalse(packagerText.contains("BabyRecorder-Install.zip"))
        XCTAssertTrue(packagerText.contains("tail -n 1"))

        let runtimeSetupText = try String(contentsOf: runtimeSetup, encoding: .utf8)
        XCTAssertTrue(runtimeSetupText.contains("imageio-ffmpeg"))
        XCTAssertTrue(runtimeSetupText.contains("install_ffmpeg_wrapper"))
        XCTAssertTrue(runtimeSetupText.contains("verify_runtime"))
        XCTAssertTrue(runtimeSetupText.contains("mlx-qwen3-asr"))
        XCTAssertTrue(runtimeSetupText.contains("ffmpeg -version"))
    }

    func testRepositoryReadmeCoversInstallAndProjectBackground() throws {
        let readme = packageRoot().appendingPathComponent("README.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: readme.path))

        let text = try String(contentsOf: readme, encoding: .utf8)
        XCTAssertTrue(text.contains("项目来由"))
        XCTAssertTrue(text.contains("一键安装"))
        XCTAssertTrue(text.contains("Qwen3-ASR"))
        XCTAssertTrue(text.contains("中国大陆"))
    }

    func testTranscriptionScriptUsesBundledRuntimeFfmpegFirst() throws {
        let script = packageRoot()
            .appendingPathComponent("Sources/BabyRecorder/Resources/Scripts/transcribe_mlx_qwen3_asr.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        XCTAssertTrue(text.contains("export PATH=\"${ROOT_DIR}/bin:${PATH}\""))
        XCTAssertTrue(text.contains("command -v ffmpeg"))
        XCTAssertTrue(text.contains("ASR_AUDIO_PATH=\"${SESSION_DIR}/asr_input.wav\""))
        XCTAssertTrue(text.contains("-ac 1"))
        XCTAssertTrue(text.contains("-ar 16000"))
        XCTAssertTrue(text.contains("-sample_fmt s16"))
        XCTAssertTrue(text.contains("\"${ASR_AUDIO_PATH}\""))
        XCTAssertTrue(text.contains("RAW_JSON=\"${SESSION_DIR}/asr_input.json\""))
        XCTAssertTrue(text.contains("QWEN3_ASR_MODE"))
        XCTAssertTrue(text.contains("transcribe_track"))
        XCTAssertTrue(text.contains("mic_asr.json"))
        XCTAssertTrue(text.contains("system_asr.json"))
        XCTAssertTrue(text.contains("transcript_dialogue.txt"))
        XCTAssertTrue(text.contains("speaker\": speaker"))
        XCTAssertTrue(text.contains("is_filler_only"))
    }

    private func packageRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
