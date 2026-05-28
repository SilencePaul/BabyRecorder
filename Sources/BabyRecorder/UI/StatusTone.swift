import SwiftUI

enum StatusTone {
    case neutral
    case success
    case warning
    case failure

    var symbolName: String {
        switch self {
        case .neutral:
            "circle"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}
