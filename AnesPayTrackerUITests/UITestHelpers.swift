import XCTest

// Shared steps for the UI tests. The app is always launched in its test-only
// mode (see AnesPayTracker/App/UITestSupport.swift), which uses a separate
// store filled with made-up data.

@MainActor
extension XCTestCase {

    /// Launches the app with the made-up invoice scenario. `keepStore` reuses
    /// the data from the previous launch instead of starting fresh.
    @discardableResult
    func launchApp(keepStore: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", "invoices"] + (keepStore ? ["-UITestKeepStore", "YES"] : [])
        app.launch()
        return app
    }

    /// Saves a screenshot into the test results for the report.
    func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps Allow on the system notification prompt if it appears.
    func allowNotificationsIfAsked(timeout: TimeInterval = 4) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: timeout) {
            allow.tap()
        }
    }

    func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab \(name) should exist")
        tab.tap()
    }

    /// The first element of `query` whose label contains `text`.
    func element(_ query: XCUIElementQuery, containing text: String) -> XCUIElement {
        query.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func text(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Scrolls up until `target` is on screen, for rows further down a list.
    @discardableResult
    func scrollTo(_ target: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return target.exists
    }

    func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "A back button should exist")
        back.tap()
    }
}
