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
            projectRoot: fixture.projectRoot,
            scriptURL: fixture.scriptURL,
            environment: ["PATH": "/usr/bin"],
            processRunner: runner
        )

        let result = try await service.transcribe(
            TranscriptionRequest(sessionDirectory: fixture.sessionDirectory, model: .accurate)
        )

        XCTAssertEqual(result.text, "转写结果")
        XCTAssertEqual(result.transcriptURL, fixture.sessionDirectory.appendingPathComponent("transcript.txt"))
        XCTAssertEqual(runner.runs, [
            ProcessRun(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: [fixture.scriptURL.path, fixture.sessionDirectory.path],
                environment: [
                    "HOME": NSHomeDirectory(),
                    "PATH": "/usr/bin",
                    "PYTHONUNBUFFERED": "1",
                    "QWEN3_ASR_MODEL": "Qwen/Qwen3-ASR-1.7B"
                ],
                currentDirectoryURL: fixture.projectRoot
            )
        ])
    }

    func testPythonMLXServiceFailsBeforeRunningWhenMixedAudioIsMissing() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        let runner = FakeProcessRunner(result: ProcessResult(exitCode: 0, standardOutput: "", standardError: ""))
        let service = PythonMLXTranscriptionService(
            projectRoot: fixture.projectRoot,
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

    func testPythonMLXServiceReportsNonZeroExitOutput() async throws {
        let fixture = try TemporaryTranscriptionFixture()
        try "audio".write(to: fixture.sessionDirectory.appendingPathComponent("mixed.wav"), atomically: true, encoding: .utf8)
        let runner = FakeProcessRunner(
            result: ProcessResult(exitCode: 1, standardOutput: "stdout", standardError: "stderr")
        )
        let service = PythonMLXTranscriptionService(
            projectRoot: fixture.projectRoot,
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
        }
    }
}

private struct TemporaryTranscriptionFixture {
    let projectRoot: URL
    let scriptURL: URL
    let sessionDirectory: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("baby-recorder-transcription-\(UUID().uuidString)", isDirectory: true)
        projectRoot = root
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
