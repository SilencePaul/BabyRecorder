import XCTest

final class DistributionScriptTests: XCTestCase {
    func testDistributionScriptsAreStandalone() throws {
        let root = packageRoot()
        let installer = root.appendingPathComponent("Scripts/install_distribution.sh")
        let packager = root.appendingPathComponent("Scripts/make_distribution.sh")

        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packager.path))

        let installerText = try String(contentsOf: installer, encoding: .utf8)
        XCTAssertTrue(installerText.contains("BabyRecorder.app"))
        XCTAssertTrue(installerText.contains("Contents/Resources/Scripts/transcribe_mlx_qwen3_asr.sh"))
        XCTAssertFalse(installerText.contains("Scripts/install_app.sh"))
        XCTAssertFalse(installerText.contains("swift build"))

        let packagerText = try String(contentsOf: packager, encoding: .utf8)
        XCTAssertTrue(packagerText.contains("README_安装说明.md"))
        XCTAssertTrue(packagerText.contains("BabyRecorder-Install.zip"))
        XCTAssertTrue(packagerText.contains("tail -n 1"))
    }

    func testRepositoryReadmeCoversInstallAndProjectBackground() throws {
        let readme = packageRoot().appendingPathComponent("README.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: readme.path))

        let text = try String(contentsOf: readme, encoding: .utf8)
        XCTAssertTrue(text.contains("项目来由"))
        XCTAssertTrue(text.contains("一键安装"))
        XCTAssertTrue(text.contains("Qwen3-ASR"))
        XCTAssertTrue(text.contains("中国大陆"))
    }

    private func packageRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
