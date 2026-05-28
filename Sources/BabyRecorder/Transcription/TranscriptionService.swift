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

enum TranscriptionMode: String, Equatable, Sendable {
    case mixed
    case dialogue

    var labelKey: String {
        switch self {
        case .mixed:
            "transcription.mode.mixed"
        case .dialogue:
            "transcription.mode.dialogue"
        }
    }
}

struct TranscriptionRequest: Equatable, Sendable {
    var sessionDirectory: URL
    var model: TranscriptionModel
    var mode: TranscriptionMode = .mixed
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
    var runtimeRoot: URL
    var scriptURL: URL
    var environment: [String: String]
    var processRunner: ProcessRunning

    init(
        runtimeRoot: URL = BabyRecorderRuntimePaths.defaultRuntimeRoot(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.runtimeRoot = runtimeRoot
        self.scriptURL = BabyRecorderRuntimePaths.transcriptionScriptURL(runtimeRoot: runtimeRoot)
        self.environment = environment
        self.processRunner = processRunner
    }

    init(
        runtimeRoot: URL,
        scriptURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.runtimeRoot = runtimeRoot
        self.scriptURL = scriptURL
        self.environment = environment
        self.processRunner = processRunner
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try validateAudioFiles(for: request)

        let pythonURL = runtimeRoot.appendingPathComponent(".venv-asr/bin/python")
        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            throw TranscriptionError.missingEnvironment(pythonURL)
        }

        var processEnvironment = environment
        processEnvironment["HOME"] = processEnvironment["HOME"] ?? NSHomeDirectory()
        processEnvironment["PATH"] = processEnvironment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        processEnvironment["PYTHONUNBUFFERED"] = "1"
        processEnvironment["SHELL"] = "/bin/zsh"
        processEnvironment["HF_HOME"] = runtimeRoot.appendingPathComponent("huggingface").path
        processEnvironment["HF_HUB_CACHE"] = runtimeRoot.appendingPathComponent("huggingface/hub").path
        processEnvironment["HF_ENDPOINT"] = processEnvironment["HF_ENDPOINT"] ?? "https://hf-mirror.com"

        let result = try await processRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-lc",
                Self.shellCommand(
                    runtimeRoot: runtimeRoot,
                    scriptURL: scriptURL,
                    sessionDirectory: request.sessionDirectory,
                    model: request.model,
                    mode: request.mode
                )
            ],
            environment: processEnvironment,
            currentDirectoryURL: runtimeRoot
        )
        try? result.combinedOutput.write(
            to: request.sessionDirectory.appendingPathComponent("transcription.log"),
            atomically: true,
            encoding: .utf8
        )
        guard result.exitCode == 0 else {
            throw TranscriptionError.processFailed(result.combinedOutput)
        }

        let transcriptURL = request.sessionDirectory.appendingPathComponent(request.mode.transcriptFileName)
        let metadataURL = request.sessionDirectory.appendingPathComponent(request.mode.metadataFileName)
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            throw TranscriptionError.missingTranscript(transcriptURL)
        }

        let text = try String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text, transcriptURL: transcriptURL, metadataURL: metadataURL)
    }

    private static func shellCommand(
        runtimeRoot: URL,
        scriptURL: URL,
        sessionDirectory: URL,
        model: TranscriptionModel,
        mode: TranscriptionMode
    ) -> String {
        [
            "cd \(shellQuoted(runtimeRoot.path))",
            "QWEN3_ASR_MODEL=\(shellQuoted(model.rawValue)) QWEN3_ASR_MODE=\(shellQuoted(mode.rawValue)) \(shellQuoted(scriptURL.path)) \(shellQuoted(sessionDirectory.path))"
        ].joined(separator: " && ")
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func validateAudioFiles(for request: TranscriptionRequest) throws {
        for fileName in request.mode.requiredAudioFileNames {
            let audioURL = request.sessionDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw TranscriptionError.missingAudio(audioURL)
            }
        }
    }
}

private extension TranscriptionMode {
    var requiredAudioFileNames: [String] {
        switch self {
        case .mixed:
            ["mixed.wav"]
        case .dialogue:
            ["mic.wav", "system.wav"]
        }
    }

    var transcriptFileName: String {
        switch self {
        case .mixed:
            "transcript.txt"
        case .dialogue:
            "transcript_dialogue.txt"
        }
    }

    var metadataFileName: String {
        switch self {
        case .mixed:
            "transcript.json"
        case .dialogue:
            "transcript_dialogue.json"
        }
    }
}

enum BabyRecorderRuntimePaths {
    static func defaultRuntimeRoot(fileManager: FileManager = .default) -> URL {
        if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupport.appendingPathComponent("BabyRecorder", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/BabyRecorder", isDirectory: true)
    }

    static func transcriptionScriptURL(runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent("Scripts/transcribe_mlx_qwen3_asr.sh")
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
