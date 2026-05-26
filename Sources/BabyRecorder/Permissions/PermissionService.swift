import AppKit
import AVFoundation
import Foundation

struct PermissionStatus: Equatable, Sendable {
    var screenRecordingGranted: Bool
    var microphoneGranted: Bool

    var isReady: Bool {
        screenRecordingGranted && microphoneGranted
    }

    var snapshot: PermissionSnapshot {
        PermissionSnapshot(
            screenRecording: screenRecordingGranted ? "granted" : "missing",
            microphone: microphoneGranted ? "granted" : "missing",
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

protocol PermissionServicing: Sendable {
    func checkPermissions() async -> PermissionStatus
    func openSystemSettings()
}

protocol MicrophonePermissionAuthorizing: Sendable {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess() async -> Bool
}

struct SystemMicrophonePermissionAuthorizer: MicrophonePermissionAuthorizing {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

struct PermissionService: PermissionServicing {
    private let screenRecordingGranted: @Sendable () -> Bool
    private let microphoneAuthorizer: any MicrophonePermissionAuthorizing
    private let openSettings: @Sendable () -> Void

    init(
        screenRecordingGranted: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
        microphoneAuthorizer: any MicrophonePermissionAuthorizing = SystemMicrophonePermissionAuthorizer(),
        openSettings: @escaping @Sendable () -> Void = {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
            NSWorkspace.shared.open(url)
        }
    ) {
        self.screenRecordingGranted = screenRecordingGranted
        self.microphoneAuthorizer = microphoneAuthorizer
        self.openSettings = openSettings
    }

    func checkPermissions() async -> PermissionStatus {
        let mic: Bool
        switch microphoneAuthorizer.authorizationStatus() {
        case .authorized:
            mic = true
        case .notDetermined:
            mic = await microphoneAuthorizer.requestAccess()
        case .denied, .restricted:
            mic = false
        @unknown default:
            mic = false
        }

        let screen = screenRecordingGranted()
        return PermissionStatus(screenRecordingGranted: screen, microphoneGranted: mic)
    }

    func openSystemSettings() {
        openSettings()
    }
}
