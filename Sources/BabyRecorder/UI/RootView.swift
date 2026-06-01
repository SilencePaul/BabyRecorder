import SwiftUI

struct RootView: View {
    @Bindable var recordingViewModel: RecordingViewModel
    @Bindable var runtimeSetupViewModel: RuntimeSetupViewModel
    @Bindable var meetingAutoRecorder: MeetingAutoRecorder

    var body: some View {
        switch runtimeSetupViewModel.phase {
        case .ready:
            ContentView(viewModel: recordingViewModel)
                .task {
                    await recordingViewModel.checkPermissions()
                    meetingAutoRecorder.startMonitoring(recordingViewModel: recordingViewModel)
                }
                .onDisappear {
                    meetingAutoRecorder.stopMonitoring()
                }
        case .checking, .installing, .failed:
            RuntimeSetupView(viewModel: runtimeSetupViewModel)
                .task {
                    await runtimeSetupViewModel.prepareIfNeeded()
                }
        }
    }
}
