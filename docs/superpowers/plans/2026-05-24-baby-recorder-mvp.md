# Baby Recorder MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS MVP that captures system audio and default microphone audio through one ScreenCaptureKit pipeline, writes `system.wav`, `mic.wav`, `mixed.wav`, and emits `session.json` diagnostics.

**Architecture:** Use a Swift Package with a SwiftUI/AppKit executable target so core logic can be tested with `swift test`, then package the executable into a signed `.app` bundle for real permission testing. ScreenCaptureKit is the only realtime capture source; mixing runs offline after recording stops.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, CoreMedia, XCTest, shell packaging script.

---

## File Structure

- `Package.swift`: Swift package definition for the app and tests.
- `Sources/BabyRecorder/BabyRecorderApp.swift`: SwiftUI app entry point.
- `Sources/BabyRecorder/UI/ContentView.swift`: Minimal recording window.
- `Sources/BabyRecorder/UI/RecordingViewModel.swift`: UI state machine and user actions.
- `Sources/BabyRecorder/Permissions/PermissionService.swift`: Startup permission readiness checks and System Settings deep links.
- `Sources/BabyRecorder/Capture/CaptureService.swift`: ScreenCaptureKit stream lifecycle.
- `Sources/BabyRecorder/Capture/CaptureOutputRouter.swift`: Routes `.audio` and `.microphone` sample buffers.
- `Sources/BabyRecorder/Audio/AudioTrackWriter.swift`: Writes one WAV track and records stats.
- `Sources/BabyRecorder/Audio/Mixer.swift`: Offline creation of `mixed.wav`.
- `Sources/BabyRecorder/Diagnostics/SessionDiagnostics.swift`: Diagnostic models, JSON writing, validation.
- `Sources/BabyRecorder/Diagnostics/RecordingSessionPaths.swift`: Timestamped output directories.
- `Sources/BabyRecorder/Support/AppError.swift`: Error codes from the spec.
- `Sources/BabyRecorder/Support/AppInfo.swift`: Version and environment helpers.
- `Tests/BabyRecorderTests/SessionDiagnosticsTests.swift`: JSON and validation tests.
- `Tests/BabyRecorderTests/MixerTests.swift`: Offline mixer tests.
- `Tests/BabyRecorderTests/AudioTrackWriterTests.swift`: Track stats tests.
- `Tests/BabyRecorderTests/RecordingViewModelTests.swift`: UI state tests with fakes.
- `Scripts/package_app.sh`: Builds and signs `BabyRecorder.app`.
- `Info.plist`: App bundle privacy usage descriptions.

## Task 1: Swift Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/BabyRecorder/BabyRecorderApp.swift`
- Create: `Sources/BabyRecorder/UI/ContentView.swift`
- Create: `Tests/BabyRecorderTests/SmokeTests.swift`

- [ ] **Step 1: Write package and smoke test**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BabyRecorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "BabyRecorder", targets: ["BabyRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "BabyRecorder",
            path: "Sources/BabyRecorder",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "BabyRecorderTests",
            dependencies: ["BabyRecorder"],
            path: "Tests/BabyRecorderTests"
        )
    ]
)
```

Create `Sources/BabyRecorder/BabyRecorderApp.swift`:

```swift
import SwiftUI

@main
struct BabyRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 520, height: 360)
        }
        .windowStyle(.titleBar)
    }
}
```

Create `Sources/BabyRecorder/UI/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Baby Recorder")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Preparing MVP...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}
```

Create `Tests/BabyRecorderTests/SmokeTests.swift`:

```swift
import XCTest
@testable import BabyRecorder

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual("BabyRecorder", AppInfo.name)
    }
}
```

- [ ] **Step 2: Add minimal `AppInfo` used by the smoke test**

Create `Sources/BabyRecorder/Support/AppInfo.swift`:

```swift
import Foundation

enum AppInfo {
    static let name = "BabyRecorder"
    static let version = "0.1.0"

    static var operatingSystemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    static var machineName: String {
        Host.current().localizedName ?? "Mac"
    }
}
```

- [ ] **Step 3: Run tests**

Run:

```bash
swift test
```

Expected: build succeeds and `SmokeTests.testSmoke` passes.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold Swift package app"
```

## Task 2: Diagnostics Models and Validation

**Files:**
- Create: `Sources/BabyRecorder/Support/AppError.swift`
- Create: `Sources/BabyRecorder/Diagnostics/SessionDiagnostics.swift`
- Create: `Sources/BabyRecorder/Diagnostics/RecordingSessionPaths.swift`
- Create: `Tests/BabyRecorderTests/SessionDiagnosticsTests.swift`

- [ ] **Step 1: Write failing diagnostics tests**

Create `Tests/BabyRecorderTests/SessionDiagnosticsTests.swift`:

```swift
import XCTest
@testable import BabyRecorder

final class SessionDiagnosticsTests: XCTestCase {
    func testValidationFailsWhenFilesMissingAndBuffersAreZero() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())

        let result = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in false })

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.checks.systemFileNonEmpty)
        XCTAssertFalse(result.checks.micFileNonEmpty)
        XCTAssertFalse(result.checks.mixedFileNonEmpty)
        XCTAssertFalse(result.checks.systemBuffersPresent)
        XCTAssertFalse(result.checks.micBuffersPresent)
    }

    func testValidationPassesWithNonEmptyFilesAndBuffers() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())
        diagnostics.tracks.system.bufferCount = 2
        diagnostics.tracks.microphone.bufferCount = 3

        let result = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in true })

        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.checks.systemFileNonEmpty)
        XCTAssertTrue(result.checks.micFileNonEmpty)
        XCTAssertTrue(result.checks.mixedFileNonEmpty)
        XCTAssertTrue(result.checks.systemBuffersPresent)
        XCTAssertTrue(result.checks.micBuffersPresent)
    }

    func testWritesRequiredJSONFields() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        var diagnostics = SessionDiagnostics.newSession(outputDirectory: temp, permissionSnapshot: .grantedForTests())
        diagnostics.tracks.system.bufferCount = 1
        diagnostics.tracks.microphone.bufferCount = 1
        diagnostics.validation = diagnostics.validationResult(fileExistsAndNonEmpty: { _ in true })

        let url = temp.appendingPathComponent("session.json")
        try diagnostics.write(to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(decoded?["sessionId"] as? String, diagnostics.sessionId)
        XCTAssertNotNil(decoded?["permissions"])
        XCTAssertNotNil(decoded?["configuration"])
        XCTAssertNotNil(decoded?["tracks"])
        XCTAssertNotNil(decoded?["validation"])
        XCTAssertNotNil(decoded?["errors"])
    }
}
```

- [ ] **Step 2: Run diagnostics tests and confirm failure**

Run:

```bash
swift test --filter SessionDiagnosticsTests
```

Expected: FAIL because `SessionDiagnostics`, `PermissionSnapshot`, and related models do not exist yet.

- [ ] **Step 3: Implement error codes and diagnostics**

Create `Sources/BabyRecorder/Support/AppError.swift`:

```swift
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
```

Create `Sources/BabyRecorder/Diagnostics/RecordingSessionPaths.swift`:

```swift
import Foundation

struct RecordingSessionPaths: Equatable {
    let sessionId: String
    let outputDirectory: URL
    let systemWav: URL
    let micWav: URL
    let mixedWav: URL
    let sessionJSON: URL

    static func create(baseDirectory: URL = URL(fileURLWithPath: "/Users/yimingliu/Desktop/宝宝录音App/Recordings"),
                       now: Date = Date(),
                       calendar: Calendar = .current) throws -> RecordingSessionPaths {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let sessionId = formatter.string(from: now)
        let directory = baseDirectory.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return RecordingSessionPaths(
            sessionId: sessionId,
            outputDirectory: directory,
            systemWav: directory.appendingPathComponent("system.wav"),
            micWav: directory.appendingPathComponent("mic.wav"),
            mixedWav: directory.appendingPathComponent("mixed.wav"),
            sessionJSON: directory.appendingPathComponent("session.json")
        )
    }
}
```

Create `Sources/BabyRecorder/Diagnostics/SessionDiagnostics.swift`:

```swift
import Foundation

struct PermissionSnapshot: Codable, Equatable {
    var screenRecording: String
    var microphone: String
    var checkedAt: String

    static func grantedForTests() -> PermissionSnapshot {
        PermissionSnapshot(screenRecording: "granted", microphone: "granted", checkedAt: ISO8601DateFormatter().string(from: Date()))
    }
}

struct CaptureConfigurationSnapshot: Codable, Equatable {
    var captureSource = "mainDisplay"
    var systemAudio = "ScreenCaptureKit.audio"
    var microphone = "ScreenCaptureKit.microphone.defaultInput"
    var sampleRate = 48000
    var channelCount = 2
    var excludesCurrentProcessAudio = true
}

struct TrackDiagnostics: Codable, Equatable {
    var path: String
    var bufferCount: Int = 0
    var framesWritten: Int64 = 0
    var bytesWritten: Int64 = 0
    var firstPTS: Double?
    var lastPTS: Double?
}

struct MixedTrackDiagnostics: Codable, Equatable {
    var path: String
    var bytesWritten: Int64 = 0
}

struct TrackGroupDiagnostics: Codable, Equatable {
    var system = TrackDiagnostics(path: "system.wav")
    var microphone = TrackDiagnostics(path: "mic.wav")
    var mixed = MixedTrackDiagnostics(path: "mixed.wav")
}

struct ValidationChecks: Codable, Equatable {
    var systemFileNonEmpty: Bool
    var micFileNonEmpty: Bool
    var mixedFileNonEmpty: Bool
    var systemBuffersPresent: Bool
    var micBuffersPresent: Bool
}

struct ValidationResult: Codable, Equatable {
    var passed: Bool
    var checks: ValidationChecks
}

struct SessionDiagnostics: Codable, Equatable {
    var sessionId: String
    var app: AppSnapshot
    var system: SystemSnapshot
    var permissions: PermissionSnapshot
    var recording: RecordingSnapshot
    var configuration: CaptureConfigurationSnapshot
    var tracks: TrackGroupDiagnostics
    var validation: ValidationResult?
    var errors: [AppErrorRecord]

    struct AppSnapshot: Codable, Equatable {
        var name: String
        var version: String
    }

    struct SystemSnapshot: Codable, Equatable {
        var macOS: String
        var machine: String
    }

    struct RecordingSnapshot: Codable, Equatable {
        var startedAt: String
        var endedAt: String?
        var durationSeconds: Double?
        var outputDirectory: String
    }

    static func newSession(outputDirectory: URL, permissionSnapshot: PermissionSnapshot, now: Date = Date()) -> SessionDiagnostics {
        let sessionId = outputDirectory.lastPathComponent
        let startedAt = ISO8601DateFormatter().string(from: now)
        return SessionDiagnostics(
            sessionId: sessionId,
            app: AppSnapshot(name: AppInfo.name, version: AppInfo.version),
            system: SystemSnapshot(macOS: AppInfo.operatingSystemVersion, machine: AppInfo.machineName),
            permissions: permissionSnapshot,
            recording: RecordingSnapshot(startedAt: startedAt, endedAt: nil, durationSeconds: nil, outputDirectory: outputDirectory.path),
            configuration: CaptureConfigurationSnapshot(),
            tracks: TrackGroupDiagnostics(),
            validation: nil,
            errors: []
        )
    }

    func validationResult(fileExistsAndNonEmpty: (String) -> Bool) -> ValidationResult {
        let checks = ValidationChecks(
            systemFileNonEmpty: fileExistsAndNonEmpty(tracks.system.path),
            micFileNonEmpty: fileExistsAndNonEmpty(tracks.microphone.path),
            mixedFileNonEmpty: fileExistsAndNonEmpty(tracks.mixed.path),
            systemBuffersPresent: tracks.system.bufferCount > 0,
            micBuffersPresent: tracks.microphone.bufferCount > 0
        )
        return ValidationResult(
            passed: checks.systemFileNonEmpty && checks.micFileNonEmpty && checks.mixedFileNonEmpty && checks.systemBuffersPresent && checks.micBuffersPresent,
            checks: checks
        )
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run diagnostics tests**

Run:

```bash
swift test --filter SessionDiagnosticsTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabyRecorder/Support Sources/BabyRecorder/Diagnostics Tests/BabyRecorderTests/SessionDiagnosticsTests.swift
git commit -m "feat: add session diagnostics"
```

## Task 3: Mixer

**Files:**
- Create: `Sources/BabyRecorder/Audio/Mixer.swift`
- Create: `Tests/BabyRecorderTests/MixerTests.swift`

- [ ] **Step 1: Write failing mixer tests**

Create `Tests/BabyRecorderTests/MixerTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import BabyRecorder

final class MixerTests: XCTestCase {
    func testMixesTwoMonoFilesIntoNonEmptyOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.wav")
        let b = dir.appendingPathComponent("b.wav")
        let out = dir.appendingPathComponent("mixed.wav")
        try TestAudio.writeSineWave(url: a, frequency: 440, duration: 0.1)
        try TestAudio.writeSineWave(url: b, frequency: 660, duration: 0.1)

        let result = try Mixer().mix(systemURL: a, microphoneURL: b, outputURL: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertGreaterThan(result.bytesWritten, 44)
    }

    func testReportsMissingInput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("mixed.wav")

        XCTAssertThrowsError(try Mixer().mix(systemURL: dir.appendingPathComponent("missing-a.wav"), microphoneURL: dir.appendingPathComponent("missing-b.wav"), outputURL: out))
    }
}

enum TestAudio {
    static func writeSineWave(url: URL, frequency: Double, duration: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frameCount = AVAudioFrameCount(48_000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            samples[index] = Float(sin(2.0 * Double.pi * frequency * Double(index) / 48_000.0) * 0.25)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
```

- [ ] **Step 2: Run mixer tests and confirm failure**

Run:

```bash
swift test --filter MixerTests
```

Expected: FAIL because `Mixer` does not exist.

- [ ] **Step 3: Implement offline mixer**

Create `Sources/BabyRecorder/Audio/Mixer.swift`:

```swift
import AVFoundation
import Foundation

struct MixResult: Equatable {
    var bytesWritten: Int64
}

enum MixerError: Error, Equatable {
    case missingInput(String)
    case unreadableInput(String)
}

struct Mixer {
    func mix(systemURL: URL, microphoneURL: URL, outputURL: URL) throws -> MixResult {
        guard FileManager.default.fileExists(atPath: systemURL.path) else {
            throw MixerError.missingInput(systemURL.path)
        }
        guard FileManager.default.fileExists(atPath: microphoneURL.path) else {
            throw MixerError.missingInput(microphoneURL.path)
        }

        let systemFile = try AVAudioFile(forReading: systemURL)
        let micFile = try AVAudioFile(forReading: microphoneURL)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let systemBuffer = try readConverted(file: systemFile, outputFormat: outputFormat)
        let micBuffer = try readConverted(file: micFile, outputFormat: outputFormat)
        let frameLength = max(systemBuffer.frameLength, micBuffer.frameLength)
        let mixed = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameLength)!
        mixed.frameLength = frameLength

        for channel in 0..<Int(outputFormat.channelCount) {
            let out = mixed.floatChannelData![channel]
            let system = systemBuffer.floatChannelData![channel]
            let mic = micBuffer.floatChannelData![channel]
            for frame in 0..<Int(frameLength) {
                let s = frame < Int(systemBuffer.frameLength) ? system[frame] : 0
                let m = frame < Int(micBuffer.frameLength) ? mic[frame] : 0
                out[frame] = min(1.0, max(-1.0, s + m))
            }
        }

        let output = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        try output.write(from: mixed)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return MixResult(bytesWritten: bytes)
    }

    private func readConverted(file: AVAudioFile, outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw MixerError.unreadableInput(file.url.path)
        }
        try file.read(into: sourceBuffer)
        if sourceFormat == outputFormat {
            return sourceBuffer
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
            throw MixerError.unreadableInput(file.url.path)
        }
        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1
        let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)!
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }
        if let conversionError {
            throw conversionError
        }
        return converted
    }
}
```

- [ ] **Step 4: Run mixer tests**

Run:

```bash
swift test --filter MixerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabyRecorder/Audio/Mixer.swift Tests/BabyRecorderTests/MixerTests.swift
git commit -m "feat: add offline mixer"
```

## Task 4: Audio Track Writer Stats

**Files:**
- Create: `Sources/BabyRecorder/Audio/AudioTrackWriter.swift`
- Create: `Tests/BabyRecorderTests/AudioTrackWriterTests.swift`

- [ ] **Step 1: Write failing track writer tests**

Create `Tests/BabyRecorderTests/AudioTrackWriterTests.swift`:

```swift
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
        XCTAssertEqual(stats.firstPTS, 0.1, accuracy: 0.001)
        XCTAssertEqual(stats.lastPTS, 0.3, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run writer tests and confirm failure**

Run:

```bash
swift test --filter AudioTrackWriterTests
```

Expected: FAIL because `AudioTrackStats` does not exist.

- [ ] **Step 3: Implement stats and writer shell**

Create `Sources/BabyRecorder/Audio/AudioTrackWriter.swift`:

```swift
import AVFoundation
import CoreMedia
import Foundation

struct AudioTrackStats: Equatable {
    var path: String
    var bufferCount: Int = 0
    var framesWritten: Int64 = 0
    var bytesWritten: Int64 = 0
    var firstPTS: Double?
    var lastPTS: Double?

    mutating func recordBuffer(frames: Int64, bytes: Int64, pts: CMTime) {
        let seconds = pts.seconds
        bufferCount += 1
        framesWritten += frames
        bytesWritten += bytes
        if firstPTS == nil {
            firstPTS = seconds
        }
        lastPTS = seconds
    }

    func asDiagnostics() -> TrackDiagnostics {
        TrackDiagnostics(path: path, bufferCount: bufferCount, framesWritten: framesWritten, bytesWritten: bytesWritten, firstPTS: firstPTS, lastPTS: lastPTS)
    }
}

final class AudioTrackWriter {
    private let url: URL
    private var file: AVAudioFile?
    private(set) var stats: AudioTrackStats

    init(url: URL) {
        self.url = url
        self.stats = AudioTrackStats(path: url.lastPathComponent)
    }

    func write(buffer: AVAudioPCMBuffer, pts: CMTime) throws {
        if file == nil {
            file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        }
        try file?.write(from: buffer)
        let bytes = Int64(buffer.frameLength) * Int64(buffer.format.streamDescription.pointee.mBytesPerFrame)
        stats.recordBuffer(frames: Int64(buffer.frameLength), bytes: bytes, pts: pts)
    }

    func close() {
        file = nil
    }
}
```

- [ ] **Step 4: Run writer tests**

Run:

```bash
swift test --filter AudioTrackWriterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabyRecorder/Audio/AudioTrackWriter.swift Tests/BabyRecorderTests/AudioTrackWriterTests.swift
git commit -m "feat: add audio track writer stats"
```

## Task 5: Permission Service and View Model

**Files:**
- Create: `Sources/BabyRecorder/Permissions/PermissionService.swift`
- Create: `Sources/BabyRecorder/UI/RecordingViewModel.swift`
- Create: `Tests/BabyRecorderTests/RecordingViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/BabyRecorderTests/RecordingViewModelTests.swift`:

```swift
import XCTest
@testable import BabyRecorder

final class RecordingViewModelTests: XCTestCase {
    func testStartDisabledWhenPermissionsMissing() async {
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: false, mic: true), captureService: FakeCaptureService())
        await viewModel.checkPermissions()

        let canStart = await viewModel.canStartRecording
        let state = await viewModel.state
        XCTAssertFalse(canStart)
        XCTAssertEqual(state, .permissionsMissing)
    }

    func testStartEnabledWhenPermissionsReady() async {
        let viewModel = await RecordingViewModel(permissionService: FakePermissionService(screen: true, mic: true), captureService: FakeCaptureService())
        await viewModel.checkPermissions()

        let canStart = await viewModel.canStartRecording
        let state = await viewModel.state
        XCTAssertTrue(canStart)
        XCTAssertEqual(state, .ready)
    }
}
```

- [ ] **Step 2: Run view model tests and confirm failure**

Run:

```bash
swift test --filter RecordingViewModelTests
```

Expected: FAIL because view model and permission protocols do not exist.

- [ ] **Step 3: Implement permission service and view model contracts**

Create `Sources/BabyRecorder/Permissions/PermissionService.swift`:

```swift
import AVFoundation
import Foundation

struct PermissionStatus: Equatable {
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

protocol PermissionServicing {
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
```

Create `Sources/BabyRecorder/UI/RecordingViewModel.swift`:

```swift
import Foundation

enum RecordingState: Equatable {
    case checkingPermissions
    case permissionsMissing
    case ready
    case starting
    case recording
    case stopping
    case finished
    case finishedWithMixFailure
    case failed(String)
}

protocol CaptureServicing {
    func start(permissionSnapshot: PermissionSnapshot) async throws
    func stop() async throws -> RecordingCompletion
}

struct RecordingCompletion: Equatable {
    var outputDirectory: URL
    var validation: ValidationResult
    var mixFailed: Bool
}

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .checkingPermissions
    @Published private(set) var permissionStatus = PermissionStatus(screenRecordingGranted: false, microphoneGranted: false)
    @Published private(set) var outputDirectory: URL?
    @Published private(set) var validation: ValidationResult?

    private let permissionService: PermissionServicing
    private let captureService: CaptureServicing

    init(permissionService: PermissionServicing = PermissionService(), captureService: CaptureServicing) {
        self.permissionService = permissionService
        self.captureService = captureService
    }

    var canStartRecording: Bool {
        state == .ready && permissionStatus.isReady
    }

    func checkPermissions() async {
        state = .checkingPermissions
        permissionStatus = await permissionService.checkPermissions()
        state = permissionStatus.isReady ? .ready : .permissionsMissing
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
    }

    func startRecording() async {
        guard canStartRecording else {
            state = .permissionsMissing
            return
        }
        do {
            state = .starting
            try await captureService.start(permissionSnapshot: permissionStatus.snapshot)
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecording() async {
        do {
            state = .stopping
            let completion = try await captureService.stop()
            outputDirectory = completion.outputDirectory
            validation = completion.validation
            state = completion.mixFailed ? .finishedWithMixFailure : .finished
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct FakePermissionService: PermissionServicing {
    var screen: Bool
    var mic: Bool

    func checkPermissions() async -> PermissionStatus {
        PermissionStatus(screenRecordingGranted: screen, microphoneGranted: mic)
    }

    func openSystemSettings() {}
}

final class FakeCaptureService: CaptureServicing {
    func start(permissionSnapshot: PermissionSnapshot) async throws {}

    func stop() async throws -> RecordingCompletion {
        RecordingCompletion(
            outputDirectory: FileManager.default.temporaryDirectory,
            validation: ValidationResult(passed: true, checks: ValidationChecks(systemFileNonEmpty: true, micFileNonEmpty: true, mixedFileNonEmpty: true, systemBuffersPresent: true, micBuffersPresent: true)),
            mixFailed: false
        )
    }
}
```

- [ ] **Step 4: Run view model tests**

Run:

```bash
swift test --filter RecordingViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabyRecorder/Permissions Sources/BabyRecorder/UI/RecordingViewModel.swift Tests/BabyRecorderTests/RecordingViewModelTests.swift
git commit -m "feat: add permission-aware recording state"
```

## Task 6: Capture Service with ScreenCaptureKit

**Files:**
- Create: `Sources/BabyRecorder/Capture/CaptureService.swift`
- Create: `Sources/BabyRecorder/Capture/CaptureOutputRouter.swift`
- Modify: `Sources/BabyRecorder/UI/RecordingViewModel.swift`

- [ ] **Step 1: Implement sample buffer routing**

Create `Sources/BabyRecorder/Capture/CaptureOutputRouter.swift`:

```swift
import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class CaptureOutputRouter: NSObject, SCStreamOutput {
    private let systemWriter: AudioTrackWriter
    private let micWriter: AudioTrackWriter
    private let queue = DispatchQueue(label: "BabyRecorder.CaptureOutputRouter")

    init(systemWriter: AudioTrackWriter, micWriter: AudioTrackWriter) {
        self.systemWriter = systemWriter
        self.micWriter = micWriter
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else {
            return
        }
        queue.async {
            do {
                guard let pcm = try Self.makePCMBuffer(from: sampleBuffer) else {
                    return
                }
                let pts = sampleBuffer.presentationTimeStamp
                switch outputType {
                case .audio:
                    try self.systemWriter.write(buffer: pcm, pts: pts)
                case .microphone:
                    try self.micWriter.write(buffer: pcm, pts: pts)
                default:
                    break
                }
            } catch {
                // CaptureService reads writer stats for MVP diagnostics. Per-buffer write errors are added in Task 7.
            }
        }
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
        try sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
            guard let formatDescription = sampleBuffer.formatDescription,
                  let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
                return nil
            }
            let format = AVAudioFormat(streamDescription: streamDescription)!
            let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            pcm.frameLength = frameCount
            let bytes = CMBlockBufferGetDataLength(blockBuffer)
            if bytes > 0, let channelData = pcm.mutableAudioBufferList.pointee.mBuffers.mData {
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: bytes, destination: channelData)
            }
            return pcm
        }
    }
}
```

- [ ] **Step 2: Implement capture service**

Create `Sources/BabyRecorder/Capture/CaptureService.swift`:

```swift
import Foundation
import ScreenCaptureKit

final class CaptureService: NSObject, CaptureServicing, SCStreamDelegate {
    private var stream: SCStream?
    private var router: CaptureOutputRouter?
    private var paths: RecordingSessionPaths?
    private var diagnostics: SessionDiagnostics?
    private var systemWriter: AudioTrackWriter?
    private var micWriter: AudioTrackWriter?
    private let mixer = Mixer()

    func start(permissionSnapshot: PermissionSnapshot) async throws {
        let paths = try RecordingSessionPaths.create()
        self.paths = paths
        var diagnostics = SessionDiagnostics.newSession(outputDirectory: paths.outputDirectory, permissionSnapshot: permissionSnapshot)
        let systemWriter = AudioTrackWriter(url: paths.systemWav)
        let micWriter = AudioTrackWriter(url: paths.micWav)
        let router = CaptureOutputRouter(systemWriter: systemWriter, micWriter: micWriter)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            diagnostics.errors.append(AppErrorRecord(.shareableContentFailed, message: error.localizedDescription))
            self.diagnostics = diagnostics
            throw error
        }

        guard let display = content.displays.first else {
            diagnostics.errors.append(AppErrorRecord(.mainDisplayUnavailable, message: "No display returned by SCShareableContent"))
            self.diagnostics = diagnostics
            throw NSError(domain: "BabyRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Main display unavailable"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(router, type: .audio, sampleHandlerQueue: DispatchQueue(label: "BabyRecorder.SystemAudio"))
        try stream.addStreamOutput(router, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "BabyRecorder.Microphone"))
        try await withCheckedThrowingContinuation { continuation in
            stream.startCapture { error in
                if let error {
                    diagnostics.errors.append(AppErrorRecord(.streamStartFailed, message: error.localizedDescription))
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        self.stream = stream
        self.router = router
        self.systemWriter = systemWriter
        self.micWriter = micWriter
        self.diagnostics = diagnostics
    }

    func stop() async throws -> RecordingCompletion {
        guard let stream, let paths, var diagnostics, let systemWriter, let micWriter else {
            throw NSError(domain: "BabyRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recording is not active"])
        }

        try await withCheckedThrowingContinuation { continuation in
            stream.stopCapture { error in
                if let error {
                    diagnostics.errors.append(AppErrorRecord(.streamStopFailed, message: error.localizedDescription))
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        systemWriter.close()
        micWriter.close()
        diagnostics.tracks.system = systemWriter.stats.asDiagnostics()
        diagnostics.tracks.microphone = micWriter.stats.asDiagnostics()

        var mixFailed = false
        do {
            let mix = try mixer.mix(systemURL: paths.systemWav, microphoneURL: paths.micWav, outputURL: paths.mixedWav)
            diagnostics.tracks.mixed.bytesWritten = mix.bytesWritten
        } catch {
            mixFailed = true
            diagnostics.errors.append(AppErrorRecord(.mixedWavWriteFailed, message: error.localizedDescription))
        }

        diagnostics.validation = diagnostics.validationResult { relativePath in
            let url = paths.outputDirectory.appendingPathComponent(relativePath)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return size > 0
        }
        try diagnostics.write(to: paths.sessionJSON)

        self.stream = nil
        self.router = nil
        self.paths = nil
        self.systemWriter = nil
        self.micWriter = nil
        self.diagnostics = nil

        return RecordingCompletion(outputDirectory: paths.outputDirectory, validation: diagnostics.validation!, mixFailed: mixFailed)
    }
}
```

- [ ] **Step 3: Run build**

Run:

```bash
swift build
```

Expected: build succeeds. If `SCStreamConfiguration.captureMicrophone` or `SCStreamOutputType.microphone` requires a newer SDK than the installed Xcode exposes, stop and record that exact compiler error in the next commit message before deciding whether to install/update Xcode.

- [ ] **Step 4: Commit**

```bash
git add Sources/BabyRecorder/Capture Sources/BabyRecorder/UI/RecordingViewModel.swift
git commit -m "feat: add ScreenCaptureKit capture service"
```

## Task 7: Wire the Minimal UI

**Files:**
- Modify: `Sources/BabyRecorder/BabyRecorderApp.swift`
- Modify: `Sources/BabyRecorder/UI/ContentView.swift`

- [ ] **Step 1: Inject real capture service**

Modify `Sources/BabyRecorder/BabyRecorderApp.swift`:

```swift
import SwiftUI

@main
struct BabyRecorderApp: App {
    @StateObject private var viewModel = RecordingViewModel(captureService: CaptureService())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(width: 560, height: 380)
                .task {
                    await viewModel.checkPermissions()
                }
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 2: Replace placeholder UI**

Modify `Sources/BabyRecorder/UI/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Baby Recorder")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("State: \(stateText)")
                Text("Screen Recording: \(viewModel.permissionStatus.screenRecordingGranted ? "Ready" : "Missing")")
                Text("Microphone: \(viewModel.permissionStatus.microphoneGranted ? "Ready" : "Missing")")
            }

            HStack {
                Button("Re-check Permissions") {
                    Task { await viewModel.checkPermissions() }
                }
                Button("Open System Settings") {
                    viewModel.openSystemSettings()
                }
            }

            HStack {
                Button("Start Recording") {
                    Task { await viewModel.startRecording() }
                }
                .disabled(!viewModel.canStartRecording)

                Button("Stop Recording") {
                    Task { await viewModel.stopRecording() }
                }
                .disabled(viewModel.state != .recording)
            }

            if let outputDirectory = viewModel.outputDirectory {
                Text("Output: \(outputDirectory.path)")
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let validation = viewModel.validation {
                Text(validation.passed ? "Validation passed" : "Validation failed")
                    .foregroundStyle(validation.passed ? .green : .red)
            }

            Spacer()
        }
        .padding(24)
    }

    private var stateText: String {
        switch viewModel.state {
        case .checkingPermissions: "checking permissions"
        case .permissionsMissing: "permissions missing"
        case .ready: "ready"
        case .starting: "starting"
        case .recording: "recording"
        case .stopping: "stopping"
        case .finished: "finished"
        case .finishedWithMixFailure: "finished with mix failure"
        case .failed(let message): "failed: \(message)"
        }
    }
}
```

- [ ] **Step 3: Run tests and build**

Run:

```bash
swift test
swift build
```

Expected: tests pass and build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/BabyRecorder/BabyRecorderApp.swift Sources/BabyRecorder/UI/ContentView.swift
git commit -m "feat: wire minimal recording UI"
```

## Task 8: App Bundle and Privacy Metadata

**Files:**
- Create: `Info.plist`
- Create: `Scripts/package_app.sh`

- [ ] **Step 1: Add app bundle metadata**

Create `Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>BabyRecorder</string>
  <key>CFBundleIdentifier</key>
  <string>local.babyrecorder.mvp</string>
  <key>CFBundleName</key>
  <string>BabyRecorder</string>
  <key>CFBundleDisplayName</key>
  <string>Baby Recorder</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.4.1</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Baby Recorder needs microphone access to capture the default microphone track.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
```

- [ ] **Step 2: Add packaging script**

Create `Scripts/package_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/build/BabyRecorder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
```

- [ ] **Step 3: Make script executable and build app**

Run:

```bash
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

Expected: prints `/Users/yimingliu/Desktop/宝宝录音App/build/BabyRecorder.app`.

- [ ] **Step 4: Commit**

```bash
git add Info.plist Scripts/package_app.sh
git commit -m "chore: package macOS app bundle"
```

## Task 9: Local Manual Recording Verification

**Files:**
- Modify only if verification reveals a compile-time or runtime issue.

- [ ] **Step 1: Launch packaged app**

Run:

```bash
open build/BabyRecorder.app
```

Expected: Baby Recorder window opens and immediately shows permission status.

- [ ] **Step 2: Complete permissions**

Use the app buttons to open System Settings and grant:

- Screen Recording
- Microphone

Quit and relaunch the app if macOS requires it.

- [ ] **Step 3: Record test audio**

Play system audio, speak into the microphone, record 10 to 20 seconds, then stop.

Expected: UI shows output directory and validation result.

- [ ] **Step 4: Inspect output directory**

Run this with the actual timestamp directory shown by the UI:

```bash
ls -lh Recordings/YYYY-MM-DD_HH-mm-ss
cat Recordings/YYYY-MM-DD_HH-mm-ss/session.json
```

Expected:

- `system.wav` exists and is non-empty.
- `mic.wav` exists and is non-empty.
- `mixed.wav` exists and is non-empty.
- `session.json` has `tracks.system.bufferCount > 0`.
- `session.json` has `tracks.microphone.bufferCount > 0`.
- `validation.passed` is `true`.

- [ ] **Step 5: Commit verification fixes or results note**

If code changed:

```bash
git add .
git commit -m "fix: address local recording verification"
```

If no code changed, add a short verification note:

```bash
mkdir -p docs/verification
printf "# Local Recording Verification\n\nDate: 2026-05-24\nMachine: macOS Tahoe 26.5\nResult: system, microphone, and mixed WAV outputs created and validation passed.\n" > docs/verification/2026-05-24-local-recording.md
git add docs/verification/2026-05-24-local-recording.md
git commit -m "docs: record local MVP verification"
```

## Task 10: Girlfriend Machine Verification

**Files:**
- Create: `docs/verification/2026-05-24-tahoe-26.4.1.md`

- [ ] **Step 1: Build app bundle**

Run:

```bash
Scripts/package_app.sh
```

Expected: `build/BabyRecorder.app` exists.

- [ ] **Step 2: Copy app to the Tahoe 26.4.1 machine**

Use AirDrop, Finder, or another local transfer method to copy:

```text
build/BabyRecorder.app
```

- [ ] **Step 3: Run the same real recording test**

Expected:

- permission readiness appears before recording
- recording starts only after permissions are ready
- output contains `system.wav`, `mic.wav`, `mixed.wav`, `session.json`
- system and microphone buffer counts are both greater than zero

- [ ] **Step 4: Record result**

Create `docs/verification/2026-05-24-tahoe-26.4.1.md`:

```markdown
# Tahoe 26.4.1 Verification

Date: 2026-05-24
Machine: Girlfriend's Mac
App Version: 0.1.0

## Result

- Screen Recording permission ready before recording: yes
- Microphone permission ready before recording: yes
- `system.wav` non-empty: yes
- `mic.wav` non-empty: yes
- `mixed.wav` non-empty: yes
- system buffer count > 0: yes
- microphone buffer count > 0: yes
- validation passed: yes

## Notes

No issues observed.
```

If any line is not true during verification, change that line to `no`, add the observed error code or symptom under Notes, and do not mark the MVP verified until the failure is understood.

- [ ] **Step 5: Commit verification note**

```bash
git add docs/verification/2026-05-24-tahoe-26.4.1.md
git commit -m "docs: record Tahoe 26.4.1 verification"
```

## Plan Self-Review

- Spec coverage: covered normal window app, startup permissions, ScreenCaptureKit `.audio` and `.microphone`, main display capture, `Recordings/` output layout, three WAV files, `session.json`, lightweight validation, and target-machine verification.
- Scope check: fallback AVAudioEngine design is intentionally not implemented in this plan because the spec says it is only for later if ScreenCaptureKit microphone capture fails.
- Placeholder scan: no unresolved placeholder markers or intentionally vague implementation steps remain.
- Type consistency: `PermissionSnapshot`, `ValidationResult`, `RecordingCompletion`, `CaptureServicing`, and `RecordingViewModel` names are used consistently across tasks.
