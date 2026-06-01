import Foundation

struct RunningApplicationSnapshot: Equatable, Sendable {
    var bundleIdentifier: String
    var localizedName: String
    var windowTitles: [String]
    var canReadWindowMetadata: Bool
}

enum MeetingDetectionStatus: Equatable, Sendable {
    case notInMeeting
    case inMeeting
    case windowMetadataUnavailable
}

struct MeetingDetectionSnapshot: Equatable, Sendable {
    var status: MeetingDetectionStatus
    var app: MeetingApp?
    var displayName: String?

    static let notInMeeting = MeetingDetectionSnapshot(status: .notInMeeting, app: nil, displayName: nil)
}

protocol MeetingApplicationProviding: Sendable {
    func runningApplications() async -> [RunningApplicationSnapshot]
}

struct MeetingDetector: Sendable {
    func detect(from applications: [RunningApplicationSnapshot]) -> MeetingDetectionSnapshot {
        var sawSupportedAppWithoutMetadata: (MeetingApp, String)?

        for application in applications {
            guard let app = MeetingApp.app(for: application.bundleIdentifier) else {
                continue
            }

            let displayName = application.localizedName.isEmpty ? app.displayName : application.localizedName
            guard application.canReadWindowMetadata else {
                sawSupportedAppWithoutMetadata = sawSupportedAppWithoutMetadata ?? (app, displayName)
                continue
            }

            if containsMeetingKeyword(in: application.windowTitles, for: app) {
                return MeetingDetectionSnapshot(status: .inMeeting, app: app, displayName: displayName)
            }
        }

        if let blocked = sawSupportedAppWithoutMetadata {
            return MeetingDetectionSnapshot(status: .windowMetadataUnavailable, app: blocked.0, displayName: blocked.1)
        }

        return .notInMeeting
    }

    private func containsMeetingKeyword(in titles: [String], for app: MeetingApp) -> Bool {
        titles.contains { title in
            app.meetingKeywords.contains { keyword in
                titleIndicatesMeeting(title, keyword: keyword)
            }
        }
    }

    private func titleIndicatesMeeting(_ title: String, keyword: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch keyword {
        case "会议中", "共享屏幕":
            guard trimmedTitle.range(of: keyword, options: [.caseInsensitive, .anchored], locale: .current) != nil else {
                return false
            }

            let remainder = trimmedTitle.dropFirst(keyword.count)
            return remainder.isEmpty || startsWithSeparator(remainder)

        default:
            return trimmedTitle.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func startsWithSeparator(_ text: Substring) -> Bool {
        guard let firstScalar = text.unicodeScalars.first else {
            return true
        }

        return CharacterSet.whitespacesAndNewlines.contains(firstScalar)
            || CharacterSet.punctuationCharacters.contains(firstScalar)
            || CharacterSet.symbols.contains(firstScalar)
    }
}
