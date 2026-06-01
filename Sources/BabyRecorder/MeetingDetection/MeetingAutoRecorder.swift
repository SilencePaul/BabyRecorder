import Foundation
import Observation

enum MeetingAutoRecordingStatus: Equatable, Sendable {
    case monitoring
    case recordingStarted(appName: String)
    case meetingMayHaveEnded(appName: String)
    case blockedByRecordingPermissions
    case windowMetadataUnavailable(appName: String)
}

@MainActor
@Observable
final class MeetingAutoRecorder {
    private let provider: MeetingApplicationProviding
    private let detector: MeetingDetector
    private let endSuggestionMissThreshold: Int
    private var autoStartedAppName: String?
    private var consecutiveMisses = 0

    private(set) var status: MeetingAutoRecordingStatus = .monitoring

    init(
        provider: MeetingApplicationProviding = SystemMeetingApplicationProvider(),
        detector: MeetingDetector = MeetingDetector(),
        endSuggestionMissThreshold: Int = 3
    ) {
        self.provider = provider
        self.detector = detector
        self.endSuggestionMissThreshold = endSuggestionMissThreshold
    }

    var shouldSuggestStop: Bool {
        if case .meetingMayHaveEnded = status {
            return true
        }
        return false
    }

    func tick(recordingViewModel: RecordingViewModel) async {
        if autoStartedAppName != nil, recordingViewModel.state != .recording {
            clearAutoStartedState()
        }

        let applications = await provider.runningApplications()
        let detection = detector.detect(from: applications)

        switch detection.status {
        case .inMeeting:
            consecutiveMisses = 0
            let appName = appName(from: detection)
            if recordingViewModel.canStartRecording {
                await recordingViewModel.startRecording()
                if recordingViewModel.state == .recording {
                    autoStartedAppName = appName
                    status = .recordingStarted(appName: appName)
                    observeAutoStartedRecordingState(recordingViewModel)
                } else {
                    clearAutoStartedState()
                }
            } else if recordingViewModel.state == .recording {
                if let autoStartedAppName {
                    status = .recordingStarted(appName: autoStartedAppName)
                } else {
                    status = .monitoring
                }
            } else if !recordingViewModel.permissionStatus.isReady {
                status = .blockedByRecordingPermissions
            } else {
                status = .monitoring
            }

        case .windowMetadataUnavailable:
            if recordingViewModel.state != .recording {
                status = .windowMetadataUnavailable(appName: appName(from: detection))
            }

        case .notInMeeting:
            guard let autoStartedAppName, recordingViewModel.state == .recording else {
                consecutiveMisses = 0
                status = .monitoring
                return
            }

            consecutiveMisses += 1
            if consecutiveMisses >= endSuggestionMissThreshold {
                status = .meetingMayHaveEnded(appName: autoStartedAppName)
            }
        }
    }

    func confirmStop(recordingViewModel: RecordingViewModel) async {
        guard shouldSuggestStop else {
            return
        }
        await recordingViewModel.stopRecording()
        clearAutoStartedState()
    }

    func clearAutoStartedState() {
        autoStartedAppName = nil
        consecutiveMisses = 0
        status = .monitoring
    }

    private func appName(from detection: MeetingDetectionSnapshot) -> String {
        detection.displayName ?? detection.app?.displayName ?? "未知会议应用"
    }

    private func observeAutoStartedRecordingState(_ recordingViewModel: RecordingViewModel) {
        withObservationTracking {
            _ = recordingViewModel.state
        } onChange: { [weak self, weak recordingViewModel] in
            Task { @MainActor in
                guard let self, let recordingViewModel, self.autoStartedAppName != nil else {
                    return
                }

                if recordingViewModel.state == .recording {
                    self.observeAutoStartedRecordingState(recordingViewModel)
                } else {
                    self.clearAutoStartedState()
                }
            }
        }
    }
}
