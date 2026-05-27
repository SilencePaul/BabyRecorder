import XCTest
@testable import BabyRecorder

final class SessionDiagnosticsTests: XCTestCase {
    func testValidationFailsWhenFilesMissingAndBuffersAreZero() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())

        let result = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in false })

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.checks.systemFileNonEmpty)
        XCTAssertFalse(result.checks.micFileNonEmpty)
        XCTAssertFalse(result.checks.mixedFileNonEmpty)
        XCTAssertFalse(result.checks.systemBuffersPresent)
        XCTAssertFalse(result.checks.micBuffersPresent)
    }

    func testValidationPassesWithNonEmptyFilesAndBuffers() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())
        diagnostics.tracks.system.bufferCount = 2
        diagnostics.tracks.microphone.bufferCount = 3

        let result = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in true })

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checks.systemFileNonEmpty)
        XCTAssertTrue(result.checks.micFileNonEmpty)
        XCTAssertTrue(result.checks.mixedFileNonEmpty)
        XCTAssertTrue(result.checks.systemBuffersPresent)
        XCTAssertTrue(result.checks.micBuffersPresent)
    }

    func testWritesRequiredJSONFields() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        var diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())
        diagnostics.tracks.system.bufferCount = 1
        diagnostics.tracks.microphone.bufferCount = 1
        diagnostics.tracks.mixed.systemGainDb = -1.5
        diagnostics.tracks.mixed.microphoneGainDb = 8.25
        diagnostics.validation = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in true })

        let url = temp.appendingPathComponent("session.json")
        try diagnostics.write(to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(decoded?["sessionId"] as? String, diagnostics.sessionId)
        XCTAssertNotNil(decoded?["permissions"])
        XCTAssertNotNil(decoded?["configuration"])
        let transcription = try XCTUnwrap(decoded?["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["engine"] as? String, "whisper.cpp")
        XCTAssertEqual(transcription["inputTrack"] as? String, "mixed.wav")
        XCTAssertEqual(transcription["modelDirectory"] as? String, "/Users/yimingliu/Desktop/宝宝录音App/Models")
        XCTAssertEqual(transcription["modelStatus"] as? String, "modelMissing")
        XCTAssertEqual(transcription["transcriptPath"] as? String, "transcript.json")
        let tracks = try XCTUnwrap(decoded?["tracks"] as? [String: Any])
        let mixed = try XCTUnwrap(tracks["mixed"] as? [String: Any])
        XCTAssertEqual(mixed["systemGainDb"] as? Double, -1.5)
        XCTAssertEqual(mixed["microphoneGainDb"] as? Double, 8.25)
        XCTAssertNotNil(decoded?["validation"])
        XCTAssertNotNil(decoded?["errors"])
    }

    func testValidationChecksFullPathsInsideOutputDirectory() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())
        var checkedPaths: [String] = []

        _ = diagnostics.validationResult { path in
            checkedPaths.append(path)
            return true
        }

        XCTAssertEqual(checkedPaths, [
            temp.appendingPathComponent("system.wav").path,
            temp.appendingPathComponent("mic.wav").path,
            temp.appendingPathComponent("mixed.wav").path
        ])
        XCTAssertEqual(diagnostics.tracks.system.path, "system.wav")
        XCTAssertEqual(diagnostics.tracks.microphone.path, "mic.wav")
        XCTAssertEqual(diagnostics.tracks.mixed.path, "mixed.wav")
    }

    func testRecordingSessionPathsCreateFormatsTimestampAndCreatesFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 24,
            hour: 15,
            minute: 30,
            second: 45
        ).date!

        let paths = try RecordingSessionPaths.create(baseDirectory: base, now: now, calendar: calendar)

        XCTAssertEqual(paths.sessionId, "2026-05-24_15-30-45")
        XCTAssertEqual(paths.outputDirectory, base.appendingPathComponent("2026-05-24_15-30-45", isDirectory: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.outputDirectory.path))
        XCTAssertEqual(paths.systemWav.lastPathComponent, "system.wav")
        XCTAssertEqual(paths.micWav.lastPathComponent, "mic.wav")
        XCTAssertEqual(paths.mixedWav.lastPathComponent, "mixed.wav")
        XCTAssertEqual(paths.sessionJSON.lastPathComponent, "session.json")
    }

    func testRecordingSessionPathsDefaultBaseDirectoryIsUserWritableAppSupport() {
        let base = RecordingSessionPaths.defaultBaseDirectory()

        XCTAssertEqual(
            base,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/BabyRecorder/Recordings", isDirectory: true)
        )
        XCTAssertFalse(base.path.contains("/Desktop/宝宝录音App/Recordings"))
    }

    func testTranscriptionModelStatusIsReadyWhenModelFileExists() throws {
        let modelDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data().write(to: modelDirectory.appendingPathComponent("ggml-base.bin"))

        let transcription = TranscriptionConfigurationSnapshot(modelDirectory: modelDirectory)

        XCTAssertEqual(transcription.modelStatus, "ready")
    }
}
