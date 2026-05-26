import AVFoundation
import Foundation

struct AudioInputDevice: Equatable, Sendable {
    var uniqueID: String
    var localizedName: String
    var modelID: String
}

enum MicrophoneDeviceSelector {
    static func preferredDevice(from devices: [AudioInputDevice], defaultDeviceID: String?) -> AudioInputDevice? {
        let usableDevices = devices.filter(isUsableMicrophone)

        if let defaultDeviceID,
           let defaultDevice = usableDevices.first(where: { $0.uniqueID == defaultDeviceID }) {
            return defaultDevice
        }

        if let builtIn = usableDevices.first(where: isBuiltInMicrophone) {
            return builtIn
        }

        return usableDevices.first
    }

    private static func isUsableMicrophone(_ device: AudioInputDevice) -> Bool {
        let haystack = "\(device.uniqueID) \(device.localizedName) \(device.modelID)".lowercased()
        let rejectedTerms = [
            "blackhole",
            "aggregate",
            "meeting_output"
        ]
        return !rejectedTerms.contains { haystack.contains($0) }
    }

    private static func isBuiltInMicrophone(_ device: AudioInputDevice) -> Bool {
        let haystack = "\(device.uniqueID) \(device.localizedName) \(device.modelID)".lowercased()
        return haystack.contains("builtinmicrophonedevice")
            || haystack.contains("macbook")
            || haystack.contains("digital mic")
    }
}

struct SystemMicrophoneDeviceProvider {
    func preferredDevice() -> AudioInputDevice? {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = session.devices
            .filter(\.isConnected)
            .map {
                AudioInputDevice(
                    uniqueID: $0.uniqueID,
                    localizedName: $0.localizedName,
                    modelID: $0.modelID
                )
            }
        return MicrophoneDeviceSelector.preferredDevice(
            from: devices,
            defaultDeviceID: AVCaptureDevice.default(for: .audio)?.uniqueID
        )
    }
}
