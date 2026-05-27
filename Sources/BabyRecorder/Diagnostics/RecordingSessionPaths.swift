import Foundation

struct RecordingSessionPaths: Equatable {
    let sessionId: String
    let outputDirectory: URL
    let systemWav: URL
    let micWav: URL
    let mixedWav: URL
    let sessionJSON: URL

    static func create(
        baseDirectory: URL = Self.defaultBaseDirectory(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> RecordingSessionPaths {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let sessionId = formatter.string(from: now)
        let directory = baseDirectory.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return RecordingSessionPaths(
            sessionId: sessionId,
            outputDirectory: directory,
            systemWav: directory.appendingPathComponent("system.wav"),
            micWav: directory.appendingPathComponent("mic.wav"),
            mixedWav: directory.appendingPathComponent("mixed.wav"),
            sessionJSON: directory.appendingPathComponent("session.json")
        )
    }

    static func defaultBaseDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BabyRecorder/Recordings", isDirectory: true)
    }
}
