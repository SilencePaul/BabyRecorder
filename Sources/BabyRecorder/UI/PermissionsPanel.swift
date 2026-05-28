import SwiftUI

struct PermissionsPanel: View {
    let permissionRows: [RecordingPresentation.PermissionRow]
    let recordingStateTitleKey: String
    let recordingStateTone: StatusTone
    let checkPermissions: () async -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section.permissions")
                .font(.headline)

            ForEach(permissionRows, id: \.labelKey) { row in
                StatusRow(
                    title: LocalizedStringKey(row.labelKey),
                    value: LocalizedStringKey(row.statusKey),
                    status: row.status == .ready ? .success : .warning
                )
            }

            StatusRow(
                title: "label.recordingState",
                value: LocalizedStringKey(recordingStateTitleKey),
                status: recordingStateTone
            )

            HStack(spacing: 8) {
                Button {
                    Task { await checkPermissions() }
                } label: {
                    Label("recording.action.recheck", systemImage: "arrow.clockwise")
                }

                Button {
                    openSystemSettings()
                } label: {
                    Label("menu.openSystemSettings", systemImage: "gear")
                }
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }
}
