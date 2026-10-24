import XCTest

final class AccountIsolationUITests: XCTestCase {
    @MainActor func testSwitchAccountsPreservesInventoryAndSkipsOnboarding() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = ""
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 10))
        app.buttons["onboarding.skip"].tap()
        login("user-a", app)
        add("Milk", app); add("Bananas", app); add("Rice", app)
        logout(app)
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        login("user-b", app)
        app.buttons["Pantry"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Milk"].exists)
        app.buttons["Insights"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your insights begin here"].waitForExistence(timeout: 5))
        app.buttons["Home"].firstMatch.tap()
        add("Apples", app)
        logout(app)
        login("user-a", app)
        app.buttons["Pantry"].firstMatch.tap()
        for name in ["Milk", "Bananas", "Rice"] { XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5)) }
        XCTAssertFalse(app.staticTexts["Apples"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Pantry"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Pantry"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Apples"].exists)
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
    }

    @MainActor func testProfileNameAndPasswordResetFeedback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "profile-test"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 10))
        app.buttons["onboarding.skip"].tap()
        profile(app)
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "Updated Name\n")
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["Updated Name"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["profile.resetPassword"], app)
        app.buttons["profile.resetPassword"].tap()
        scrollTo(app.staticTexts["account.message"], app)
        XCTAssertTrue(app.staticTexts["account.message"].label.contains("password reset email"))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch(); profile(app)
        XCTAssertEqual(app.textFields["profile.name"].value as? String, "Updated Name")
    }

    @MainActor private func login(_ uid: String, _ app: XCUIApplication) {
        let email = app.textFields["account.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap(); email.typeText(uid + "@example.com")
        app.secureTextFields["account.password"].tap()
        app.secureTextFields["account.password"].typeText("fixture-password\n")
        XCTAssertTrue(app.buttons["Home"].firstMatch.waitForExistence(timeout: 15))
    }
    @MainActor private func add(_ name: String, _ app: XCUIApplication) {
        app.buttons["Add Food"].tap()
        let field = app.textFields["addFood.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name + "\n")
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
    }
    @MainActor private func profile(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Settings"].firstMatch.tap()
        let row = app.buttons["Account & Profile"]
        scrollTo(row, app); row.tap()
        XCTAssertTrue(app.navigationBars["My Profile"].waitForExistence(timeout: 5))
    }
    @MainActor private func logout(_ app: XCUIApplication) {
        profile(app)
        let button = app.buttons["profile.signOut"]
        scrollTo(button, app); button.tap()
        app.buttons["profile.confirmSignOut"].firstMatch.tap()
        XCTAssertTrue(app.textFields["account.email"].waitForExistence(timeout: 10))
    }
    @MainActor private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
