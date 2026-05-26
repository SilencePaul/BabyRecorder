import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

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

protocol ScreenRecordingPermissionAuthorizing: Sendable {
    func isGranted() async -> Bool
}

struct ScreenCaptureKitPermissionAuthorizer: ScreenRecordingPermissionAuthorizing {
    func isGranted() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
}

private struct ClosureScreenRecordingPermissionAuthorizer: ScreenRecordingPermissionAuthorizing {
    private let isGrantedClosure: @Sendable () -> Bool

    init(_ isGrantedClosure: @escaping @Sendable () -> Bool) {
        self.isGrantedClosure = isGrantedClosure
    }

    func isGranted() async -> Bool {
        isGrantedClosure()
    }
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
    private let screenRecordingAuthorizer: any ScreenRecordingPermissionAuthorizing
    private let microphoneAuthorizer: any MicrophonePermissionAuthorizing
    private let openSettings: @Sendable () -> Void

    init(
        screenRecordingAuthorizer: any ScreenRecordingPermissionAuthorizing = ScreenCaptureKitPermissionAuthorizer(),
        microphoneAuthorizer: any MicrophonePermissionAuthorizing = SystemMicrophonePermissionAuthorizer(),
        openSettings: @escaping @Sendable () -> Void = {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
            NSWorkspace.shared.open(url)
        }
    ) {
        self.screenRecordingAuthorizer = screenRecordingAuthorizer
        self.microphoneAuthorizer = microphoneAuthorizer
        self.openSettings = openSettings
    }

    init(
        screenRecordingGranted: @escaping @Sendable () -> Bool,
        microphoneAuthorizer: any MicrophonePermissionAuthorizing = SystemMicrophonePermissionAuthorizer(),
        openSettings: @escaping @Sendable () -> Void = {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
            NSWorkspace.shared.open(url)
        }
    ) {
        self.init(
            screenRecordingAuthorizer: ClosureScreenRecordingPermissionAuthorizer(screenRecordingGranted),
            microphoneAuthorizer: microphoneAuthorizer,
            openSettings: openSettings
        )
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

        let screen = await screenRecordingAuthorizer.isGranted()
        return PermissionStatus(screenRecordingGranted: screen, microphoneGranted: mic)
    }

    func openSystemSettings() {
        openSettings()
    }
}
