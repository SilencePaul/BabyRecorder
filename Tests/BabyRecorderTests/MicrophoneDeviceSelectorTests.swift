import XCTest
@testable import BabyRecorder

final class MicrophoneDeviceSelectorTests: XCTestCase {
    func testPrefersDefaultDeviceWhenItIsRealMicrophone() {
        let airPods = AudioInputDevice(
            uniqueID: "airpods-mic",
            localizedName: "Yiming's AirPods Pro",
            modelID: "AirPods"
        )
        let builtIn = AudioInputDevice(
            uniqueID: "BuiltInMicrophoneDevice",
            localizedName: "MacBook Air Microphone",
            modelID: "Digital Mic"
        )

        let selected = MicrophoneDeviceSelector.preferredDevice(from: [builtIn, airPods], defaultDeviceID: airPods.uniqueID)

        XCTAssertEqual(selected, airPods)
    }

    func testPrefersDefaultExternalMicrophoneForWiredHeadset() {
        let headphoneInput = AudioInputDevice(
            uniqueID: "BuiltInHeadphoneInputDevice",
            localizedName: "External Microphone",
            modelID: "Codec Input"
        )
        let builtIn = AudioInputDevice(
            uniqueID: "BuiltInMicrophoneDevice",
            localizedName: "MacBook Air Microphone",
            modelID: "Digital Mic"
        )

        let selected = MicrophoneDeviceSelector.preferredDevice(from: [headphoneInput, builtIn], defaultDeviceID: headphoneInput.uniqueID)

        XCTAssertEqual(selected, headphoneInput)
    }

    func testSkipsAggregateAndVirtualDevicesBeforeBuiltInMicrophone() {
        let aggregate = AudioInputDevice(
            uniqueID: "~:AMS2_Aggregate:0",
            localizedName: "Meeting_Input",
            modelID: ""
        )
        let blackHole = AudioInputDevice(
            uniqueID: "BlackHole2ch_UID",
            localizedName: "BlackHole 2ch",
            modelID: "BlackHole2ch_ModelUID"
        )
        let builtIn = AudioInputDevice(
            uniqueID: "BuiltInMicrophoneDevice",
            localizedName: "MacBook Air Microphone",
            modelID: "Digital Mic"
        )

        let selected = MicrophoneDeviceSelector.preferredDevice(
            from: [aggregate, blackHole, builtIn],
            defaultDeviceID: aggregate.uniqueID
        )

        XCTAssertEqual(selected, builtIn)
    }
}
