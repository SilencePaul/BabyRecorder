import AVFoundation
import CoreMedia
import Foundation

struct AudioTrackStats: Equatable {
    var path: String
    var bufferCount: Int = 0
    var framesWritten: Int64 = 0
    var bytesWritten: Int64 = 0
    var firstPTS: Double?
    var lastPTS: Double?

    mutating func recordBuffer(frames: Int64, bytes: Int64, pts: CMTime) {
        let seconds = pts.seconds
        bufferCount += 1
        framesWritten += frames
        bytesWritten += bytes
        if firstPTS == nil {
            firstPTS = seconds
        }
        lastPTS = seconds
    }

    func asDiagnostics() -> TrackDiagnostics {
        TrackDiagnostics(path: path, bufferCount: bufferCount, framesWritten: framesWritten, bytesWritten: bytesWritten, firstPTS: firstPTS, lastPTS: lastPTS)
    }
}

final class AudioTrackWriter {
    private let url: URL
    private var file: AVAudioFile?
    private(set) var stats: AudioTrackStats

    init(url: URL) {
        self.url = url
        self.stats = AudioTrackStats(path: url.lastPathComponent)
    }

    func write(buffer: AVAudioPCMBuffer, pts: CMTime) throws {
        let writableBuffer = try Self.fileWritableBuffer(from: buffer)
        if file == nil {
            file = try AVAudioFile(forWriting: url, settings: writableBuffer.format.settings)
        }
        try file?.write(from: writableBuffer)
        let bytes = Self.byteCount(for: writableBuffer)
        stats.recordBuffer(frames: Int64(writableBuffer.frameLength), bytes: bytes, pts: pts)
    }

    func close() {
        file = nil
    }

    private static func byteCount(for buffer: AVAudioPCMBuffer) -> Int64 {
        UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList).reduce(0) { total, audioBuffer in
            total + Int64(audioBuffer.mDataByteSize)
        }
    }

    private static func fileWritableBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format.isInterleaved else {
            return buffer
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: buffer.format.commonFormat,
            sampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ) else {
            throw AudioTrackWriterError.unsupportedInterleavedFormat
        }
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: buffer.frameLength) else {
            throw AudioTrackWriterError.unsupportedInterleavedFormat
        }
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let source = buffer.mutableAudioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self),
              let destinations = converted.floatChannelData else {
            throw AudioTrackWriterError.unsupportedInterleavedFormat
        }
        converted.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<Int(buffer.frameLength) {
            for channel in 0..<channelCount {
                destinations[channel][frame] = source[(frame * channelCount) + channel]
            }
        }
        return converted
    }
}

private enum AudioTrackWriterError: LocalizedError {
    case unsupportedInterleavedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedInterleavedFormat:
            "Interleaved PCM format could not be converted for WAV writing."
        }
    }
}
