import XCTest
@testable import BabyRecorder

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertEqual("BabyRecorder", AppInfo.name)
    }
}
