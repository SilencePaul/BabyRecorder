import XCTest
@testable import BabyRecorder

final class RuntimeSetupServiceTests: XCTestCase {
    func testRuntimeIsReadyWhenScriptPythonCliFfmpegAndModelSnapshotExist() throws {
        let root = try makeRuntimeRoot()
        try makeReadyRuntime(at: root)

        let service = RuntimeSetupService(runtimeRoot: root)

        XCTAssertTrue(service.isReady)
    }

    func testRuntimeIsNotReadyWhenFfmpegWrapperIsMissing() throws {
        let root = try makeRuntimeRoot()
        try makeReadyRuntime(at: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("bin/ffmpeg"))

        let service = RuntimeSetupService(runtimeRoot: root)

        XCTAssertFalse(service.isReady)
    }

    func testRuntimeIsNotReadyWhenDefaultModelCacheIsMissing() throws {
        let root = try makeRuntimeRoot()
        try makeReadyRuntime(at: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("huggingface/hub/models--Qwen--Qwen3-ASR-0.6B"))

        let service = RuntimeSetupService(runtimeRoot: root)

        XCTAssertFalse(service.isReady)
    }

    func testSetupCommandUsesBundledRuntimeScriptAndRuntimeRootEnvironment() throws {
        let root = try makeRuntimeRoot()
        let script = try makeScript(named: "setup_baby_recorder_runtime.sh")
        let service = RuntimeSetupService(runtimeRoot: root, setupScriptURL: script)

        let command = service.setupCommand()

        XCTAssertEqual(command.executableURL.path, "/bin/bash")
        XCTAssertEqual(command.arguments, [script.path])
        XCTAssertEqual(command.environment["BABY_RECORDER_RUNTIME_DIR"], root.path)
        XCTAssertEqual(command.environment["BABY_RECORDER_WARM_MODEL"], "1")
    }

    private func makeRuntimeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeReadyRuntime(at root: URL) throws {
        try makeFile(root.appendingPathComponent("Scripts/transcribe_mlx_qwen3_asr.sh"))
        try makeFile(root.appendingPathComponent(".venv-asr/bin/python"))
        try makeFile(root.appendingPathComponent(".venv-asr/bin/mlx-qwen3-asr"))
        try makeFile(root.appendingPathComponent("bin/ffmpeg"))
        try makeFile(root.appendingPathComponent("huggingface/hub/models--Qwen--Qwen3-ASR-0.6B/snapshots/main/config.json"))
    }

    private func makeScript(named name: String) throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        try makeFile(script)
        return script
    }

    private func makeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
    }
}
