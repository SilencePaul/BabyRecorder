import XCTest
@testable import BabyRecorder

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual("BabyRecorder", AppInfo.name)
    }

    func testInfoPlistStringsLocalizeBundleName() throws {
        XCTAssertEqual(
            try infoPlistStrings(for: "en")["CFBundleName"] as? String,
            "Baby Recorder"
        )
        XCTAssertEqual(
            try infoPlistStrings(for: "zh-Hans")["CFBundleName"] as? String,
            "宝宝录音"
        )
    }

    func testBundleIdentityIsStableForSystemPermissions() throws {
        let plist = try infoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.yimingliu.BabyRecorder")
        XCTAssertEqual(plist["CFBundleName"] as? String, "BabyRecorder")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.4.1")
    }

    private func infoPlistStrings(for localization: String) throws -> [String: Any] {
        let stringsURL = packageRoot()
            .appendingPathComponent("Sources/BabyRecorder/Resources")
            .appendingPathComponent("\(localization).lproj")
            .appendingPathComponent("InfoPlist.strings")
        let data = try Data(contentsOf: stringsURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: packageRoot().appendingPathComponent("Info.plist"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func packageRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
