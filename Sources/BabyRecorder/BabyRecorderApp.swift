import SwiftUI

@main
struct BabyRecorderApp: App {
    @StateObject private var viewModel = RecordingViewModel(captureService: CaptureService())

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(width: 560, height: 380)
                .task {
                    await viewModel.checkPermissions()
                }
        }
        .windowStyle(.titleBar)
    }
}
