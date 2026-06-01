import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SystemMeetingApplicationProvider: MeetingApplicationProviding {
    struct AccessibilityWindowTitleRead: Equatable {
        var titles: [String]
        var readSucceeded: Bool
    }

    struct WindowMetadata: Equatable {
        var titles: [String]
        var canReadWindowMetadata: Bool
    }

    func runningApplications() async -> [RunningApplicationSnapshot] {
        let applications = NSWorkspace.shared.runningApplications
        let windowTitles = Self.visibleWindowTitlesByProcessID()
        let accessibilityTrusted = AXIsProcessTrusted()

        return applications.compactMap { application in
            guard let bundleIdentifier = application.bundleIdentifier,
                  MeetingApp.app(for: bundleIdentifier) != nil else {
                return nil
            }

            let titles = windowTitles[application.processIdentifier] ?? []
            let accessibilityRead = accessibilityTrusted
                ? Self.accessibilityWindowTitles(for: application.processIdentifier)
                : AccessibilityWindowTitleRead(titles: [], readSucceeded: false)
            let metadata = Self.mergedWindowMetadata(
                visibleTitles: titles,
                accessibilityRead: accessibilityRead
            )

            return RunningApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                localizedName: application.localizedName ?? "",
                windowTitles: metadata.titles,
                canReadWindowMetadata: metadata.canReadWindowMetadata
            )
        }
    }

    static func mergedWindowMetadata(
        visibleTitles: [String],
        accessibilityRead: AccessibilityWindowTitleRead
    ) -> WindowMetadata {
        let mergedTitles = Array(Set(visibleTitles + accessibilityRead.titles))
        return WindowMetadata(
            titles: mergedTitles,
            canReadWindowMetadata: visibleTitles.isEmpty == false || accessibilityRead.readSucceeded
        )
    }

    private static func visibleWindowTitlesByProcessID() -> [pid_t: [String]] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var titlesByPID: [pid_t: [String]] = [:]
        for window in windowInfo {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let title = window[kCGWindowName as String] as? String,
                  title.isEmpty == false else {
                continue
            }
            titlesByPID[ownerPID, default: []].append(title)
        }
        return titlesByPID
    }

    private static func accessibilityWindowTitles(for processIdentifier: pid_t) -> AccessibilityWindowTitleRead {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return AccessibilityWindowTitleRead(titles: [], readSucceeded: false)
        }

        let titles: [String] = windows.compactMap { window -> String? in
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String,
                  title.isEmpty == false else {
                return nil
            }
            return title
        }
        return AccessibilityWindowTitleRead(titles: titles, readSucceeded: true)
    }
}
