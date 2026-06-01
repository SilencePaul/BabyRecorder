import Foundation

enum MeetingApp: String, CaseIterable, Equatable, Sendable {
    case tencentMeeting
    case feishu
    case dingTalk

    var displayName: String {
        switch self {
        case .tencentMeeting:
            "腾讯会议"
        case .feishu:
            "飞书"
        case .dingTalk:
            "钉钉"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .tencentMeeting:
            ["com.tencent.meeting"]
        case .feishu:
            ["com.electron.lark"]
        case .dingTalk:
            ["com.alibaba.dingtalkmac", "com.alibaba.DingTalkMac"]
        }
    }

    var meetingKeywords: [String] {
        switch self {
        case .tencentMeeting:
            ["会议中", "共享屏幕"]
        case .feishu:
            ["飞书会议", "Lark Meeting", "Feishu Meeting", "会议中", "共享屏幕"]
        case .dingTalk:
            ["钉钉会议", "DingTalk Meeting", "会议中", "共享屏幕"]
        }
    }

    static func app(for bundleIdentifier: String) -> MeetingApp? {
        allCases.first { app in
            app.bundleIdentifiers.contains { candidate in
                candidate.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }
        }
    }
}
