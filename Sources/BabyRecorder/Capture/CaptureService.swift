import CoreMedia
import Foundation
import ScreenCaptureKit

final class CaptureService: NSObject, CaptureServicing, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var router: CaptureOutputRouter?
    private var paths: RecordingSessionPaths?
    private var diagnostics: SessionDiagnostics?
    private var systemWriter: AudioTrackWriter?
    private var micWriter: AudioTrackWriter?
    private let delegateErrorLock = NSLock()
    private var delegateStopErrors: [AppErrorRecord] = []
    private let mixer = Mixer()

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        let paths = try RecordingSessionPaths.create()
        self.paths = paths

        var diagnostics = SessionDiagnostics.newSession(outputDirectory: paths.outputDirectory, permissionSnapshot: permissionSnapshot)
        let systemWriter = AudioTrackWriter(url: paths.systemWav)
        let micWriter = AudioTrackWriter(url: paths.micWav)
        let router = CaptureOutputRouter(systemWriter: systemWriter, micWriter: micWriter)
        self.systemWriter = systemWriter
        self.micWriter = micWriter
        self.router = router
        self.diagnostics = diagnostics

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            diagnostics.errors.append(AppErrorRecord(.shareableContentFailed, message: error.localizedDescription))
            finishFailedStart(paths: paths, diagnostics: diagnostics, router: router, systemWriter: systemWriter, micWriter: micWriter)
            throw error
        }

        guard let display = content.displays.first else {
            let error = CaptureServiceError.mainDisplayUnavailable
            diagnostics.errors.append(AppErrorRecord(.mainDisplayUnavailable, message: error.localizedDescription))
            finishFailedStart(paths: paths, diagnostics: diagnostics, router: router, systemWriter: systemWriter, micWriter: micWriter)
            throw error
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(router, type: .audio, sampleHandlerQueue: router.sampleQueue)
            try stream.addStreamOutput(router, type: .microphone, sampleHandlerQueue: router.sampleQueue)
            self.stream = stream
            try await startCapture(stream)
        } catch {
            diagnostics.errors.append(AppErrorRecord(.streamStartFailed, message: error.localizedDescription))
            finishFailedStart(paths: paths, diagnostics: diagnostics, router: router, systemWriter: systemWriter, micWriter: micWriter)
            throw error
        }

        self.diagnostics = diagnostics
    }

    func stop() async throws -> RecordingCompletion {
        guard let stream, let paths, var diagnostics, let systemWriter, let micWriter else {
            throw CaptureServiceError.recordingNotActive
        }
        defer {
            clearState()
        }

        do {
            try await stopCapture(stream)
        } catch {
            diagnostics.errors.append(AppErrorRecord(.streamStopFailed, message: error.localizedDescription))
        }

        router?.drain()
        diagnostics.errors.append(contentsOf: takeDelegateStopErrors())
        if let writeFailures = router?.recordedWriteFailures {
            diagnostics.errors.append(contentsOf: writeFailures)
        }

        systemWriter.close()
        micWriter.close()
        diagnostics.tracks.system = systemWriter.stats.asDiagnostics()
        diagnostics.tracks.microphone = micWriter.stats.asDiagnostics()

        if diagnostics.tracks.system.bufferCount == 0 {
            diagnostics.errors.append(AppErrorRecord(.systemAudioNoBuffers, message: "No system audio sample buffers were written."))
        }
        if diagnostics.tracks.microphone.bufferCount == 0 {
            diagnostics.errors.append(AppErrorRecord(.microphoneNoBuffers, message: "No microphone sample buffers were written."))
        }

        var mixFailed = false
        do {
            let mix = try mixer.mix(systemURL: paths.systemWav, microphoneURL: paths.micWav, outputURL: paths.mixedWav)
            diagnostics.tracks.mixed.bytesWritten = mix.bytesWritten
        } catch {
            mixFailed = true
            diagnostics.errors.append(AppErrorRecord(.mixedWavWriteFailed, message: error.localizedDescription))
        }

        diagnostics.recording.endedAt = ISO8601DateFormatter().string(from: Date())
        diagnostics.recording.durationSeconds = Self.durationSeconds(
            startedAt: diagnostics.recording.startedAt,
            endedAt: diagnostics.recording.endedAt
        )
        diagnostics.validation = diagnostics.validationResult { fullPath in
            Self.fileExistsAndNonEmpty(atPath: fullPath)
        }

        if diagnostics.validation?.passed == false {
            diagnostics.errors.append(AppErrorRecord(.validationFailed, message: "Session validation failed."))
        }

        try diagnostics.write(to: paths.sessionJSON)
        let validation = diagnostics.validation!

        return RecordingCompletion(outputDirectory: paths.outputDirectory, validation: validation, mixFailed: mixFailed)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegateErrorLock.lock()
        delegateStopErrors.append(AppErrorRecord(.streamStopFailed, message: error.localizedDescription))
        delegateErrorLock.unlock()
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func clearState() {
        stream = nil
        router = nil
        paths = nil
        diagnostics = nil
        systemWriter = nil
        micWriter = nil
        _ = takeDelegateStopErrors()
    }

    private func finishFailedStart(
        paths: RecordingSessionPaths,
        diagnostics: SessionDiagnostics,
        router: CaptureOutputRouter,
        systemWriter: AudioTrackWriter,
        micWriter: AudioTrackWriter
    ) {
        router.drain()
        var diagnostics = diagnostics
        diagnostics.errors.append(contentsOf: router.recordedWriteFailures)
        diagnostics.tracks.system = systemWriter.stats.asDiagnostics()
        diagnostics.tracks.microphone = micWriter.stats.asDiagnostics()
        systemWriter.close()
        micWriter.close()
        diagnostics.recording.endedAt = ISO8601DateFormatter().string(from: Date())
        diagnostics.recording.durationSeconds = Self.durationSeconds(
            startedAt: diagnostics.recording.startedAt,
            endedAt: diagnostics.recording.endedAt
        )
        diagnostics.validation = diagnostics.validationResult { fullPath in
            Self.fileExistsAndNonEmpty(atPath: fullPath)
        }
        try? diagnostics.write(to: paths.sessionJSON)
        clearState()
    }

    private func takeDelegateStopErrors() -> [AppErrorRecord] {
        delegateErrorLock.lock()
        defer { delegateErrorLock.unlock() }

        let errors = delegateStopErrors
        delegateStopErrors.removeAll()
        return errors
    }

    private static func durationSeconds(startedAt: String, endedAt: String?) -> Double? {
        guard let endedAt,
              let start = ISO8601DateFormatter().date(from: startedAt),
              let end = ISO8601DateFormatter().date(from: endedAt) else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    private static func fileExistsAndNonEmpty(atPath path: String) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }
}

private enum CaptureServiceError: LocalizedError {
    case mainDisplayUnavailable
    case recordingNotActive

    var errorDescription: String? {
        switch self {
        case .mainDisplayUnavailable:
            "Main display unavailable"
        case .recordingNotActive:
            "Recording is not active"
        }
    }
}
