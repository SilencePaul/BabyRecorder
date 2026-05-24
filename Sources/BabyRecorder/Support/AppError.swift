import Foundation

enum AppErrorCode: String, Codable, Equatable {
    case screenRecordingPermissionMissing
    case microphonePermissionMissing
    case shareableContentFailed
    case mainDisplayUnavailable
    case streamCreateFailed
    case streamStartFailed
    case streamStopFailed
    case systemAudioNoBuffers
    case microphoneNoBuffers
    case systemWavWriteFailed
    case microphoneWavWriteFailed
    case mixedWavWriteFailed
    case validationFailed
}

struct AppErrorRecord: Codable, Equatable {
    var code: AppErrorCode
    var message: String
    var context: [String: String]

    init(_ code: AppErrorCode, message: String, context: [String: String] = [:]) {
        self.code = code
        self.message = message
        self.context = context
    }
}
