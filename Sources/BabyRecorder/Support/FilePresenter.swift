import AppKit
import Foundation

protocol FilePresenting: Sendable {
    func revealInFinder(_ url: URL)
}

struct FinderFilePresenter: FilePresenting {
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
