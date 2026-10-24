//
//  PantryPulseUITestsLaunchTests.swift
//  PantryPulseUITests
//
//  Created by Thisaja Mudalige on 2026-10-14.
//

import XCTest

final class PantryPulseUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PANTRYPULSE_UI_TEST_DEFAULTS"] = "PantryPulse.UITests." + UUID().uuidString
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
