import SwiftUI

struct StatusRow: View {
    let title: LocalizedStringKey
    private let value: Text
    private let truncatesValue: Bool
    private let status: StatusTone

    init(title: LocalizedStringKey, value: LocalizedStringKey, status: StatusTone) {
        self.title = title
        self.value = Text(value)
        self.truncatesValue = false
        self.status = status
    }

    init(title: LocalizedStringKey, value: String, status: StatusTone) {
        self.title = title
        self.value = Text(value)
        self.truncatesValue = true
        self.status = status
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Label {
                valueView
            } icon: {
                Image(systemName: status.symbolName)
                    .foregroundStyle(status.color)
            }
            .labelStyle(.titleAndIcon)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var valueView: some View {
        if truncatesValue {
            value
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            value
        }
    }
}
