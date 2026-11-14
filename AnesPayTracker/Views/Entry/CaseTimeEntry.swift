import SwiftUI

// MARK: - Cases Entry

/// Add/Edit Shift section for sites that pay for case time only: a list of
/// cases, each with a start and stop time. Times can be typed in, corrected,
/// or captured with Start Now / Stop Now.
struct CasesEntry: View {
    @Binding var cases: [ShiftCase]
    let serviceDate: Date
    let minimumHours: Double?

    private let calendar = Calendar.current

    private var ordered: [ShiftCase] { CaseTimeCalculator.sorted(cases) }
    private var caseMinutes: Int { CaseTimeCalculator.totalMinutes(cases) }
    private var paidMinutes: Int {
        CaseTimeCalculator.paidMinutes(caseMinutes: caseMinutes, minimumHours: minimumHours)
    }
    private var hasRunningCase: Bool { cases.contains(where: \.isRunning) }
    private var isToday: Bool { calendar.isDateInToday(serviceDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cases")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.5)
                Spacer()
                Text(CaseTimeCalculator.durationLabel(minutes: caseMinutes))
                    .font(.title3.bold())
                    .foregroundStyle(Color.accent)
                    .accessibilityLabel("Total case time \(CaseTimeCalculator.durationLabel(minutes: caseMinutes))")
            }

            if cases.isEmpty {
                Text("This site pays for case time only. Add each case's start and stop time; time between cases isn't counted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Rows stay in the order they were added so a row doesn't jump
            // while its time is being edited; numbers follow the clock.
            ForEach(cases) { shiftCase in
                CaseRow(
                    number: number(of: shiftCase),
                    shiftCase: $cases.element(shiftCase),
                    canStopNow: isToday,
                    onDelete: { cases.removeAll { $0.id == shiftCase.id } }
                )
            }

            HStack(spacing: 12) {
                Button {
                    addCase()
                } label: {
                    Label("Add Case", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                if isToday && !hasRunningCase {
                    Button {
                        startCaseNow()
                    } label: {
                        Label("Start Now", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if paidMinutes > caseMinutes {
                Text("Daily minimum applies: paid for \(CaseTimeCalculator.durationLabel(minutes: paidMinutes)) instead of \(CaseTimeCalculator.durationLabel(minutes: caseMinutes)) worked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let problem = CaseTimeCalculator.blockingProblem(in: cases) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let warning = CaseTimeCalculator.warning(in: cases) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func number(of shiftCase: ShiftCase) -> Int {
        (ordered.firstIndex { $0.id == shiftCase.id } ?? 0) + 1
    }

    private func addCase() {
        let start: Date
        if let last = ordered.last, !last.isRunning {
            start = last.endAt
        } else if isToday && !hasRunningCase {
            start = CaseTimeCalculator.truncatedToMinute(Date())
        } else {
            start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: serviceDate) ?? serviceDate
        }
        // Zero-length until the stop time is entered, so a forgotten row adds no pay.
        cases.append(ShiftCase(startAt: start, endAt: start))
    }

    private func startCaseNow() {
        let now = CaseTimeCalculator.truncatedToMinute(Date())
        cases.append(ShiftCase(startAt: now, endAt: now, isRunning: true))
    }
}

// MARK: - Case Row

struct CaseRow: View {
    let number: Int
    @Binding var shiftCase: ShiftCase
    let canStopNow: Bool
    let onDelete: () -> Void

    private let calendar = Calendar.current

    private var startBinding: Binding<Date> {
        Binding(
            get: { shiftCase.startAt },
            set: { picked in
                let newStart = CaseTimeCalculator.time(of: picked, onDayOf: shiftCase.startAt, calendar: calendar)
                shiftCase.startAt = newStart
                if shiftCase.isRunning || shiftCase.endAt < newStart {
                    shiftCase.endAt = newStart
                }
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { shiftCase.endAt },
            set: { picked in
                shiftCase.endAt = CaseTimeCalculator.end(atTimeOf: picked, forStart: shiftCase.startAt, calendar: calendar)
            }
        )
    }

    private var endsNextDay: Bool {
        !shiftCase.isRunning && !calendar.isDate(shiftCase.startAt, inSameDayAs: shiftCase.endAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Case \(number)")
                    .font(.body.bold())
                Spacer()
                if shiftCase.isRunning {
                    Label("Running", systemImage: "record.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                } else {
                    Text(CaseTimeCalculator.durationLabel(minutes: CaseTimeCalculator.minutes(of: shiftCase)))
                        .font(.subheadline.bold())
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Delete case \(number)")
            }

            if shiftCase.isRunning {
                HStack(spacing: 8) {
                    Text("Started")
                        .foregroundStyle(.secondary)
                    DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    if canStopNow {
                        Button {
                            stopNow()
                        } label: {
                            Label("Stop Now", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Enter Stop Time") {
                        shiftCase.endAt = shiftCase.startAt
                        shiftCase.isRunning = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 8) {
                    DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    DatePicker("Stop", selection: endBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    if endsNextDay {
                        Text("next day")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func stopNow() {
        let now = CaseTimeCalculator.truncatedToMinute(Date())
        shiftCase.endAt = max(now, shiftCase.startAt)
        shiftCase.isRunning = false
    }
}
