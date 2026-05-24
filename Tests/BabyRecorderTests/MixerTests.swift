import AVFoundation
import XCTest
@testable import BabyRecorder

final class MixerTests: XCTestCase {
    func testMixesTwoMonoFilesIntoNonEmptyOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.wav")
        let b = dir.appendingPathComponent("b.wav")
        let out = dir.appendingPathComponent("mixed.wav")
        try TestAudio.writeSineWave(url: a, frequency: 440, duration: 0.1)
        try TestAudio.writeSineWave(url: b, frequency: 660, duration: 0.1)

        let result = try Mixer().mix(systemURL: a, microphoneURL: b, outputURL: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertGreaterThan(result.bytesWritten, 44)
    }

    func testReportsMissingInput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("mixed.wav")

        XCTAssertThrowsError(try Mixer().mix(systemURL: dir.appendingPathComponent("missing-a.wav"), microphoneURL: dir.appendingPathComponent("missing-b.wav"), outputURL: out))
    }
}

enum TestAudio {
    static func writeSineWave(url: URL, frequency: Double, duration: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frameCount = AVAudioFrameCount(48_000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            samples[index] = Float(sin(2.0 * Double.pi * frequency * Double(index) / 48_000.0) * 0.25)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
