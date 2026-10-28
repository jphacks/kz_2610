import XCTest

final class ProfileFlowTests: XCTestCase {
    func testFriendAddSheetOpensAndClosesWithoutConnection() {
        let app = XCUIApplication()
        app.launchEnvironment["MESHINOWA_OFFLINE"] = "1"
        app.launchEnvironment["MESHINOWA_UI_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["-hasOpenedMeshinowa", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["友達"].waitForExistence(timeout: 15))
        app.buttons["友達"].tap()
        let addButton = app.buttons["friends.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.navigationBars["友達を追加"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["あなたのID"].exists)
        XCTAssertTrue(app.staticTexts["接続後に表示されます"].exists)
        XCTAssertFalse(app.textFields["friends.add.handle"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "friend-add-disconnected"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons["閉じる"].tap()
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    }

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
