import SwiftUI

struct RuntimeSetupView: View {
    @Bindable var viewModel: RuntimeSetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(titleKey)
                    .font(.title)
                    .fontWeight(.semibold)
                Text(messageKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if viewModel.phase == .checking || viewModel.phase == .installing {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(statusKey)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                if case .failed = viewModel.phase {
                    Button("runtimeSetup.action.retry") {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.logText.isEmpty == false {
                ScrollView {
                    Text(viewModel.logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 140)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(Text("app.title"))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var titleKey: LocalizedStringKey {
        switch viewModel.phase {
        case .checking:
            "runtimeSetup.title.checking"
        case .installing:
            "runtimeSetup.title.installing"
        case .ready:
            "runtimeSetup.title.ready"
        case .failed:
            "runtimeSetup.title.failed"
        }
    }

    private var messageKey: LocalizedStringKey {
        switch viewModel.phase {
        case .checking, .installing:
            "runtimeSetup.message.installing"
        case .ready:
            "runtimeSetup.message.ready"
        case .failed:
            "runtimeSetup.message.failed"
        }
    }

    private var statusKey: LocalizedStringKey {
        switch viewModel.phase {
        case .checking:
            "runtimeSetup.status.checking"
        case .installing:
            "runtimeSetup.status.installing"
        case .ready:
            "runtimeSetup.status.ready"
        case .failed:
            "runtimeSetup.status.failed"
        }
    }
}
