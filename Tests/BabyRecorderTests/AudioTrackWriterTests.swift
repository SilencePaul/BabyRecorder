import AVFoundation
import CoreMedia
import XCTest
@testable import BabyRecorder

final class AudioTrackWriterTests: XCTestCase {
    func testRecordsBufferStats() {
        var stats = AudioTrackStats(path: "system.wav")
        stats.recordBuffer(frames: 480, bytes: 3840, pts: CMTime(seconds: 0.1, preferredTimescale: 48_000))
        stats.recordBuffer(frames: 960, bytes: 7680, pts: CMTime(seconds: 0.3, preferredTimescale: 48_000))

        XCTAssertEqual(stats.bufferCount, 2)
        XCTAssertEqual(stats.framesWritten, 1440)
        XCTAssertEqual(stats.bytesWritten, 11520)
        XCTAssertEqual(try XCTUnwrap(stats.firstPTS), 0.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.lastPTS), 0.3, accuracy: 0.001)
    }

    func testMapsStatsToDiagnostics() {
        var stats = AudioTrackStats(path: "mic.wav")
        stats.recordBuffer(frames: 128, bytes: 1024, pts: CMTime(seconds: 1.25, preferredTimescale: 48_000))

        let diagnostics = stats.asDiagnostics()

        XCTAssertEqual(diagnostics.path, "mic.wav")
        XCTAssertEqual(diagnostics.bufferCount, 1)
        XCTAssertEqual(diagnostics.framesWritten, 128)
        XCTAssertEqual(diagnostics.bytesWritten, 1024)
        XCTAssertEqual(try XCTUnwrap(diagnostics.firstPTS), 1.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(diagnostics.lastPTS), 1.25, accuracy: 0.001)
    }

    func testWriterRecordsNonInterleavedStereoBufferStats() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("system.wav")
        let frameCount: AVAudioFrameCount = 128
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frameCount) {
                samples[frame] = Float(channel + frame) / 1000.0
            }
        }

        let writer = AudioTrackWriter(url: url)
        try writer.write(buffer: buffer, pts: CMTime(seconds: 0.5, preferredTimescale: 48_000))
        writer.close()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0, 0)
        XCTAssertEqual(writer.stats.bufferCount, 1)
        XCTAssertEqual(writer.stats.framesWritten, Int64(frameCount))
        XCTAssertEqual(writer.stats.bytesWritten, 1024)
        XCTAssertEqual(try XCTUnwrap(writer.stats.firstPTS), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(writer.stats.lastPTS), 0.5, accuracy: 0.001)
    }

    func testFailedWriteLeavesStatsAtZero() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        buffer.frameLength = 16
        let writer = AudioTrackWriter(url: dir)

        XCTAssertThrowsError(try writer.write(buffer: buffer, pts: CMTime(seconds: 0.25, preferredTimescale: 48_000)))
        XCTAssertEqual(writer.stats.bufferCount, 0)
        XCTAssertEqual(writer.stats.framesWritten, 0)
        XCTAssertEqual(writer.stats.bytesWritten, 0)
        XCTAssertNil(writer.stats.firstPTS)
        XCTAssertNil(writer.stats.lastPTS)
    }
}
