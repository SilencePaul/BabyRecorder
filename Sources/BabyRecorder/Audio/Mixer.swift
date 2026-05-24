import AVFoundation
import Foundation

struct MixResult: Equatable {
    let bytesWritten: Int64
}

enum MixerError: Error, Equatable {
    case missingInput(String)
    case unreadableInput(String)
}

struct Mixer {
    func mix(systemURL: URL, microphoneURL: URL, outputURL: URL) throws -> MixResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: systemURL.path) else {
            throw MixerError.missingInput(systemURL.path)
        }
        guard fileManager.fileExists(atPath: microphoneURL.path) else {
            throw MixerError.missingInput(microphoneURL.path)
        }

        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let systemFile = try openFile(at: systemURL)
        let microphoneFile = try openFile(at: microphoneURL)

        let systemBuffer = try readConverted(file: systemFile, outputFormat: outputFormat)
        let microphoneBuffer = try readConverted(file: microphoneFile, outputFormat: outputFormat)
        let frameCount = max(systemBuffer.frameLength, microphoneBuffer.frameLength)
        let mixedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)!
        mixedBuffer.frameLength = frameCount

        let channelCount = Int(outputFormat.channelCount)
        for channel in 0..<channelCount {
            let systemSamples = systemBuffer.floatChannelData![channel]
            let microphoneSamples = microphoneBuffer.floatChannelData![channel]
            let mixedSamples = mixedBuffer.floatChannelData![channel]

            for frame in 0..<Int(frameCount) {
                let systemSample = frame < Int(systemBuffer.frameLength) ? systemSamples[frame] : 0
                let microphoneSample = frame < Int(microphoneBuffer.frameLength) ? microphoneSamples[frame] : 0
                mixedSamples[frame] = min(1, max(-1, systemSample + microphoneSample))
            }
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        try outputFile.write(from: mixedBuffer)

        let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        let bytesWritten = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return MixResult(bytesWritten: bytesWritten)
    }

    private func openFile(at url: URL) throws -> AVAudioFile {
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            throw MixerError.unreadableInput(url.path)
        }
    }

    private func readConverted(file: AVAudioFile, outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let sourceFormat = file.processingFormat
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length))!
        do {
            try file.read(into: sourceBuffer)
        } catch {
            throw MixerError.unreadableInput(file.url.path)
        }

        guard sourceFormat != outputFormat else {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw MixerError.unreadableInput(file.url.path)
        }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1_024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            throw MixerError.unreadableInput(file.url.path)
        }

        do {
            try converter.convert(to: outputBuffer, from: sourceBuffer)
        } catch {
            throw MixerError.unreadableInput(file.url.path)
        }

        return outputBuffer
    }
}
