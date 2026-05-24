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
}
