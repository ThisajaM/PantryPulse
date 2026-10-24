import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    @MainActor func testLandscapeInventoryAndScannerNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "layout-test"
        app.launch()
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10)); XCTAssertTrue(skip.isHittable)
        snapshot("Landscape onboarding", app)
        skip.tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 15))
        app.buttons["Add Food"].tap()
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Landscape food\n")
        let save = app.buttons["addFood.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable)
        snapshot("Landscape add food", app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        tab("Pantry", app)
        let item = app.buttons.containing(.staticText, identifier: "Landscape food").firstMatch
        reach(item, app); item.tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        snapshot("Landscape food details", app)
        reach(app.buttons["Edit Food"], app); app.buttons["Edit Food"].tap()
        XCTAssertTrue(app.navigationBars["Edit Food"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["addFood.name"].value as? String, "Landscape food")
        app.navigationBars.buttons.firstMatch.tap()
        tab("Home", app)
        reach(app.buttons["See all"], app); app.buttons["See all"].tap()
        XCTAssertTrue(app.navigationBars["Use First"].waitForExistence(timeout: 5))
        snapshot("Landscape use first", app)
        tab("Insights", app)
        XCTAssertTrue(app.staticTexts["Your insights begin here"].waitForExistence(timeout: 5))
        snapshot("Landscape insights", app)
        tab("Scan", app)
        let barcode = app.buttons.containing(.staticText, identifier: "Scan a Barcode").firstMatch
        reach(barcode, app); barcode.tap()
        let manual = app.buttons["barcode.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        reach(manual, app); manual.tap()
        XCTAssertTrue(app.textFields["barcode.input"].waitForExistence(timeout: 5))
        snapshot("Landscape barcode", app)
        app.buttons["barcode.cancel"].tap()
        let recognition = app.buttons.containing(.staticText, identifier: "Recognize Food").firstMatch
        reach(recognition, app); recognition.tap()
        XCTAssertTrue(app.buttons["recognition.library"].waitForExistence(timeout: 10))
        snapshot("Landscape recognition fallback", app)
        app.navigationBars.buttons.firstMatch.tap()
        tab("Settings", app)
        let profile = app.buttons["Account & Profile"]
        reach(profile, app); profile.tap()
        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 5))
        snapshot("Landscape profile", app)
    }

    @MainActor private func tab(_ title: String, _ app: XCUIApplication) {
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    @MainActor private func reach(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func snapshot(_ title: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
