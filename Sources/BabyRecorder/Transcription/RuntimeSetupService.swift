import Foundation

struct RuntimeSetupCommand: Equatable, Sendable {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
    var currentDirectoryURL: URL
}

struct RuntimeSetupService: Sendable {
    var runtimeRoot: URL
    var setupScriptURL: URL
    var environment: [String: String]
    var processRunner: ProcessRunning

    init(
        runtimeRoot: URL = BabyRecorderRuntimePaths.defaultRuntimeRoot(),
        setupScriptURL: URL? = Bundle.module.url(
            forResource: "setup_baby_recorder_runtime",
            withExtension: "sh",
            subdirectory: "Scripts"
        ),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: ProcessRunning = SystemProcessRunner()
    ) {
        self.runtimeRoot = runtimeRoot
        self.setupScriptURL = setupScriptURL ?? runtimeRoot.appendingPathComponent("Scripts/setup_baby_recorder_runtime.sh")
        self.environment = environment
        self.processRunner = processRunner
    }

    var isReady: Bool {
        FileManager.default.fileExists(atPath: BabyRecorderRuntimePaths.transcriptionScriptURL(runtimeRoot: runtimeRoot).path)
            && FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent(".venv-asr/bin/python").path)
            && FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent(".venv-asr/bin/mlx-qwen3-asr").path)
            && FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent("bin/ffmpeg").path)
            && defaultModelCacheExists
    }

    func setupCommand() -> RuntimeSetupCommand {
        var processEnvironment = environment
        processEnvironment["HOME"] = processEnvironment["HOME"] ?? NSHomeDirectory()
        processEnvironment["PATH"] = processEnvironment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        processEnvironment["PYTHONUNBUFFERED"] = "1"
        processEnvironment["SHELL"] = "/bin/zsh"
        processEnvironment["BABY_RECORDER_RUNTIME_DIR"] = runtimeRoot.path
        processEnvironment["BABY_RECORDER_WARM_MODEL"] = processEnvironment["BABY_RECORDER_WARM_MODEL"] ?? "1"

        return RuntimeSetupCommand(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: [setupScriptURL.path],
            environment: processEnvironment,
            currentDirectoryURL: setupScriptURL.deletingLastPathComponent()
        )
    }

    func runSetup() async throws -> ProcessResult {
        let command = setupCommand()
        let result = try await processRunner.run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            environment: command.environment,
            currentDirectoryURL: command.currentDirectoryURL
        )
        guard result.exitCode == 0 else {
            throw RuntimeSetupError.processFailed(result.combinedOutput)
        }
        return result
    }

    private var defaultModelCacheExists: Bool {
        let snapshots = runtimeRoot.appendingPathComponent("huggingface/hub/models--Qwen--Qwen3-ASR-0.6B/snapshots")
        guard let enumerator = FileManager.default.enumerator(
            at: snapshots,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                return true
            }
        }
        return false
    }
}

enum RuntimeSetupError: LocalizedError, Equatable {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let output):
            output.isEmpty ? String(localized: "runtimeSetup.error.processFailed") : output
        }
    }
}
