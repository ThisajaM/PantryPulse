//
//  PantryPulseUITests.swift
//  PantryPulseUITests
//
//  Created by Thisaja Mudalige on 2026-10-14.
//

import XCTest

final class PantryPulseUITests: XCTestCase {

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testAccountEntryPreservesLocalNavigation() {
        let app = freshApp()
        launchDashboard(app)
        app.tabBars.buttons["Settings"].tap()
        let account = app.buttons["Account & Profile"]
        app.swipeUp()
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["profile.email"].exists)
        XCTAssertTrue(app.switches["profile.faceID"].waitForExistence(timeout: 5))
        capture("Profile", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWasteRiskRealModelDetailsAndRelaunch() {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        launchDashboard(app)
        app.buttons["Add Food"].tap()
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Risk review food\n")
        let expiry = app.switches["addFood.includesExpiry"]
        scrollFormTo(expiry, in: app)
        expiry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        for pass in 0..<2 {
            if pass == 1 {
                app.terminate()
                app.launch()
                XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
            }
            app.tabBars.buttons["Pantry"].tap()
            let card = app.buttons.containing(.staticText, identifier: "Risk review food").firstMatch
            scrollDayFourTo(card, in: app)
            card.tap()
            XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
            let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "• Core ML")).firstMatch
            scrollDayFourTo(result, in: app)
            XCTAssertTrue(result.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Recorded inputs"].exists)
            capture("Day6 real waste risk \(pass)", app: app)
        }
    }

    @MainActor
    func testUseFirstUnknownAndDetailsAndReminderPreferences() {
        let app = freshApp()
        launchDashboard(app)
        for (name, dated) in [("Day Four Undated", false), ("Day Four Due Today", true)] {
            app.tabBars.buttons["Home"].tap()
            app.buttons["Add Food"].tap()
            let field = app.textFields["addFood.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name + "\n")
            if dated {
                let expiry = app.switches["addFood.includesExpiry"]
                scrollFormTo(expiry, in: app)
                expiry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            app.buttons["addFood.save"].tap()
            XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        }
        scrollDayFourTo(app.buttons["See all"], in: app)
        app.buttons["See all"].tap()
        XCTAssertTrue(app.navigationBars["Use First"].waitForExistence(timeout: 5))
        capture("Day4 Use First", app: app)
        let due = app.buttons.containing(.staticText, identifier: "Day Four Due Today").firstMatch
        scrollDayFourTo(due, in: app)
        due.tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Day Four Due Today"].exists)
        app.navigationBars["Food Details"].buttons.element(boundBy: 0).tap()
        let undated = app.buttons.containing(.staticText, identifier: "Day Four Undated").firstMatch
        scrollDayFourTo(undated, in: app)
        XCTAssertTrue(undated.isHittable)
        capture("Day4 Unknown expiry", app: app)
        scrollDayFourTo(app.buttons["useFirst.expired"], in: app)
        app.buttons["useFirst.expired"].tap()
        XCTAssertTrue(app.navigationBars["Expired Items"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No expired items"].exists)
        capture("Day4 Expired empty", app: app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Expiry Reminders"].tap()
        XCTAssertTrue(app.navigationBars["Expiry Reminders"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["reminders.enabled"].value as? String, "0")
        capture("Day4 Reminders default off", app: app)
    }

    @MainActor
    func testReminderEnablementAndPreferencesPersist() {
        let app = freshApp()
        launchDashboard(app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Expiry Reminders"].tap()
        let enabled = app.switches["reminders.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        XCTAssertEqual(enabled.value as? String, "0")
        enabled.switches.firstMatch.exists ? enabled.switches.firstMatch.tap() : enabled.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(enabled.value as? String, "1")
        let threeDays = app.switches["Three days before"]
        XCTAssertTrue(threeDays.exists)
        scrollDayFourTo(threeDays, in: app)
        threeDays.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(threeDays.value as? String, "0")
        capture("Day4 Reminder settings", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Expiry Reminders"].tap()
        XCTAssertEqual(app.switches["reminders.enabled"].value as? String, "1")
        XCTAssertEqual(app.switches["Three days before"].value as? String, "0")
        app.switches["reminders.enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.datePickers.firstMatch.exists)
    }

    @MainActor
    func testConsumptionWasteHistoryAndRelaunch() {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        launchDashboard(app)
        for (name, action, confirmation) in [("History Rice", "foodDetails.consume", "Confirm Consumed"),
                                             ("History Bread", "foodDetails.waste", "Confirm Wasted")] {
            app.tabBars.buttons["Home"].tap()
            scrollDayFourTo(app.buttons["Add Food"], in: app)
            app.buttons["Add Food"].tap()
            let field = app.textFields["addFood.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name + "\n")
            app.buttons["addFood.save"].tap()
            XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Pantry"].tap()
            let card = app.buttons.containing(.staticText, identifier: name).firstMatch
            scrollDayFourTo(card, in: app)
            card.tap()
            XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
            scrollDayFourTo(app.buttons[action], in: app)
            app.buttons[action].tap()
            XCTAssertTrue(app.alerts["Record full item usage?"].waitForExistence(timeout: 5))
            app.alerts.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons[action].exists)
            app.buttons[action].tap()
            app.alerts.buttons[confirmation].tap()
            XCTAssertFalse(app.buttons[action].exists)
            XCTAssertTrue(app.staticTexts["This item is no longer active. Recorded history remains available in Insights."].exists)
            if name == "History Rice" {
                scrollDayFourTo(app.buttons["foodDetails.delete"], in: app)
                app.buttons["foodDetails.delete"].tap()
                app.alerts.buttons["Delete Food"].tap()
            } else {
                app.navigationBars["Food Details"].buttons.element(boundBy: 0).tap()
            }
            XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recorded outcomes"].exists)
        capture("Day4 Recorded Insights", app: app)
        scrollDayFourTo(app.staticTexts["History Rice"], in: app)
        XCTAssertTrue(app.staticTexts["History Rice"].isHittable)
        capture("Day4 Usage History", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        scrollDayFourTo(app.staticTexts["History Bread"], in: app)
        XCTAssertTrue(app.staticTexts["History Bread"].exists)
        scrollDayFourTo(app.staticTexts["History Rice"], in: app)
        XCTAssertTrue(app.staticTexts["History Rice"].exists)
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].exists)
    }

    @MainActor
    func testFoodRecognitionPhotoAndConfirmation() {
        let app = freshApp()
        openRecognitionWithLibraryPhoto(app)
        let error = app.staticTexts["recognition.error"]
        let form = app.navigationBars["Add Food"]
        expectation(for: NSPredicate { _, _ in error.exists || form.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        if error.exists {
            XCTAssertTrue(error.label.contains("Could not create inference context"))
            scrollTo(app.buttons["recognition.manual"], in: app)
            app.buttons["recognition.manual"].tap()
        }
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        scrollFormTo(app.textFields["addFood.quantity"], in: app)
        XCTAssertEqual(app.textFields["addFood.quantity"].value as? String, "Quantity")
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMockRecognitionCorrectionPersistsAcrossRelaunch() {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        app.launchEnvironment["PANTRYPULSE_RECOGNITION_TEST"] = "success"
        openRecognitionWithLibraryPhoto(app)
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["recognition.suggestion.Apple"].exists)
        let retake = app.buttons["Retake Photo"]
        scrollFormTo(retake, in: app)
        retake.tap()
        XCTAssertTrue(app.buttons["recognition.library"].waitForExistence(timeout: 5))
        app.buttons["recognition.library"].tap()
        let selectedImage = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(selectedImage.waitForExistence(timeout: 10))
        selectedImage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 10))
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Apple")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Corrected pear\n")
        let quantity = app.textFields["addFood.quantity"]
        scrollFormTo(quantity, in: app)
        XCTAssertEqual(quantity.value as? String, "Quantity")
        quantity.tap(); quantity.typeText("2")
        app.staticTexts["QUANTITY & UNITS"].tap()
        let storage = app.buttons["Store in Fridge"]
        scrollFormTo(storage, in: app)
        storage.tap()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Corrected pear"].exists)
        app.terminate(); app.launch()
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Corrected pear"].waitForExistence(timeout: 5))
        app.staticTexts["Corrected pear"].tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No photo added"].exists)
        capture("Mock recognition corrected and persisted", app: app)
    }

    @MainActor
    func testMockRecognitionAmbiguityAndFailureOfferManualEntry() {
        for scenario in ["ambiguous", "failure"] {
            let app = freshApp()
            app.launchEnvironment["PANTRYPULSE_RECOGNITION_TEST"] = scenario
            openRecognitionWithLibraryPhoto(app)
            if scenario == "ambiguous" {
                XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 10))
                let notice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Uncertain result")).firstMatch
                scrollFormTo(notice, in: app)
                XCTAssertTrue(notice.exists)
            } else {
                XCTAssertTrue(app.staticTexts["recognition.error"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["recognition.suggestion.Apple"].exists)
                scrollTo(app.buttons["recognition.manual"], in: app)
                app.buttons["recognition.manual"].tap()
            }
            XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Pantry"].tap()
            XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func openRecognitionWithLibraryPhoto(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        app.tabBars.buttons["Scan"].tap()
        app.buttons.containing(.staticText, identifier: "Recognize Food").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Recognize Food"].waitForExistence(timeout: 5))
        capture("Recognition entry", app: app)
        app.buttons["recognition.library"].tap()
        let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForNonExistence(timeout: 15))
    }

    @MainActor
    func testAppShellNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        launchDashboard(app)
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 5)

        scrollTo(app.buttons["See all"], in: app)
        app.buttons["See all"].tap()
        XCTAssertTrue(app.navigationBars["Use First"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No upcoming expiry dates"].exists)

        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Whole Milk"].exists, "Preview samples must not leak into the running app.")

        app.tabBars.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Recognize Food").firstMatch.exists)

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your insights begin here"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Expiry Reminders"].exists)

        // Home's push survives switching through every other tab.
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Use First"].waitForExistence(timeout: 5))
        app.navigationBars["Use First"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))

        // Native back updates the bound path rather than leaving a stale route behind.
        app.tabBars.buttons["Pantry"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["See all"].exists)
    }

    @MainActor
    func testDashboardActionsAndPantrySearchState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        launchDashboard(app)
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.buttons["Add Food"].tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["addFood.name"].exists)
        app.navigationBars["Add Food"].buttons.element(boundBy: 0).tap()
        app.buttons["home.notifications"].tap()
        XCTAssertTrue(app.navigationBars["Expiry Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["reminders.enabled"].exists)
        app.navigationBars["Expiry Reminders"].buttons.element(boundBy: 0).tap()
        app.buttons["home.profile"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Pantry"].tap()
        let search = app.textFields["pantry.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("milk\n")
        app.buttons["pantry.category.Fruits"].tap()
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertEqual(search.value as? String, "milk")
        XCTAssertTrue(app.buttons["pantry.category.Fruits"].isSelected)
        app.buttons["Clear search"].tap()
        app.buttons["pantry.category.All"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].exists)
        XCTAssertFalse(app.staticTexts["Whole Milk"].exists)
        scrollTo(app.buttons["Add Your First Food"], in: app)
        app.buttons["Add Your First Food"].tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["addFood.name"].exists)
    }

    @MainActor
    func testOnboardingCompletionPersists() {
        let app = freshApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Pantry, Smarter"].waitForExistence(timeout: 5))
        capture("Welcome", app: app)
        // An interrupted introduction must not count as completed.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Your Pantry, Smarter"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["Never Miss an Expiry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.page.1"].isSelected)
        let expiryTitle = app.staticTexts["Never Miss an Expiry"]
        XCTAssertGreaterThanOrEqual(expiryTitle.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(expiryTitle.frame.maxX, app.frame.maxX)
        capture("Expiry", app: app)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.staticTexts["Snap It. We'll Identify It."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.page.2"].isSelected)
        capture("Recognition", app: app)
        app.swipeRight()
        XCTAssertTrue(app.buttons["onboarding.page.1"].isSelected)
        app.buttons["onboarding.page.2"].tap()
        XCTAssertTrue(app.buttons["Get Started"].exists)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.skip"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 5)
    }

    @MainActor
    func testOnboardingSkipPersistsAndSupportingScreens() {
        let app = freshApp()
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Scan"].tap()
        capture("Scan choices", app: app)
        for title in ["Recognize Food", "Scan a Barcode", "Enter Manually"] {
            app.buttons.containing(.staticText, identifier: title).firstMatch.tap()
            let destination = title == "Enter Manually" ? "Add Food" : title == "Scan a Barcode" ? "Scan Product" : "Recognize Food"
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            if title == "Enter Manually" {
                XCTAssertTrue(app.textFields["addFood.name"].exists)
            } else if title == "Scan a Barcode" {
                XCTAssertTrue(app.staticTexts["Camera unavailable. Enter a barcode manually."].waitForExistence(timeout: 5))
            } else if destination == "Recognize Food" {
                XCTAssertTrue(app.buttons["recognition.library"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["Coming in a later phase"].exists)
            }
            app.navigationBars[destination].buttons.element(boundBy: 0).tap()
        }
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["Your insights begin here"].waitForExistence(timeout: 5))
        capture("Empty Insights", app: app)
        app.buttons["View My Pantry"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        capture("Settings", app: app)
        for (title, destination) in [("Default Storage", "Default Storage"), ("Expiry Reminders", "Expiry Reminders"), ("AI Recognition", "Recognize Food")] {
            app.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            if destination == "Expiry Reminders" {
                XCTAssertEqual(app.switches["reminders.enabled"].value as? String, "0")
            } else if destination == "Recognize Food" {
                XCTAssertTrue(app.buttons["recognition.library"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["Coming in a later phase"].exists)
            }
            app.navigationBars[destination].buttons.element(boundBy: 0).tap()
        }
        scrollTo(app.buttons["About PantryPulse"], in: app)
        app.buttons["About PantryPulse"].tap()
        XCTAssertTrue(app.navigationBars["About PantryPulse"].waitForExistence(timeout: 5))
        app.navigationBars["About PantryPulse"].buttons.element(boundBy: 0).tap()
        app.buttons["Review Introduction"].tap()
        XCTAssertTrue(app.staticTexts["Your Pantry, Smarter"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingAccessibilityText() {
        let app = freshApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        for (index, title) in ["Your Pantry, Smarter", "Never Miss an Expiry", "Snap It. We'll Identify It."].enumerated() {
            let heading = app.staticTexts[title]
            let settled = NSPredicate { _, _ in
                heading.exists && abs(heading.frame.minX - 24) < 0.5 && heading.frame.maxX <= app.frame.maxX
            }
            expectation(for: settled, evaluatedWith: nil)
            waitForExpectations(timeout: 5)
            scrollTo(heading, in: app)
            XCTAssertTrue(app.buttons["onboarding.continue"].isHittable)
            XCTAssertTrue(app.buttons["onboarding.skip"].isHittable)
            capture("Large text - " + title, app: app)
            let message = app.staticTexts["onboarding.message.\(index)"]
            let pageScroll = app.scrollViews.containing(.staticText, identifier: title).firstMatch
            pageScroll.swipeUp()
            XCTAssertTrue(message.isHittable, "The explanation must remain reachable by scrolling.")
            capture("Large text explanation - " + title, app: app)
            app.buttons["onboarding.continue"].tap()
        }
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyStateActionsClearTabBar() {
        let app = freshApp()
        launchDashboard(app)
        app.tabBars.buttons["Pantry"].tap()
        let add = app.buttons["Add Your First Food"]
        scrollTo(add, in: app)
        XCTAssertLessThanOrEqual(add.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Redesigned empty pantry", app: app)
        add.tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        let pantry = app.buttons["View My Pantry"]
        scrollTo(pantry, in: app)
        XCTAssertLessThanOrEqual(pantry.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Redesigned empty insights", app: app)
        pantry.tap()
        XCTAssertTrue(app.tabBars.buttons["Pantry"].isSelected)
    }

    @MainActor
    func testScreenContentRemainsReachableAboveTabBar() {
        let app = freshApp()
        launchDashboard(app)
        let screens: [(String, String)] = [
            ("Home", "Expiry summaries use supplied dates only; they are not model predictions."),
            ("Pantry", "Scan, photograph, or enter food manually."),
            ("Scan", "Scan a barcode or enter it manually to look up packaged food. Camera access is requested only when you open the scanner."),
            ("Insights", "Insights describe your recorded history. No savings, environmental impact or ML risk is estimated."),
            ("Settings", "About PantryPulse")
        ]
        for (tab, lastText) in screens {
            app.tabBars.buttons[tab].tap()
            capture("\(tab) top", app: app)
            let element = tab == "Settings" ? app.buttons[lastText] : app.staticTexts[lastText]
            for _ in 0..<10 {
                if element.isHittable && element.frame.maxY <= app.tabBars.firstMatch.frame.minY { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.isHittable, "\(tab) bottom content must be reachable")
            XCTAssertLessThanOrEqual(element.frame.maxY, app.tabBars.firstMatch.frame.minY,
                                     "\(tab) bottom content must scroll clear of the tab bar")
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
            capture("\(tab) bottom", app: app)
        }
    }


    @MainActor
    func testBarcodeManualInvalidAndCancellation() {
        let app = freshApp()
        app.launch()
        app.buttons["onboarding.skip"].tap()
        app.tabBars.buttons["Scan"].tap()
        app.buttons.containing(.staticText, identifier: "Scan a Barcode").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable. Enter a barcode manually."].waitForExistence(timeout: 5))
        capture("Barcode scanner unavailable on Simulator", app: app)
        scrollTo(app.buttons["barcode.manual"], in: app)
        app.buttons["barcode.manual"].tap()
        let input = app.textFields["barcode.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("123")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        scrollTo(app.buttons["barcode.lookup"], in: app)
        app.buttons["barcode.lookup"].tap()
        scrollTo(app.staticTexts["barcode.error"], in: app)
        XCTAssertTrue(app.staticTexts["barcode.error"].waitForExistence(timeout: 5))
        capture("Manual barcode validation", app: app)
        app.buttons["barcode.cancel"].tap()
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testManualProductConfirmationAndCatalogueRelaunch() throws {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        launchDashboard(app)
        func lookup() {
            app.tabBars.buttons["Scan"].tap()
            app.buttons.containing(.staticText, identifier: "Scan a Barcode").firstMatch.tap()
            scrollTo(app.buttons["barcode.manual"], in: app)
            app.buttons["barcode.manual"].tap()
            let input = app.textFields["barcode.input"]
            input.tap(); input.typeText("00310062004566")
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            scrollTo(app.buttons["barcode.lookup"], in: app)
            app.buttons["barcode.lookup"].tap()
        }
        lookup()
        let manual = app.buttons["Enter Details Manually"]
        scrollTo(manual, in: app)
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        let name = app.textFields["label.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Brinjals")
        app.buttons["Done"].tap()
        let amount = app.textFields["label.quantity"]
        scrollTo(amount, in: app)
        amount.tap(); amount.typeText("0.456 kg")
        app.buttons["Done"].tap()
        XCTAssertEqual(amount.value as? String, "0.456 kg")
        let useQuantity = app.switches["label.useQuantity"]
        scrollFormTo(useQuantity, in: app, hasFixedSave: false)
        XCTAssertTrue(useQuantity.isEnabled)
        useQuantity.switches.firstMatch.exists ? useQuantity.switches.firstMatch.tap() : useQuantity.tap()
        XCTAssertEqual(useQuantity.value as? String, "1")
        capture("Label quantity accepted", app: app)
        scrollTo(app.buttons["label.continue"], in: app)
        app.buttons["label.continue"].tap()
        let brand = app.textFields["Brand (optional)"]
        scrollFormTo(brand, in: app)
        brand.tap(); brand.typeText("Packaging confirmation\n")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let quantity = app.textFields["addFood.quantity"]
        scrollTo(quantity, in: app)
        XCTAssertEqual(quantity.value as? String, "0.456")
        app.buttons["addFood.save"].tap()
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Brinjals"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        lookup()
        XCTAssertTrue(app.staticTexts["barcode.productName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["barcode.productName"].label, "Brinjals")
        capture("Confirmed local product after relaunch", app: app)
    }

    @MainActor
    func testUnknownBarcodeOffersUnifiedFallbackWithoutSaving() {
        let app = freshApp()
        launchDashboard(app)
        app.tabBars.buttons["Scan"].tap()
        app.buttons.containing(.staticText, identifier: "Scan a Barcode").firstMatch.tap()
        scrollTo(app.buttons["barcode.manual"], in: app)
        app.buttons["barcode.manual"].tap()
        let input = app.textFields["barcode.input"]
        input.tap(); input.typeText("00999999003586")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        scrollTo(app.buttons["barcode.lookup"], in: app)
        app.buttons["barcode.lookup"].tap()
        let fallback = app.buttons["Enter Details Manually"]
        scrollTo(fallback, in: app)
        fallback.tap()
        XCTAssertTrue(app.staticTexts["Product details need confirmation."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["label.name"].value as? String, "Product name")
        scrollFormTo(app.buttons["Scan Product Label"], in: app, hasFixedSave: false)
        XCTAssertTrue(app.buttons["Scan Product Label"].isHittable)
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
    }

    /// Integration check against the real public service; no successful response is injected into the app.
    @MainActor
    func testLiveBarcodeConfirmationSaveAndRelaunch() throws {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        app.launch()
        app.buttons["onboarding.skip"].tap()
        app.tabBars.buttons["Scan"].tap()
        app.buttons.containing(.staticText, identifier: "Scan a Barcode").firstMatch.tap()
        scrollTo(app.buttons["barcode.manual"], in: app)
        app.buttons["barcode.manual"].tap()
        let input = app.textFields["barcode.input"]
        input.tap(); input.typeText("3017620422003")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        scrollTo(app.buttons["barcode.lookup"], in: app)
        app.buttons["barcode.lookup"].tap()
        XCTAssertTrue(app.staticTexts["barcode.productName"].waitForExistence(timeout: 30), "Real Open Food Facts lookup failed: " + app.debugDescription)
        let photoToggle = app.switches["Use this product photo"]
        XCTAssertTrue(photoToggle.waitForExistence(timeout: 30), "The live product photo did not load.")
        capture("Product Found from live API", app: app)
        // Retrieving a product is not a save.
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is ready!"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Scan"].tap()
        let next = app.buttons["barcode.continue"]
        scrollTo(next, in: app)
        XCTAssertTrue(next.waitForExistence(timeout: 25))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: next)
        waitForExpectations(timeout: 25)
        next.tap()
        XCTAssertTrue(app.navigationBars["Add Food"].waitForExistence(timeout: 5))
        let name = app.textFields["addFood.name"]
        scrollFormTo(name, in: app)
        name.tap()
        let original = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "Barcode audit food\n")
        let quantity = app.textFields["addFood.quantity"]
        scrollFormTo(quantity, in: app)
        quantity.tap(); quantity.typeText("2")
        app.staticTexts["QUANTITY & UNITS"].tap()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Barcode audit food"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        let total = app.descendants(matching: .any)["home.total"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("1"), total.label)
        capture("Dashboard after confirmed barcode save", app: app)
        app.terminate(); app.launch()
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Barcode audit food"].waitForExistence(timeout: 5))
        app.staticTexts["Barcode audit food"].tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        capture("Saved barcode food after relaunch", app: app)
    }

    @MainActor
    private func freshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        return app
    }

    @MainActor
    private func launchDashboard(_ app: XCUIApplication) {
        if app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] == nil {
            app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        }
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollDayFourTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<25 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.tabBars.firstMatch.frame.minY
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let middle = top + (bottom - top) * 0.5
            let back = element.exists && element.frame.minY < top
            origin.withOffset(CGVector(dx: 24, dy: middle)).press(forDuration: 0.01,
                thenDragTo: origin.withOffset(CGVector(dx: 24, dy: middle + (back ? 100 : -100))))
        }
        XCTFail("Day 4 control is not reachable: \(element)")
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func scrollFormTo(_ element: XCUIElement, in app: XCUIApplication, hasFixedSave: Bool = true) {
        for _ in 0..<20 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let footer = app.buttons["addFood.save"]
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY
                : hasFixedSave && footer.exists && footer.isHittable ? footer.frame.minY
                : app.tabBars.firstMatch.frame.minY
            if element.exists, element.isHittable,
               element.frame.minY >= top, element.frame.maxY <= bottom {
                return
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let middle = top + (bottom - top) * 0.5
            let distance = min(120, (bottom - top) * 0.3)
            let scrollBack = element.exists && element.frame.minY < top
            let start = origin.withOffset(CGVector(dx: 30, dy: middle))
            let end = origin.withOffset(CGVector(dx: 30, dy: middle + (scrollBack ? distance : -distance)))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTFail("Form control was not reachable: \(element)")
    }

    @MainActor
    func testFoodPhotoPickerAndUnavailableCamera() {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        app.buttons["Add Food"].tap()
        let photo = app.buttons["addFood.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.staticTexts["addFood.photoError"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Choose from Photo Library"].tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 5))
        app.navigationBars["Photos"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForNonExistence(timeout: 5))
        app.buttons["photoSource.cancel"].tap()
        XCTAssertFalse(app.buttons["Remove Photo"].exists)

        let name = app.textFields["addFood.name"]
        name.tap()
        name.typeText("Photo workflow")
        app.scrollViews.firstMatch.swipeDown() // Dismiss the keyboard by scrolling the form.
        app.swipeDown()

        func choosePhoto() {
            photo.tap()
            app.buttons["Choose from Photo Library"].tap()
            let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
            XCTAssertTrue(image.waitForExistence(timeout: 5))
            image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["Photos"].waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Remove Photo"].waitForExistence(timeout: 10))
        }
        choosePhoto()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Pantry"].tap()
        let card = app.buttons.containing(.staticText, identifier: "Photo workflow").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.images["Food photo"].waitForExistence(timeout: 5))
        capture("Saved food photo after relaunch", app: app)
        scrollTo(app.buttons["Edit Food"], in: app)
        app.buttons["Edit Food"].tap()
        choosePhoto()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.images["Food photo"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Edit Food"], in: app)
        app.buttons["Edit Food"].tap()
        app.buttons["Remove Photo"].tap()
        app.navigationBars["Edit Food"].buttons.element(boundBy: 0).tap()
        app.swipeDown()
        XCTAssertTrue(app.images["Food photo"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Edit Food"], in: app)
        app.buttons["Edit Food"].tap()
        app.buttons["Remove Photo"].tap()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["No photo added"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddFoodValidationAndSaveWithoutExpiry() {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        launchDashboard(app)
        app.buttons["Add Food"].tap()
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("Add Food form", app: app)
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.alerts["Unable to add food"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Enter a food name."].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Add Food"].exists)
        name.tap()
        name.typeText("Test Rice")
        app.staticTexts["FOOD NAME"].tap()
        let quantity = app.textFields["addFood.quantity"]
        scrollFormTo(quantity, in: app)
        quantity.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.5)).tap()
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        XCTAssertEqual(quantity.value as? String, "0")
        app.staticTexts["QUANTITY & UNITS"].tap()
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.staticTexts["Quantity must be a finite number greater than zero."].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        scrollFormTo(quantity, in: app)
        quantity.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.5)).tap()
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        XCTAssertEqual(quantity.value as? String, "2")
        app.staticTexts["QUANTITY & UNITS"].tap()
        let expiry = app.switches["addFood.includesExpiry"]
        scrollFormTo(expiry, in: app)
        XCTAssertEqual(expiry.value as? String, "0")
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Test Rice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Your pantry is ready!"].exists)
        capture("Saved food in Pantry", app: app)
    }

    @MainActor
    func testAddFoodWithExpiryAndCancelDoesNotSave() {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        launchDashboard(app)
        app.tabBars.buttons["Scan"].tap()
        app.buttons["Enter Manually"].tap()
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test Yogurt")
        app.scrollViews.firstMatch.swipeDown() // Dismiss the keyboard by scrolling the form.
        let expiry = app.switches["addFood.includesExpiry"]
        scrollFormTo(expiry, in: app)
        expiry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(expiry.value as? String, "1")
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Test Yogurt"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Add Food"], in: app)
        app.buttons["Add Food"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Unsaved food")
        app.navigationBars["Add Food"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unsaved food"].exists)
    }

    @MainActor
    func testAddFoodAccessibilityLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_ACCOUNT"] = "fixture-a"
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchDashboard(app)
        scrollTo(app.buttons["Add Food"], in: app)
        app.buttons["Add Food"].tap()
        XCTAssertTrue(app.textFields["addFood.name"].waitForExistence(timeout: 5))
        capture("Add Food accessibility text", app: app)
        let notes = app.descendants(matching: .any).matching(identifier: "addFood.notes").firstMatch
        scrollFormTo(notes, in: app, hasFixedSave: false)
        capture("Add Food notes accessibility text", app: app)
        scrollFormTo(app.buttons["addFood.save"], in: app, hasFixedSave: false)
        XCTAssertTrue(app.buttons["addFood.save"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["addFood.save"].frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("Add Food save accessibility text", app: app)
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.alerts["Unable to add food"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testInventoryManagementSearchFilterSortAndRelaunch() {
        let app = freshApp()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DISK"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        for (name, hasExpiry) in [("Phase D Rice", false), ("Phase D Yogurt", true)] {
            app.tabBars.buttons["Home"].tap()
            scrollTo(app.buttons["Add Food"], in: app)
            app.buttons["Add Food"].tap()
            let field = app.textFields["addFood.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name + "\n")
            XCTAssertTrue(app.buttons["addFood.save"].waitForExistence(timeout: 5))
            if hasExpiry {
                let expiry = app.switches["addFood.includesExpiry"]
                scrollFormTo(expiry, in: app)
                expiry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                XCTAssertEqual(expiry.value as? String, "1")
            }
            app.buttons["addFood.save"].tap()
            XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home Dashboard"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Pantry"].tap()
        for (name, expiry) in [("Phase D Rice", "No expiry date"), ("Phase D Yogurt", "Expires today")] {
            let card = app.buttons.containing(.staticText, identifier: name).firstMatch
            scrollTo(card, in: app)
            XCTAssertTrue(card.exists)
            card.tap()
            XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["foodDetails.name"].label, name)
            XCTAssertTrue(app.staticTexts["Other"].exists)
            scrollTo(app.staticTexts["1 pieces"], in: app)
            XCTAssertTrue(app.staticTexts["1 pieces"].exists)
            scrollTo(app.staticTexts[expiry].firstMatch, in: app)
            XCTAssertTrue(app.staticTexts[expiry].firstMatch.exists)
            capture(name + " details after relaunch", app: app)
            app.navigationBars["Food Details"].buttons.element(boundBy: 0).tap()
        }
        let rice = app.buttons.containing(.staticText, identifier: "Phase D Rice").firstMatch
        scrollTo(rice, in: app)
        rice.tap()
        scrollTo(app.buttons["Edit Food"], in: app)
        app.buttons["Edit Food"].tap()
        let name = app.textFields["addFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Phase D Rice".count) + "Brown Rice\n")
        XCTAssertTrue(app.buttons["addFood.save"].waitForExistence(timeout: 5))
        app.buttons["addFood.save"].tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        app.swipeDown()
        app.swipeDown()
        XCTAssertEqual(app.staticTexts["foodDetails.name"].label, "Brown Rice")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Pantry"].tap()
        let search = app.textFields["pantry.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bRoWn\n")
        XCTAssertTrue(app.staticTexts["Brown Rice"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Phase D Yogurt"].exists)
        app.buttons["pantry.category.Fruits"].tap()
        XCTAssertTrue(app.staticTexts["No matching food"].waitForExistence(timeout: 3))
        app.buttons["pantry.category.All"].tap()
        XCTAssertTrue(app.staticTexts["Brown Rice"].waitForExistence(timeout: 3))
        app.buttons["Clear search"].tap()
        for order in ["Name (A–Z)", "Name (Z–A)", "Recently added", "Expiry (soonest)"] {
            app.buttons["pantry.sort"].tap()
            app.buttons[order].tap()
            XCTAssertTrue(app.buttons["pantry.sort"].label.contains(order))
            let first = app.staticTexts["Brown Rice"].frame
            let second = app.staticTexts["Phase D Yogurt"].frame
            if order == "Name (A–Z)" {
                XCTAssertTrue(first.minY < second.minY || (first.minY == second.minY && first.minX < second.minX))
            } else {
                XCTAssertTrue(second.minY < first.minY || (second.minY == first.minY && second.minX < first.minX))
            }
        }
        app.buttons.containing(.staticText, identifier: "Brown Rice").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Food Details"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["foodDetails.delete"], in: app)
        app.buttons["foodDetails.delete"].tap()
        XCTAssertTrue(app.alerts["Delete this food?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.navigationBars["Food Details"].exists)
        app.buttons["foodDetails.delete"].tap()
        app.alerts.buttons["Delete Food"].tap()
        XCTAssertTrue(app.navigationBars["My Pantry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Brown Rice"].exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Phase D Yogurt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Brown Rice"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = freshApp()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
