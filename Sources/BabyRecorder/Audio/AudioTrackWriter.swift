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
        if file == nil {
            file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        }
        try file?.write(from: buffer)
        let bytes = Int64(buffer.frameLength) * Int64(buffer.format.streamDescription.pointee.mBytesPerFrame)
        stats.recordBuffer(frames: Int64(buffer.frameLength), bytes: bytes, pts: pts)
    }

    func close() {
        file = nil
    }
}
