//
// LockUnlockUITests.swift
// UI tests for the Notch lock/unlock feature
//
import XCTest

final class LockUnlockUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Ensure the app starts with a clean state
        app.launchArguments.append("-reset")
        app.launch()
    }

    func testLockToggle() throws {
        // Open Settings (⌘, is the default shortcut)
        let cmd = XCUIKeyboardKeyCommand(key: ",", modifierFlags: .command)
        app.typeKeyCommand(cmd)
        // Wait for Settings window
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

        // Find the "Show notch lock" toggle
        let lockToggle = settingsWindow.checkBoxes["Show notch lock"]
        XCTAssertTrue(lockToggle.waitForExistence(timeout: 2))

        // Ensure it is on (default true). Turn it off and on again.
        if lockToggle.value as? String == "1" { // checked
            lockToggle.click()
        }
        // Turn back on
        lockToggle.click()
        XCTAssertEqual(lockToggle.value as? String, "1")

        // Close Settings
        app.keyboards.buttons["Escape"].click()
        // Verify lock button appears in the notch when expanded
        // Expand the notch by tapping the pill
        let notch = app.otherElements["Dynamic Notch"]
        XCTAssertTrue(notch.waitForExistence(timeout: 3))
        notch.click()
        // Look for lock icon (system name "lock.open" or "lock.fill")
        let lockButton = notch.buttons["lock.open"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 2))
    }
}
