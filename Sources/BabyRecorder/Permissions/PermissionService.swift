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

struct PermissionService: PermissionServicing {
    func checkPermissions() async -> PermissionStatus {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let screen = CGPreflightScreenCaptureAccess()
        return PermissionStatus(screenRecordingGranted: screen, microphoneGranted: mic)
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }
}
