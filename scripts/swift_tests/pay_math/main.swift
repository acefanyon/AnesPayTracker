// Runs the app's real pay math, outside the app. macOS/Linux with a Swift toolchain:
//
//   swiftc -o /tmp/pay_math_tests \
//     AnesPayTracker/Engine/CaseTimeCalculator.swift \
//     AnesPayTracker/Engine/PaycheckDateMath.swift \
//     AnesPayTracker/Engine/InvoiceMath.swift \
//     AnesPayTracker/Engine/InvoiceScheduleMath.swift \
//     scripts/swift_tests/pay_math/main.swift && /tmp/pay_math_tests
//
// CI runs this on every push. All names and amounts here are made up.

import Foundation

var failures = 0

func check<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name): expected \(expected), got \(actual)")
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Phoenix")!

func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

func shiftCase(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int, day: Int = 11) -> ShiftCase {
    ShiftCase(startAt: at(2026, 11, day, startHour, startMinute), endAt: at(2026, 11, day, endHour, endMinute))
}

func money(_ text: String) -> Decimal { Decimal(string: text)! }

// MARK: Minutes

let day = [
    shiftCase(7, 30, 9, 14),    // 104
    shiftCase(9, 40, 11, 5),    // 85
    shiftCase(11, 30, 13, 52),  // 142
    shiftCase(14, 10, 16, 10),  // 120
]
check(CaseTimeCalculator.totalMinutes(day), 451, "four cases add up to 7 h 31 m")
check(CaseTimeCalculator.minutes(of: shiftCase(8, 0, 8, 0)), 0, "zero-length case counts nothing")
check(CaseTimeCalculator.minutes(of: ShiftCase(startAt: at(2026, 11, 11, 8, 3), endAt: at(2026, 11, 11, 8, 3), isRunning: true)), 0, "running case counts nothing until stopped")
check(CaseTimeCalculator.minutes(of: ShiftCase(startAt: at(2026, 11, 11, 10, 0), endAt: at(2026, 11, 11, 9, 0))), 0, "end before start never goes negative")
check(CaseTimeCalculator.minutes(of: ShiftCase(startAt: at(2026, 11, 11, 8, 3, 59), endAt: at(2026, 11, 11, 9, 47, 1))), 104, "seconds are dropped: 8:03–9:47 is 104 minutes")
check(CaseTimeCalculator.truncatedToMinute(at(2026, 11, 11, 8, 3, 59)), at(2026, 11, 11, 8, 3), "truncate to the minute")
check(CaseTimeCalculator.minutes(of: ShiftCase(startAt: at(2026, 11, 11, 23, 30), endAt: at(2026, 11, 12, 0, 45))), 75, "case across midnight")

// MARK: Pay

check(CaseTimeCalculator.pay(rate: 400, paidMinutes: 451), money("3006.67"), "7 h 31 m at $400/hr = $3,006.67")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: 450), money("3000"), "7 h 30 m at $400/hr = $3,000.00")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: 1), money("6.67"), "1 minute at $400/hr = $6.67")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: 2), money("13.33"), "2 minutes at $400/hr = $13.33")
check(CaseTimeCalculator.pay(rate: 100, paidMinutes: 1), money("1.67"), "1 minute at $100/hr = $1.67")
check(CaseTimeCalculator.pay(rate: money("0.30"), paidMinutes: 1), money("0.01"), "exactly half a cent rounds up")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: 0), money("0"), "no minutes, no pay")

// MARK: Daily minimum

check(CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: 4), 240, "light day is raised to the 4 h minimum")
check(CaseTimeCalculator.paidMinutes(caseMinutes: 451, minimumHours: 4), 451, "a full day is not changed by the minimum")
check(CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: nil), 150, "no minimum set")
check(CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: 0), 150, "zero minimum is no minimum")
check(CaseTimeCalculator.paidMinutes(caseMinutes: 100, minimumHours: 2.5), 150, "half-hour minimums")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: 4)), money("1600"), "light day with 4 h minimum at $400/hr = $1,600.00")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: 5)), money("2000"), "half-day minimum: 5 h at $400/hr = $2,000.00")
check(CaseTimeCalculator.pay(rate: 400, paidMinutes: CaseTimeCalculator.paidMinutes(caseMinutes: 150, minimumHours: nil)), money("1000"), "minimum switched off for the day: 2 h 30 m = $1,000.00")

// MARK: Validation

check(CaseTimeCalculator.blockingProblem(in: day) == nil, true, "a clean day has no problems")
check(CaseTimeCalculator.blockingProblem(in: [shiftCase(9, 40, 11, 5), shiftCase(7, 30, 9, 14)]) == nil, true, "entry order does not matter")
check(CaseTimeCalculator.blockingProblem(in: [shiftCase(7, 30, 9, 14), shiftCase(9, 14, 10, 0)]) == nil, true, "back-to-back cases are fine")
check(CaseTimeCalculator.blockingProblem(in: [shiftCase(7, 30, 9, 14), shiftCase(9, 0, 10, 0)]) != nil, true, "overlapping cases are blocked")
let running = ShiftCase(startAt: at(2026, 11, 11, 8, 0), endAt: at(2026, 11, 11, 8, 0), isRunning: true)
check(CaseTimeCalculator.blockingProblem(in: [shiftCase(7, 0, 7, 45), running]) == nil, true, "a running last case is fine")
check(CaseTimeCalculator.blockingProblem(in: [running, shiftCase(9, 0, 10, 0)]) != nil, true, "a running case must be last")
check(CaseTimeCalculator.blockingProblem(in: [running, ShiftCase(startAt: at(2026, 11, 11, 9, 0), endAt: at(2026, 11, 11, 9, 0), isRunning: true)]) != nil, true, "two running cases are blocked")
check(CaseTimeCalculator.warning(in: day) == nil, true, "normal cases have no warning")
check(CaseTimeCalculator.warning(in: [shiftCase(7, 0, 20, 0)]) != nil, true, "a 13 h case is flagged")
check(CaseTimeCalculator.sorted([shiftCase(9, 40, 11, 5), shiftCase(7, 30, 9, 14)]).map { CaseTimeCalculator.minutes(of: $0) }, [104, 85], "cases sort chronologically")

// MARK: Time editing

check(CaseTimeCalculator.end(atTimeOf: at(2026, 1, 1, 9, 47), forStart: at(2026, 11, 11, 8, 3), calendar: calendar), at(2026, 11, 11, 9, 47), "end time lands on the start's day")
check(CaseTimeCalculator.end(atTimeOf: at(2026, 1, 1, 0, 45), forStart: at(2026, 11, 11, 23, 30), calendar: calendar), at(2026, 11, 12, 0, 45), "end before start means past midnight")
check(CaseTimeCalculator.end(atTimeOf: at(2026, 1, 1, 8, 3), forStart: at(2026, 11, 11, 8, 3), calendar: calendar), at(2026, 11, 11, 8, 3), "equal start and end stays zero-length, not 24 h")
check(CaseTimeCalculator.time(of: at(2026, 1, 1, 7, 15), onDayOf: at(2026, 11, 11, 13, 0), calendar: calendar), at(2026, 11, 11, 7, 15), "start time lands on the case's day")
let moved = CaseTimeCalculator.moving([shiftCase(7, 30, 9, 14), ShiftCase(startAt: at(2026, 11, 11, 23, 30), endAt: at(2026, 11, 12, 0, 45))], toDay: at(2026, 11, 13, 15, 0), calendar: calendar)
check(moved.map(\.startAt), [at(2026, 11, 13, 7, 30), at(2026, 11, 13, 23, 30)], "moving a day keeps start times")
check(moved.map(\.endAt), [at(2026, 11, 13, 9, 14), at(2026, 11, 14, 0, 45)], "moving a day keeps end times")
check(CaseTimeCalculator.totalMinutes(moved), 179, "moving a day keeps durations")
check(CaseTimeCalculator.moving(day, toDay: at(2026, 11, 11, 18, 0), calendar: calendar), day, "moving to the same day changes nothing")

// MARK: Labels

check(CaseTimeCalculator.durationLabel(minutes: 451), "7 h 31 m", "duration label")
check(CaseTimeCalculator.durationLabel(minutes: 451, compact: true), "7h 31m", "compact duration label")
check(CaseTimeCalculator.durationLabel(minutes: 45), "45 m", "minutes only")
check(CaseTimeCalculator.durationLabel(minutes: 240), "4 h", "whole hours")
check(CaseTimeCalculator.durationLabel(minutes: 0), "0 m", "zero")

// MARK: Monthly paydays ("paid by the 15th for the prior month")

func monthlyPayday(periodEnd: Date, endAnchor: Date = at(2026, 10, 31), payAnchor: Date = at(2026, 11, 15)) -> Date? {
    PaycheckDateMath.monthlyPaycheckDate(periodEnd: periodEnd, periodEndAnchor: endAnchor, paycheckAnchor: payAnchor, calendar: calendar)
}
check(monthlyPayday(periodEnd: at(2026, 10, 31)), at(2026, 11, 15), "anchor month pays on the anchor date")
check(monthlyPayday(periodEnd: at(2026, 11, 30)), at(2026, 12, 15), "November work is paid December 15")
check(monthlyPayday(periodEnd: at(2026, 12, 31)), at(2027, 1, 15), "December work is paid January 15 of the next year")
check(monthlyPayday(periodEnd: at(2026, 9, 30)), at(2026, 10, 15), "months before the anchor count backward")
check(monthlyPayday(periodEnd: at(2027, 2, 28)), at(2027, 3, 15), "February")
check(monthlyPayday(periodEnd: at(2026, 11, 30), endAnchor: at(2026, 10, 20), payAnchor: at(2026, 11, 15, 9, 30)), at(2026, 12, 15), "anchor day-of-month and time of day do not matter")
check(monthlyPayday(periodEnd: at(2027, 1, 31), endAnchor: at(2026, 12, 31), payAnchor: at(2027, 1, 31)), at(2027, 2, 28), "a payday on the 31st falls on the last day of a shorter month")

// MARK: Invoices

check(InvoiceMath.invoiceNumber(employerCode: "EN", date: at(2026, 4, 13), calendar: calendar), "EN-041326", "invoice number is EMPLOYER-MMDDYY")
check(InvoiceMath.invoiceNumber(employerCode: "e-n3", date: at(2026, 11, 3), calendar: calendar), "EN-110326", "the code is cleaned to two uppercase characters")
check(InvoiceMath.dateCode(at(2027, 1, 5), calendar: calendar), "010527", "date code pads month and day")
check(InvoiceMath.uniqueNumber(base: "EN-041326", existing: []), "EN-041326", "an unused number is kept")
check(InvoiceMath.uniqueNumber(base: "EN-041326", existing: ["EN-041326"]), "EN-041326-2", "a used number gets -2")
check(InvoiceMath.uniqueNumber(base: "EN-041326", existing: ["EN-041326", "EN-041326-2"]), "EN-041326-3", "then -3")
check(InvoiceMath.suggestedCode(from: "Example Surgery Center"), "ES", "suggested code uses the first two initials")
check(InvoiceMath.suggestedCode(from: "Northside"), "NO", "one word uses its first two letters")
check(InvoiceMath.suggestedCode(from: "  st. mary's  "), "SM", "punctuation and spacing are ignored")
check(InvoiceMath.suggestedCode(from: ""), "", "no name, no suggestion")
check(InvoiceMath.sanitizedCode("a1c"), "A1", "codes are at most two characters")

check(InvoiceMath.cents(money("3006.67")), 300667, "dollars to cents")
check(InvoiceMath.cents(money("0.005")), 1, "half a cent rounds up")
check(InvoiceMath.cents(money("200")), 20000, "whole dollars to cents")
check(InvoiceMath.dollars(cents: 320667), money("3206.67"), "cents to dollars")
check(InvoiceMath.cents(CaseTimeCalculator.pay(rate: 400, paidMinutes: 451)), 300667, "case pay converts to cents exactly")

check(InvoiceMath.caseLabel(3), "Anesthesia services, case 3", "generic case label")
check(InvoiceMath.addressLines(" 1 Example St \n\nSuite 2\nAnytown, ST 00000 "), ["1 Example St", "Suite 2", "Anytown, ST 00000"], "address lines are trimmed and blank lines dropped")
check(InvoiceMath.addressFields(""), ["", "", ""], "an empty address has three empty fields")
check(InvoiceMath.addressFields("1 Example St"), ["1 Example St", "", ""], "a one-line address fills the first field")
check(InvoiceMath.addressFields("1 Example St\nSuite 2\nAnytown, ST 00000\nUSA"), ["1 Example St", "Suite 2", "Anytown, ST 00000, USA"], "extra lines are kept in the last field")
let typedAddress = InvoiceMath.address(InvoiceMath.address("", settingField: 0, to: "1 Example St"), settingField: 2, to: "Anytown, ST 00000")
check(typedAddress, "1 Example St\n\nAnytown, ST 00000", "fields are stored as lines")
check(InvoiceMath.addressLines(typedAddress), ["1 Example St", "Anytown, ST 00000"], "a blank middle field prints no blank line")
check(InvoiceMath.address("1 Example St", settingField: 1, to: "Suite 2 "), "1 Example St\nSuite 2 \n", "typing is kept exactly, including a trailing space")

let invoiceDay = InvoiceDay(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    date: at(2026, 11, 11),
    siteName: "Example Surgery Center",
    caseLines: [
        InvoiceCaseLine(label: InvoiceMath.caseLabel(1), startAt: at(2026, 11, 11, 7, 30), endAt: at(2026, 11, 11, 9, 14), minutes: 104),
        InvoiceCaseLine(label: InvoiceMath.caseLabel(2), startAt: at(2026, 11, 11, 9, 40), endAt: at(2026, 11, 11, 15, 27), minutes: 347),
    ],
    charges: [
        InvoiceCharge(label: "Anesthesia time", detail: "7 h 31 m at $400.00/hr", amountCents: 300667),
        InvoiceCharge(label: "Recovery", detail: "Flat fee", amountCents: 20000),
    ]
)
check(invoiceDay.totalCents, 320667, "a day's total is the sum of its charges")
let snapshot = InvoiceSnapshot(
    senderName: "Sample Physician, MD", senderAddress: "1 Example St\nAnytown, ST 00000", senderPhone: "555-0100", senderEmail: "",
    billToName: "Example Group PLLC", billToAddress: "PO Box 1\nAnytown, ST 00000",
    days: [invoiceDay, invoiceDay]
)
check(snapshot.totalCents, 641334, "an invoice's total is the sum of its days")
check(snapshot.siteNames, ["Example Surgery Center"], "a site worked on several days is listed once")
var otherSiteDay = invoiceDay
otherSiteDay.siteName = "Example Eye Center"
var twoSites = snapshot
twoSites.days = [invoiceDay, otherSiteDay, invoiceDay]
check(twoSites.siteNames, ["Example Surgery Center", "Example Eye Center"], "one invoice can cover several sites")
check(InvoiceMath.fingerprint(of: otherSiteDay) == InvoiceMath.fingerprint(of: invoiceDay), false, "moving a shift to another site changes the fingerprint")
let decoded = try! JSONDecoder().decode(InvoiceSnapshot.self, from: try! JSONEncoder().encode(snapshot))
check(decoded.totalCents, 641334, "a saved invoice reads back with the same total")
check(decoded.days.map { InvoiceMath.fingerprint(of: $0) }, snapshot.days.map { InvoiceMath.fingerprint(of: $0) }, "a saved invoice reads back unchanged")
var editedDay = invoiceDay
editedDay.caseLines[0].endAt = at(2026, 11, 11, 9, 15)
check(InvoiceMath.fingerprint(of: editedDay) == InvoiceMath.fingerprint(of: invoiceDay), false, "changing a case time changes the fingerprint")
var repricedDay = invoiceDay
repricedDay.charges[0].amountCents = 300000
check(InvoiceMath.fingerprint(of: repricedDay) == InvoiceMath.fingerprint(of: invoiceDay), false, "changing an amount changes the fingerprint")

// MARK: Invoice schedules and reminders

func span(_ y1: Int, _ m1: Int, _ d1: Int, _ y2: Int, _ m2: Int, _ d2: Int) -> InvoicePeriod {
    InvoicePeriod(start: at(y1, m1, d1), end: at(y2, m2, d2))
}
func period(_ date: Date, _ cadence: InvoiceCadence, anchor: Date? = nil) -> InvoicePeriod? {
    InvoiceScheduleMath.period(containing: date, cadence: cadence, anchorEnd: anchor, calendar: calendar)
}

let twoWeekAnchor = at(2026, 11, 22)
check(period(at(2026, 11, 19, 14, 5), .everyTwoWeeks, anchor: twoWeekAnchor), span(2026, 11, 9, 2026, 11, 22), "every 2 weeks: a day inside the anchor's period")
check(period(at(2026, 11, 22), .everyTwoWeeks, anchor: twoWeekAnchor), span(2026, 11, 9, 2026, 11, 22), "every 2 weeks: the anchor day ends its period")
check(period(at(2026, 11, 23), .everyTwoWeeks, anchor: twoWeekAnchor), span(2026, 11, 23, 2026, 12, 6), "every 2 weeks: the day after starts the next period")
check(period(at(2026, 11, 8), .everyTwoWeeks, anchor: twoWeekAnchor), span(2026, 10, 26, 2026, 11, 8), "every 2 weeks: earlier periods count back from the anchor")
check(period(at(2026, 11, 19), .everyTwoWeeks, anchor: at(2026, 12, 20)), span(2026, 11, 9, 2026, 11, 22), "every 2 weeks: an anchor in the future works too")
check(period(at(2026, 11, 19), .weekly, anchor: at(2026, 11, 21)), span(2026, 11, 15, 2026, 11, 21), "weekly: Sunday to Saturday from a Saturday anchor")
check(period(at(2026, 11, 19), .everyTwoWeeks), nil, "every 2 weeks needs its anchor")
check(period(at(2026, 11, 19), .payPeriod), nil, "pay periods come from the pay-period engine, not here")
check(period(at(2026, 11, 15), .twiceMonthly), span(2026, 11, 1, 2026, 11, 15), "twice a month: the 15th ends the first half")
check(period(at(2026, 11, 16), .twiceMonthly), span(2026, 11, 16, 2026, 11, 30), "twice a month: the 16th starts the second half")
check(period(at(2027, 2, 20), .twiceMonthly), span(2027, 2, 16, 2027, 2, 28), "twice a month: February's second half ends on the 28th")
check(period(at(2028, 2, 20), .twiceMonthly), span(2028, 2, 16, 2028, 2, 29), "twice a month: leap-year February ends on the 29th")
check(period(at(2026, 11, 19), .monthly), span(2026, 11, 1, 2026, 11, 30), "monthly: the calendar month")
check(period(at(2026, 12, 31, 23, 59), .monthly), span(2026, 12, 1, 2026, 12, 31), "monthly: late on the last day is still that month")

let novPeriod = span(2026, 11, 9, 2026, 11, 22)
check(InvoiceScheduleMath.hasEnded(novPeriod, now: at(2026, 11, 22, 18, 0), calendar: calendar), false, "a period hasn't ended during its last day")
check(InvoiceScheduleMath.hasEnded(novPeriod, now: at(2026, 11, 23, 0, 1), calendar: calendar), true, "a period has ended the next day")
check(InvoiceScheduleMath.firstInvoiceReminderDay(after: novPeriod, calendar: calendar), at(2026, 11, 23), "invoice reminders start the day after the period ends")
check(InvoiceScheduleMath.firstUnpaidReminderDay(issuedOn: at(2026, 11, 23, 16, 0), dueOn: at(2026, 12, 15), calendar: calendar), at(2026, 12, 15), "unpaid reminders start on the due date")
check(InvoiceScheduleMath.firstUnpaidReminderDay(issuedOn: at(2026, 11, 23, 16, 0), dueOn: nil, calendar: calendar), at(2026, 11, 30), "without a due date, unpaid reminders start a week after the invoice date")

func reminders(from day: Date, after now: Date, limit: Int = 3) -> [Date] {
    InvoiceScheduleMath.weeklyReminders(startingOn: day, hour: 9, after: now, limit: limit, calendar: calendar)
}
check(reminders(from: at(2026, 11, 23), after: at(2026, 11, 19, 12, 0)), [at(2026, 11, 23, 9), at(2026, 11, 30, 9), at(2026, 12, 7, 9)], "reminders at 9 AM, then weekly")
check(reminders(from: at(2026, 11, 23), after: at(2026, 11, 23, 8, 59)), [at(2026, 11, 23, 9), at(2026, 11, 30, 9), at(2026, 12, 7, 9)], "a reminder later the same morning is kept")
check(reminders(from: at(2026, 11, 23), after: at(2026, 11, 23, 10, 0)), [at(2026, 11, 30, 9), at(2026, 12, 7, 9), at(2026, 12, 14, 9)], "a reminder already past is skipped")
check(reminders(from: at(2026, 1, 1), after: at(2026, 11, 19, 12, 0), limit: 1), [at(2026, 11, 26, 9)], "long-overdue reminders stay on the same weekday")
check(reminders(from: at(2026, 11, 23), after: at(2026, 11, 19), limit: 0), [], "no reminders when none are wanted")

check(InvoiceScheduleMath.isOverdue(dueOn: at(2026, 12, 15), paidOn: nil, now: at(2026, 12, 16, 8, 0), calendar: calendar), true, "unpaid after the due date is overdue")
check(InvoiceScheduleMath.isOverdue(dueOn: at(2026, 12, 15), paidOn: nil, now: at(2026, 12, 15, 20, 0), calendar: calendar), false, "the due date itself isn't overdue")
check(InvoiceScheduleMath.isOverdue(dueOn: at(2026, 12, 15), paidOn: at(2026, 12, 20), now: at(2027, 1, 5), calendar: calendar), false, "a paid invoice is never overdue")
check(InvoiceScheduleMath.isOverdue(dueOn: nil, paidOn: nil, now: at(2027, 1, 5), calendar: calendar), false, "without a due date nothing is overdue")
check(InvoiceCadence.allCases.map(\.rawValue), ["weekly", "everyTwoWeeks", "twiceMonthly", "monthly", "payPeriod"], "saved schedule names never change")

if failures > 0 {
    print("\n\(failures) pay-math test(s) failed.")
    exit(1)
}
print("\nAll pay-math tests passed.")
