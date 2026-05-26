import Foundation

enum TranscriptionModel: String, Equatable, Sendable {
    case fast = "Qwen/Qwen3-ASR-0.6B"
    case accurate = "Qwen/Qwen3-ASR-1.7B"

    var labelKey: String {
        switch self {
        case .fast:
            "transcription.model.fast"
        case .accurate:
            "transcription.model.accurate"
        }
    }
}

struct TranscriptionRequest: Equatable, Sendable {
    var sessionDirectory: URL
    var model: TranscriptionModel
}

struct TranscriptionResult: Equatable, Sendable {
    var text: String
    var transcriptURL: URL
    var metadataURL: URL
}

enum TranscriptionStatus: Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
}

struct TranscriptionSnapshot: Equatable, Sendable {
    var status: TranscriptionStatus = .idle
    var text: String = ""
    var transcriptURL: URL?
    var metadataURL: URL?
    var errorMessage: String?

    static let idle = TranscriptionSnapshot()
}

protocol TranscriptionServicing: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}

struct NoOpTranscriptionService: TranscriptionServicing {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        throw TranscriptionError.engineUnavailable
    }
}

struct PythonMLXTranscriptionService: TranscriptionServicing {
    var projectRoot: URL
    var scriptURL: URL
    var environment: [String: String]
    var processRunner: ProcessRunning

    init(
        projectRoot: URL = URL(fileURLWithPath: "/Users/yimingliu/Desktop/宝宝录音App", isDirectory: true),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.projectRoot = projectRoot
        self.scriptURL = projectRoot.appendingPathComponent("Scripts/transcribe_mlx_qwen3_asr.sh")
        self.environment = environment
        self.processRunner = processRunner
    }

    init(
        projectRoot: URL,
        scriptURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.projectRoot = projectRoot
        self.scriptURL = scriptURL
        self.environment = environment
        self.processRunner = processRunner
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let audioURL = request.sessionDirectory.appendingPathComponent("mixed.wav")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.missingAudio(audioURL)
        }

        let pythonURL = projectRoot.appendingPathComponent(".venv-asr/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            throw TranscriptionError.missingEnvironment(pythonURL)
        }

        var processEnvironment = environment
        processEnvironment["QWEN3_ASR_MODEL"] = request.model.rawValue

        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: [scriptURL.path, request.sessionDirectory.path],
            environment: processEnvironment,
            currentDirectoryURL: projectRoot
        )
        guard result.exitCode == 0 else {
            throw TranscriptionError.processFailed(result.combinedOutput)
        }

        let transcriptURL = request.sessionDirectory.appendingPathComponent("transcript.txt")
        let metadataURL = request.sessionDirectory.appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            throw TranscriptionError.missingTranscript(transcriptURL)
        }

        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text, transcriptURL: transcriptURL, metadataURL: metadataURL)
    }
}

struct ProcessResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

protocol ProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL
    ) async throws -> ProcessResult
}

struct SystemProcessRunner: ProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = currentDirectoryURL

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessResult(
                exitCode: process.terminationStatus,
                standardOutput: String(data: outputData, encoding: .utf8) ?? "",
                standardError: String(data: errorData, encoding: .utf8) ?? ""
            )
        }.value
    }
}

enum TranscriptionError: LocalizedError, Equatable {
    case engineUnavailable
    case missingAudio(URL)
    case missingEnvironment(URL)
    case processFailed(String)
    case missingTranscript(URL)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            String(localized: "transcription.error.engineUnavailable")
        case .missingAudio(let url):
            String(
                format: NSLocalizedString("transcription.error.missingAudio %@", comment: ""),
                url.lastPathComponent
            )
        case .missingEnvironment:
            String(localized: "transcription.error.missingEnvironment")
        case .processFailed(let message):
            message.isEmpty ? String(localized: "transcription.error.processFailed") : message
        case .missingTranscript:
            String(localized: "transcription.error.missingTranscript")
        }
    }
}
