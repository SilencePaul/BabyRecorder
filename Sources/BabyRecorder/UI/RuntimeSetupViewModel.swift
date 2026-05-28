import Foundation
import Observation

enum RuntimeSetupPhase: Equatable {
    case checking
    case installing
    case ready
    case failed(String)
}

@MainActor
@Observable
final class RuntimeSetupViewModel {
    private let service: RuntimeSetupService
    private(set) var phase: RuntimeSetupPhase = .checking
    private(set) var logText = ""

    init(service: RuntimeSetupService = RuntimeSetupService()) {
        self.service = service
    }

    func prepareIfNeeded() async {
        guard phase != .installing else {
            return
        }

        if service.isReady {
            phase = .ready
            return
        }

        phase = .installing
        logText = String(localized: "runtimeSetup.log.starting")

        do {
            let result = try await service.runSetup()
            appendLog(result.combinedOutput)
            phase = service.isReady ? .ready : .failed(String(localized: "runtimeSetup.error.incomplete"))
        } catch {
            appendLog(error.localizedDescription)
            phase = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        phase = .checking
        await prepareIfNeeded()
    }

    private func appendLog(_ text: String) {
        guard text.isEmpty == false else {
            return
        }

        if logText.isEmpty {
            logText = text
        } else {
            logText += "\n\(text)"
        }
    }
}
