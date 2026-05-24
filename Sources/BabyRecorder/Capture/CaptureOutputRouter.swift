import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class CaptureOutputRouter: NSObject, SCStreamOutput {
    private let systemWriter: AudioTrackWriter
    private let micWriter: AudioTrackWriter
    private var writeFailures: [AppErrorRecord] = []

    let sampleQueue = DispatchQueue(label: "BabyRecorder.CaptureOutputRouter")

    init(systemWriter: AudioTrackWriter, micWriter: AudioTrackWriter) {
        self.systemWriter = systemWriter
        self.micWriter = micWriter
    }

    var recordedWriteFailures: [AppErrorRecord] {
        sampleQueue.sync {
            writeFailures
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            recordWriteFailure(CaptureOutputRouterError.invalidSampleBuffer, outputType: outputType)
            return
        }

        do {
            let pcm = try Self.makePCMBuffer(from: sampleBuffer)
            let pts = sampleBuffer.presentationTimeStamp
            switch outputType {
            case .audio:
                try systemWriter.write(buffer: pcm, pts: pts)
            case .microphone:
                try micWriter.write(buffer: pcm, pts: pts)
            default:
                break
            }
        } catch {
            recordWriteFailure(error, outputType: outputType)
        }
    }

    func drain() {
        sampleQueue.sync {}
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard sampleBuffer.isValid else {
            throw CaptureOutputRouterError.invalidSampleBuffer
        }
        guard let formatDescription = sampleBuffer.formatDescription else {
            throw CaptureOutputRouterError.missingFormatDescription
        }
        guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            throw CaptureOutputRouterError.invalidAudioFormat
        }
        guard sampleBuffer.numSamples > 0 else {
            throw CaptureOutputRouterError.emptySampleBuffer
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CaptureOutputRouterError.invalidAudioFormat
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

private extension CMSampleBuffer {
    func copyPCMData(into pcm: AVAudioPCMBuffer) throws {
        try withAudioBufferList { audioBufferList, blockBuffer in
            guard CMBlockBufferGetDataLength(blockBuffer) > 0 else {
                throw CaptureOutputRouterError.missingAudioData
            }

            let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            guard audioBufferList.count == destinationBuffers.count else {
                throw CaptureOutputRouterError.bufferCountMismatch(source: audioBufferList.count, destination: destinationBuffers.count)
            }

            for index in 0..<audioBufferList.count {
                let sourceBuffer = audioBufferList[index]
                let destinationBuffer = destinationBuffers[index]
                guard sourceBuffer.mDataByteSize == destinationBuffer.mDataByteSize else {
                    throw CaptureOutputRouterError.byteCountMismatch(
                        bufferIndex: index,
                        source: sourceBuffer.mDataByteSize,
                        destination: destinationBuffer.mDataByteSize
                    )
                }
                guard sourceBuffer.mDataByteSize == 0 || (sourceBuffer.mData != nil && destinationBuffer.mData != nil) else {
                    throw CaptureOutputRouterError.missingAudioData
                }
                if let source = sourceBuffer.mData, let destination = destinationBuffer.mData, sourceBuffer.mDataByteSize > 0 {
                    memcpy(destination, source, Int(sourceBuffer.mDataByteSize))
                }
            }
        }
    }
}

private enum CaptureOutputRouterError: LocalizedError {
    case invalidSampleBuffer
    case missingFormatDescription
    case invalidAudioFormat
    case emptySampleBuffer
    case bufferCountMismatch(source: Int, destination: Int)
    case byteCountMismatch(bufferIndex: Int, source: UInt32, destination: UInt32)
    case missingAudioData

    var errorDescription: String? {
        switch self {
        case .invalidSampleBuffer:
            "Sample buffer was invalid."
        case .missingFormatDescription:
            "Sample buffer was missing an audio format description."
        case .invalidAudioFormat:
            "Sample buffer audio format was invalid."
        case .emptySampleBuffer:
            "Sample buffer did not contain audio frames."
        case .bufferCountMismatch(let source, let destination):
            "Sample buffer has \(source) audio buffers, but PCM destination has \(destination)."
        case .byteCountMismatch(let bufferIndex, let source, let destination):
            "Sample buffer audio buffer \(bufferIndex) has \(source) bytes, but PCM destination has \(destination)."
        case .missingAudioData:
            "Sample buffer audio data was missing."
        }
    }
}
