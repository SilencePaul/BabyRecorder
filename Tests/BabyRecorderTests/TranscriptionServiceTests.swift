import XCTest
@testable import BabyRecorder

final class TranscriptionServiceTests: XCTestCase {
    func testPythonMLXServiceRunsScriptWithSelectedModelAndReadsTranscript() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        try "audio".write(to: fixture.sessionDirectory.appendingPathComponent("mixed.wav"), atomically: true, encoding: .utf8)
        try "转写结果\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        try "{}\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript.json"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
        let service = PythonMLXTranscriptionService(
            runtimeRoot: fixture.runtimeRoot,
            scriptURL: fixture.scriptURL,
            environment: ["PATH": "/usr/bin"],
            processRunner: runner
        )

        let result = try await service.transcribe(
            TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .accurate)
        )

        XCTAssertEqual(result.text, "转写结果")
        XCTAssertEqual(result.transcriptURL, fixture.sessionDirectory.appendingPathComponent("transcript.txt"))
        XCTAssertEqual(
            try String(contentsOf: fixture.sessionDirectory.appendingPathComponent("transcription.log"), encoding: .utf8),
            "ok"
        )
        XCTAssertEqual(runner.runs, [
            ProcessRun(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [
                    "-lc",
                    "cd '\(fixture.runtimeRoot.path)' && QWEN3_ASR_MODEL='Qwen/Qwen3-ASR-1.7B' QWEN3_ASR_MODE='mixed' '\(fixture.scriptURL.path)' '\(fixture.sessionDirectory.path)'"
                ],
                environment: [
                    "HF_ENDPOINT": "https://hf-mirror.com",
                    "HF_HOME": fixture.runtimeRoot.appendingPathComponent("huggingface").path,
                    "HF_HUB_CACHE": fixture.runtimeRoot.appendingPathComponent("huggingface/hub").path,
                    "HOME": NSHomeDirectory(),
                    "PATH": "/usr/bin",
                    "PYTHONUNBUFFERED": "1",
                    "SHELL": "/bin/zsh"
                ],
                currentDirectoryURL: fixture.runtimeRoot
            )
        ])
    }

    func testPythonMLXServiceRunsDialogueModeWithSelectedModel() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        try "mic".write(to: fixture.sessionDirectory.appendingPathComponent("mic.wav"), atomically: true, encoding: .utf8)
        try "system".write(to: fixture.sessionDirectory.appendingPathComponent("system.wav"), atomically: true, encoding: .utf8)
        try "对话稿\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.txt"), atomically: true, encoding: .utf8)
        try "{}\n".write(to: fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.json"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "ok", standardError: ""))
        let service = PythonMLXTranscriptionService(
            runtimeRoot: fixture.runtimeRoot,
            scriptURL: fixture.scriptURL,
            processRunner: runner
        )

        let result = try await service.transcribe(
            TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .fast, mode: .dialogue)
        )

        XCTAssertEqual(result.text, "对话稿")
        XCTAssertEqual(result.transcriptURL, fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.txt"))
        XCTAssertEqual(result.metadataURL, fixture.sessionDirectory.appendingPathComponent("transcript_dialogue.json"))
        XCTAssertEqual(runner.runs.count, 1)
        XCTAssertTrue(runner.runs[0].arguments[1].contains("QWEN3_ASR_MODE='dialogue'"))
    }

    func testPythonMLXServiceFailsBeforeRunningWhenMixedAudioIsMissing() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        let service = PythonMLXTranscriptionService(
            runtimeRoot: fixture.runtimeRoot,
            scriptURL: fixture.scriptURL,
            processRunner: runner
        )

        do {
            _ = try await service.transcribe(
                TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .fast)
            )
            XCTFail("Expected missing audio error")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .missingAudio(fixture.sessionDirectory.appendingPathComponent("mixed.wav")))
            XCTAssertEqual(runner.runs, [])
        }
    }

    func testPythonMLXServiceFailsBeforeRunningDialogueModeWhenTrackIsMissing() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        try "mic".write(to: fixture.sessionDirectory.appendingPathComponent("mic.wav"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        let service = PythonMLXTranscriptionService(
            runtimeRoot: fixture.runtimeRoot,
            scriptURL: fixture.scriptURL,
            processRunner: runner
        )

        do {
            _ = try await service.transcribe(
                TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .fast, mode: .dialogue)
            )
            XCTFail("Expected missing system audio error")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .missingAudio(fixture.sessionDirectory.appendingPathComponent("system.wav")))
            XCTAssertEqual(runner.runs, [])
        }
    }

    func testPythonMLXServiceReportsNonZeroExitOutput() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        try "audio".write(to: fixture.sessionDirectory.appendingPathComponent("mixed.wav"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner(
            result: ProcessResult(exitCode: 1, standardOutput: "stdout", standardError: "stderr")
        )
        let service = PythonMLXTranscriptionService(
            runtimeRoot: fixture.runtimeRoot,
            scriptURL: fixture.scriptURL,
            processRunner: runner
        )

        do {
            _ = try await service.transcribe(
                TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .fast)
            )
            XCTFail("Expected process failure")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .processFailed("stdout\nstderr"))
            XCTAssertEqual(
                try String(contentsOf: fixture.sessionDirectory.appendingPathComponent("transcription.log"), encoding: .utf8),
                "stdout\nstderr"
            )
        }
    }
}

private struct TemporaryTranscriptionFixture {
    let runtimeRoot: URL
    let scriptURL: URL
    let sessionDirectory: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("baby-recorder-transcription-\(UUID().uuidString)", isDirectory: true)
        runtimeRoot = root
        scriptURL = root.appendingPathComponent("Scripts/transcribe_mlx_qwen3_asr.sh")
        sessionDirectory = root.appendingPathComponent("Recordings/session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".venv-asr/bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: scriptURL)
        try Data().write(to: root.appendingPathComponent(".venv-asr/bin/python"))
    }
}

private struct ProcessRun: Equatable {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
    var currentDirectoryURL: URL
}

private final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private(set) var runs: [ProcessRun] = []
    var result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL
    ) async throws -> ProcessResult {
        runs.append(
            ProcessRun(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectoryURL: currentDirectoryURL
            )
        )
        return result
    }
}
