import Foundation

enum AppInfo {
    static let name = "BabyRecorder"
    static let version = "0.1.0"

    static var operatingSystemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    static var machineName: String {
        Host.current().localizedName ?? "Mac"
    }
}
