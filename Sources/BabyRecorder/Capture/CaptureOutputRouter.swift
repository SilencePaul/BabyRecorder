import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class CaptureOutputRouter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let systemWriter: AudioTrackWriter
    private let micWriter: AudioTrackWriter
    private let queue = DispatchQueue(label: "BabyRecorder.CaptureOutputRouter")
    private var writeFailures: [AppErrorRecord] = []

    init(systemWriter: AudioTrackWriter, micWriter: AudioTrackWriter) {
        self.systemWriter = systemWriter
        self.micWriter = micWriter
    }

    var recordedWriteFailures: [AppErrorRecord] {
        queue.sync {
            writeFailures
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }

        let routedBuffer: RoutedAudioBuffer
        do {
            guard let pcm = try Self.makePCMBuffer(from: sampleBuffer) else {
                return
            }
            routedBuffer = RoutedAudioBuffer(pcm: pcm, pts: sampleBuffer.presentationTimeStamp, outputType: outputType)
        } catch {
            queue.async {
                self.recordWriteFailure(error, outputType: outputType)
            }
            return
        }

        queue.async {
            do {
                switch routedBuffer.outputType {
                case .audio:
                    try self.systemWriter.write(buffer: routedBuffer.pcm, pts: routedBuffer.pts)
                case .microphone:
                    try self.micWriter.write(buffer: routedBuffer.pcm, pts: routedBuffer.pts)
                default:
                    break
                }
            } catch {
                self.recordWriteFailure(error, outputType: routedBuffer.outputType)
            }
        }
    }

    func drain() {
        queue.sync {}
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        pcm.frameLength = frameCount
        try sampleBuffer.copyPCMData(into: pcm)
        return pcm
    }

    private func recordWriteFailure(_ error: Error, outputType: SCStreamOutputType) {
        let code: AppErrorCode
        switch outputType {
        case .audio:
            code = .systemWavWriteFailed
        case .microphone:
            code = .microphoneWavWriteFailed
        default:
            return
        }

        writeFailures.append(
            AppErrorRecord(
                code,
                message: error.localizedDescription,
                context: ["outputType": String(describing: outputType)]
            )
        )
    }
}

private struct RoutedAudioBuffer: @unchecked Sendable {
    let pcm: AVAudioPCMBuffer
    let pts: CMTime
    let outputType: SCStreamOutputType
}

private extension CMSampleBuffer {
    func copyPCMData(into pcm: AVAudioPCMBuffer) throws {
        try withAudioBufferList { audioBufferList, _ in
            let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            guard audioBufferList.count <= destinationBuffers.count else {
                throw CaptureOutputRouterError.bufferCountMismatch(source: audioBufferList.count, destination: destinationBuffers.count)
            }

            for index in 0..<audioBufferList.count {
                let sourceBuffer = audioBufferList[index]
                let destinationBuffer = destinationBuffers[index]
                let bytes = min(sourceBuffer.mDataByteSize, destinationBuffer.mDataByteSize)
                guard bytes == 0 || (sourceBuffer.mData != nil && destinationBuffer.mData != nil) else {
                    throw CaptureOutputRouterError.missingAudioData
                }
                if let source = sourceBuffer.mData, let destination = destinationBuffer.mData, bytes > 0 {
                    memcpy(destination, source, Int(bytes))
                }
            }
        }
    }
}

private enum CaptureOutputRouterError: LocalizedError {
    case bufferCountMismatch(source: Int, destination: Int)
    case missingAudioData

    var errorDescription: String? {
        switch self {
        case .bufferCountMismatch(let source, let destination):
            "Sample buffer has \(source) audio buffers, but PCM destination has \(destination)."
        case .missingAudioData:
            "Sample buffer audio data was missing."
        }
    }
}
