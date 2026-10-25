import XCTest

final class ProfileFlowTests: XCTestCase {
    func testProfileEditPersistsAndSettingsOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["MESHINOWA_OFFLINE"] = "1"
        app.launchEnvironment["MESHINOWA_UI_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["-hasOpenedMeshinowa", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["プロフィール"].waitForExistence(timeout: 15))
        app.buttons["プロフィール"].tap()
        app.buttons["プロフィールを編集"].tap()
        let name = app.textFields["表示名"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        if let value = name.value as? String {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        name.typeText("Hackathon Chef")
        app.buttons["おさかな"].tap()
        app.navigationBars.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["Hackathon Chef"].waitForExistence(timeout: 5))
        let profile = XCTAttachment(screenshot: app.screenshot())
        profile.name = "profile-edited"
        profile.lifetime = .keepAlways
        add(profile)
        app.buttons["設定を開く"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "端末内モード")).firstMatch.exists)
        app.terminate()
        app.launch()
        app.buttons["プロフィール"].tap()
        XCTAssertTrue(app.staticTexts["Hackathon Chef"].waitForExistence(timeout: 5))
    }
}
