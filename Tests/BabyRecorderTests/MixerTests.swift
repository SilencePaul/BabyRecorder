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
        try assertMixedOutputIs48kStereoAndAudible(out)
    }

    func testReportsMissingInput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("mixed.wav")
        let missingSystem = dir.appendingPathComponent("missing-a.wav")

        XCTAssertThrowsError(try Mixer().mix(systemURL: missingSystem, microphoneURL: dir.appendingPathComponent("missing-b.wav"), outputURL: out)) { error in
            XCTAssertEqual(error as? MixerError, .missingInput(missingSystem.path))
        }
    }

    func testResamples44100HzMonoInputsTo48000HzStereoOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a-44100.wav")
        let b = dir.appendingPathComponent("b-44100.wav")
        let out = dir.appendingPathComponent("mixed.wav")
        try TestAudio.writeSineWave(url: a, frequency: 440, duration: 0.1, sampleRate: 44_100)
        try TestAudio.writeSineWave(url: b, frequency: 660, duration: 0.1, sampleRate: 44_100)

        _ = try Mixer().mix(systemURL: a, microphoneURL: b, outputURL: out)

        try assertMixedOutputIs48kStereoAndAudible(out)
    }

    func testClipsSummedSamplesToOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.wav")
        let b = dir.appendingPathComponent("b.wav")
        let out = dir.appendingPathComponent("mixed.wav")
        try TestAudio.writeConstant(url: a, value: 0.75, duration: 0.1)
        try TestAudio.writeConstant(url: b, value: 0.75, duration: 0.1)

        _ = try Mixer().mix(systemURL: a, microphoneURL: b, outputURL: out)

        let buffer = try TestAudio.readPCM(url: out)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for index in 0..<Int(buffer.frameLength) {
                XCTAssertLessThanOrEqual(samples[index], 1.0)
                XCTAssertGreaterThanOrEqual(samples[index], -1.0)
            }
            XCTAssertEqual(samples[0], 1.0, accuracy: 0.0001)
        }
    }

    private func assertMixedOutputIs48kStereoAndAudible(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000, accuracy: 0.001)
        XCTAssertEqual(file.processingFormat.channelCount, 2)

        let buffer = try TestAudio.readPCM(url: url)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertTrue(TestAudio.allChannelsHaveNonSilentSamples(buffer))
    }
}

enum TestAudio {
    static func writeSineWave(url: URL, frequency: Double, duration: Double, sampleRate: Double = 48_000) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            samples[index] = Float(sin(2.0 * Double.pi * frequency * Double(index) / sampleRate) * 0.25)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func writeConstant(url: URL, value: Float, duration: Double, sampleRate: Double = 48_000) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            samples[index] = value
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func readPCM(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return buffer
    }

    static func allChannelsHaveNonSilentSamples(_ buffer: AVAudioPCMBuffer) -> Bool {
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            var channelHasNonSilentSample = false
            for index in 0..<Int(buffer.frameLength) where abs(samples[index]) > 0.0001 {
                channelHasNonSilentSample = true
                break
            }
            if !channelHasNonSilentSample {
                return false
            }
        }
        return buffer.format.channelCount > 0
    }
}
