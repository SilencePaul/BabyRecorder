import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct SystemMeetingApplicationProvider: MeetingApplicationProviding {
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
            let accessibilityTitles = accessibilityTrusted ? Self.accessibilityWindowTitles(for: application.processIdentifier) : []
            let mergedTitles = Array(Set(titles + accessibilityTitles))

            return RunningApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                localizedName: application.localizedName ?? "",
                windowTitles: mergedTitles,
                canReadWindowMetadata: accessibilityTrusted || mergedTitles.isEmpty == false
            )
        }
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

    private static func accessibilityWindowTitles(for processIdentifier: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window in
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String,
                  title.isEmpty == false else {
                return nil
            }
            return title
        }
    }
}
