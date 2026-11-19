import XCTest

/// QA plan section C14 (invoice reminders and payment tracking), run in the
/// made-up scenario from UITestSupport:
/// - Case Group: invoiced every 2 weeks; its last period ended 3 days ago with
///   two shifts not yet invoiced ($3,206.67 + $2,000.00 = $5,206.67), and one
///   older invoice whose due date has passed.
/// - Day Rate Partners: no invoice reminders, pay periods not set up.
final class InvoiceRemindersUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// C14: Home shows the due period; Create opens the form with that
    /// employer and those dates; creating the invoice clears the reminder.
    @MainActor
    func test01_InvoiceDueOnHomeCreatesPrefilledInvoice() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Invoice due"].waitForExistence(timeout: 15), "Home should show an Invoice due card")
        XCTAssertTrue(text(app, containing: "2 shifts").exists, "The due card should count the 2 uninvoiced shifts")
        XCTAssertTrue(text(app, containing: "$5,206.67").exists, "The due card should total $5,206.67")
        XCTAssertEqual(app.buttons.matching(identifier: "invoiceDue.create").count, 1, "Only Case Group is due; Day Rate Partners has no reminders")
        screenshot(app, "01 Home shows Invoice due")

        app.buttons["invoiceDue.create"].tap()
        XCTAssertTrue(app.navigationBars["New Invoice"].waitForExistence(timeout: 10), "Create should open the New Invoice form")
        screenshot(app, "02 New Invoice opened from the reminder")

        let total = text(app, containing: "$5,206.67")
        XCTAssertTrue(scrollTo(total, in: app), "The form should total the due period's two shifts ($5,206.67)")
        screenshot(app, "03 New Invoice summary")

        let create = app.navigationBars["New Invoice"].buttons["Create"]
        XCTAssertTrue(create.isEnabled, "Create should be enabled (your details are filled in)")
        create.tap()

        XCTAssertTrue(app.staticTexts["Total due"].waitForExistence(timeout: 10), "The new invoice should open")
        XCTAssertTrue(text(app, containing: "$5,206.67").exists, "The new invoice should total $5,206.67")
        screenshot(app, "04 New invoice opened")

        goBack(app) // invoice → list
        goBack(app) // list → Home
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Invoice due"].exists, "The due card should be gone once the invoice exists")
        screenshot(app, "05 Home after creating the invoice")
    }

    /// C14: schedule options and turning reminders off.
    @MainActor
    func test02_ReminderSettings() {
        let app = launchApp()
        openTab(app, "Settings")
        let reminders = app.buttons["Reminders & Payments"]
        XCTAssertTrue(reminders.waitForExistence(timeout: 10), "Settings should link to Reminders & Payments")
        reminders.tap()
        XCTAssertTrue(text(app, containing: "Every 2 weeks").waitForExistence(timeout: 10), "Case Group should show Every 2 weeks")
        screenshot(app, "06 Reminders & Payments")

        // Day Rate Partners' pay periods aren't set up, so "Each pay period" isn't offered.
        element(app.buttons, containing: "Day Rate Partners").tap()
        let dayRatePicker = element(app.buttons, containing: "Remind me to invoice")
        XCTAssertTrue(dayRatePicker.waitForExistence(timeout: 10))
        dayRatePicker.tap()
        XCTAssertTrue(app.buttons["Every month"].waitForExistence(timeout: 5), "The schedule menu should open")
        XCTAssertFalse(app.buttons["Each pay period"].exists, "Each pay period needs real pay-period dates")
        screenshot(app, "07 Day Rate Partners schedule options")
        app.buttons["Off"].tap()
        goBack(app)

        // Case Group's pay periods are set up, so it is offered.
        element(app.buttons, containing: "Case Group").tap()
        let picker = element(app.buttons, containing: "Remind me to invoice")
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, containing: "Current period").exists, "The current period should be shown")
        screenshot(app, "08 Case Group every 2 weeks")
        picker.tap()
        XCTAssertTrue(app.buttons["Each pay period"].waitForExistence(timeout: 5), "Each pay period should be offered for Case Group")
        app.buttons["Every month"].tap()
        XCTAssertTrue(text(app, containing: "Current period").waitForExistence(timeout: 5))
        XCTAssertFalse(app.datePickers["A period ends on"].exists, "Monthly schedules don't need a period end date")
        screenshot(app, "09 Case Group every month")

        element(app.buttons, containing: "Remind me to invoice").tap()
        app.buttons["Off"].tap()
        XCTAssertFalse(text(app, containing: "Current period").exists, "Turning reminders off hides the schedule details")
        screenshot(app, "10 Case Group reminders off")

        openTab(app, "Home")
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Invoice due"].exists, "With reminders off, nothing is due on Home")
        screenshot(app, "11 Home with reminders off")
    }

    /// C14: payment tracking on, Unpaid/Overdue, marking paid, and that it is
    /// still paid after the app is closed and reopened.
    @MainActor
    func test03_PaymentTracking() {
        let app = launchApp()
        openTab(app, "Settings")
        app.buttons["Reminders & Payments"].tap()

        let tracking = app.switches["Track invoice payments"]
        XCTAssertTrue(tracking.waitForExistence(timeout: 10))
        XCTAssertEqual(tracking.value as? String, "0", "Payment tracking should be off by default")
        flip(tracking)

        let leaveUnpaid = app.buttons["Leave Them Unpaid"]
        require(leaveUnpaid, in: app, "Turning tracking on should offer to mark existing invoices paid")
        XCTAssertTrue(app.buttons["Mark 1 as Paid Today"].exists, "Both choices should be visible")
        screenshot(app, "12 Mark existing invoices as paid?")
        leaveUnpaid.tap()
        // The notification prompt comes after the answer, never on top of it.
        allowNotificationsIfAsked()
        XCTAssertEqual(tracking.value as? String, "1", "Payment tracking should now be on")

        openTab(app, "Home")
        let unpaidCard = app.buttons["invoices.unpaidCard"]
        require(unpaidCard, in: app, "Home should show the unpaid invoice")
        XCTAssertTrue(text(app, containing: "1 overdue").exists, "The old invoice is past its due date")
        screenshot(app, "13 Home shows unpaid invoice")

        unpaidCard.tap()
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 10), "The list should mark it Overdue")
        screenshot(app, "14 Invoice list shows Overdue")

        element(app.buttons, containing: "CG-").tap()
        let paid = app.switches["invoice.paidToggle"]
        require(paid, in: app, "The invoice should have a Paid switch")
        flip(paid)
        XCTAssertTrue(text(app, containing: "Paid ").waitForExistence(timeout: 5), "The invoice should show Paid with a date")
        XCTAssertTrue(app.datePickers["Paid on"].exists, "A paid date should appear")
        screenshot(app, "15 Invoice marked paid")

        // Close and reopen with the same data.
        app.terminate()
        let reopened = launchApp(keepStore: true)
        XCTAssertTrue(reopened.navigationBars["Home"].waitForExistence(timeout: 15))
        XCTAssertFalse(reopened.buttons["invoices.unpaidCard"].exists, "Nothing should be unpaid after reopening")
        openTab(reopened, "Report")
        let invoicesLink = reopened.buttons["report.invoicesLink"]
        XCTAssertTrue(invoicesLink.waitForExistence(timeout: 10))
        invoicesLink.tap()
        XCTAssertTrue(text(reopened, containing: "Paid ").waitForExistence(timeout: 10), "The invoice should still be Paid after reopening")
        screenshot(reopened, "16 Still paid after reopening")
    }

    /// Smoke check: every tab still opens with the scenario's data.
    @MainActor
    func test04_EveryTabOpens() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        screenshot(app, "17 Home")
        for tab in ["Calendar", "Pay Periods", "Report", "Settings"] {
            openTab(app, tab)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), "\(tab) should open")
            screenshot(app, "18 \(tab)")
        }
    }
}
