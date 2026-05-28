import SwiftUI

struct RootView: View {
    @Bindable var recordingViewModel: RecordingViewModel
    @Bindable var runtimeSetupViewModel: RuntimeSetupViewModel

    var body: some View {
        switch runtimeSetupViewModel.phase {
        case .ready:
            ContentView(viewModel: recordingViewModel)
                .task {
                    await recordingViewModel.checkPermissions()
                }
        case .checking, .installing, .failed:
            RuntimeSetupView(viewModel: runtimeSetupViewModel)
                .task {
                    await runtimeSetupViewModel.prepareIfNeeded()
                }
        }
    }
}
