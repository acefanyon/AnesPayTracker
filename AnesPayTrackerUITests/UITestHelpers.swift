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

    /// Flips a switch by tapping the switch itself. In a Form the switch
    /// element spans the whole row, and a tap in its middle lands on the label.
    func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists && inner.frame.width < toggle.frame.width {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    /// Waits for `element`; if it never appears, fails with a list of what is
    /// on screen, so the cause can be read from the log without screenshots.
    func require(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.waitForExistence(timeout: timeout) { return }
        let kinds = ["Button", "Switch", "Alert", "Sheet", "StaticText", "NavigationBar", "Other, identifier"]
        let onScreen = app.debugDescription
            .split(separator: "\n")
            .filter { line in kinds.contains { line.contains($0) } }
            .prefix(80)
            .joined(separator: "\n")
        XCTFail("\(message)\nOn screen:\n\(onScreen)", file: file, line: line)
    }

    func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "A back button should exist")
        back.tap()
    }
}
