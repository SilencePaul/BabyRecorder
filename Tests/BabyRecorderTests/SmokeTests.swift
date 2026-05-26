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

    private func infoPlistStrings(for localization: String) throws -> [String: Any] {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stringsURL = packageRoot
            .appendingPathComponent("Sources/BabyRecorder/Resources")
            .appendingPathComponent("\(localization).lproj")
            .appendingPathComponent("InfoPlist.strings")
        let data = try Data(contentsOf: stringsURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
