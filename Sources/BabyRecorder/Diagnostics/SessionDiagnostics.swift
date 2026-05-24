import Foundation

struct PermissionSnapshot: Codable, Equatable, Sendable {
    var screenRecording: String
    var microphone: String
    var checkedAt: String

    static func grantedForTests() -> PermissionSnapshot {
        PermissionSnapshot(
            screenRecording: "granted",
            microphone: "granted",
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

struct CaptureConfigurationSnapshot: Codable, Equatable {
    var captureSource = "mainDisplay"
    var systemAudio = "ScreenCaptureKit.audio"
    var microphone = "ScreenCaptureKit.microphone.defaultInput"
    var sampleRate = 48000
    var channelCount = 2
    var excludesCurrentProcessAudio = true
}

struct TrackDiagnostics: Codable, Equatable {
    var path: String
    var bufferCount: Int = 0
    var framesWritten: Int64 = 0
    var bytesWritten: Int64 = 0
    var firstPTS: Double?
    var lastPTS: Double?
}

struct MixedTrackDiagnostics: Codable, Equatable {
    var path: String
    var bytesWritten: Int64 = 0
}

struct TrackGroupDiagnostics: Codable, Equatable {
    var system = TrackDiagnostics(path: "system.wav")
    var microphone = TrackDiagnostics(path: "mic.wav")
    var mixed = MixedTrackDiagnostics(path: "mixed.wav")
}

struct ValidationChecks: Codable, Equatable, Sendable {
    var systemFileNonEmpty: Bool
    var micFileNonEmpty: Bool
    var mixedFileNonEmpty: Bool
    var systemBuffersPresent: Bool
    var micBuffersPresent: Bool
}

struct ValidationResult: Codable, Equatable, Sendable {
    var passed: Bool
    var checks: ValidationChecks
}

struct SessionDiagnostics: Codable, Equatable {
    var sessionId: String
    var app: AppSnapshot
    var system: SystemSnapshot
    var permissions: PermissionSnapshot
    var recording: RecordingSnapshot
    var configuration: CaptureConfigurationSnapshot
    var tracks: TrackGroupDiagnostics
    var validation: ValidationResult?
    var errors: [AppErrorRecord]

    struct AppSnapshot: Codable, Equatable {
        var name: String
        var version: String
    }

    struct SystemSnapshot: Codable, Equatable {
        var macOS: String
        var machine: String
    }

    struct RecordingSnapshot: Codable, Equatable {
        var startedAt: String
        var endedAt: String?
        var durationSeconds: Double?
        var outputDirectory: String
    }

    static func newSession(
        outputDirectory: URL,
        permissionSnapshot: PermissionSnapshot,
        now: Date = Date()
    ) -> SessionDiagnostics {
        let sessionId = outputDirectory.lastPathComponent
        let startedAt = ISO8601DateFormatter().string(from: now)

        return SessionDiagnostics(
            sessionId: sessionId,
            app: AppSnapshot(name: AppInfo.name, version: AppInfo.version),
            system: SystemSnapshot(macOS: AppInfo.operatingSystemVersion, machine: AppInfo.machineName),
            permissions: permissionSnapshot,
            recording: RecordingSnapshot(
                startedAt: startedAt,
                endedAt: nil,
                durationSeconds: nil,
                outputDirectory: outputDirectory.path
            ),
            configuration: CaptureConfigurationSnapshot(),
            tracks: TrackGroupDiagnostics(),
            validation: nil,
            errors: []
        )
    }

    func validationResult(fileExistsAndNonEmpty: (String) -> Bool) -> ValidationResult {
        let outputDirectory = URL(fileURLWithPath: recording.outputDirectory, isDirectory: true)

        let checks = ValidationChecks(
            systemFileNonEmpty: fileExistsAndNonEmpty(outputDirectory.appendingPathComponent(tracks.system.path).path),
            micFileNonEmpty: fileExistsAndNonEmpty(outputDirectory.appendingPathComponent(tracks.microphone.path).path),
            mixedFileNonEmpty: fileExistsAndNonEmpty(outputDirectory.appendingPathComponent(tracks.mixed.path).path),
            systemBuffersPresent: tracks.system.bufferCount > 0,
            micBuffersPresent: tracks.microphone.bufferCount > 0
        )

        return ValidationResult(
            passed: checks.systemFileNonEmpty
                && checks.micFileNonEmpty
                && checks.mixedFileNonEmpty
                && checks.systemBuffersPresent
                && checks.micBuffersPresent,
            checks: checks
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
