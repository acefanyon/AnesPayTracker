// Runs the app's real pay math, outside the app. macOS/Linux with a Swift toolchain:
//
//   swiftc -o /tmp/pay_math_tests \
//     AnesPayTracker/Engine/CaseTimeCalculator.swift \
//     AnesPayTracker/Engine/PaycheckDateMath.swift \
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

if failures > 0 {
    print("\n\(failures) pay-math test(s) failed.")
    exit(1)
}
print("\nAll pay-math tests passed.")
