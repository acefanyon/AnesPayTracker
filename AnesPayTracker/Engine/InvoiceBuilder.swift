import Foundation

// MARK: - Invoice Builder

/// Turns saved shifts into invoice content. The numbering and money helpers
/// it uses live in `InvoiceMath`.
enum InvoiceBuilder {

    /// What one shift bills: base pay, on-call and bonuses. Streak bonuses are
    /// left out because they are paid on their own schedule, not with the
    /// day's work. Cases appear with generic labels and times only.
    static func day(for shift: Shift) -> InvoiceDay {
        var caseLines: [InvoiceCaseLine] = []
        if shift.isCaseTracked {
            for (index, shiftCase) in shift.sortedCases.enumerated() where !shiftCase.isRunning {
                caseLines.append(InvoiceCaseLine(
                    label: InvoiceMath.caseLabel(index + 1),
                    startAt: shiftCase.startAt,
                    endAt: shiftCase.endAt,
                    minutes: CaseTimeCalculator.minutes(of: shiftCase)
                ))
            }
        }

        var charges: [InvoiceCharge] = []
        func add(_ label: String, _ detail: String, _ amount: Decimal) {
            let cents = InvoiceMath.cents(amount)
            guard cents != 0 else { return }
            charges.append(InvoiceCharge(label: label, detail: detail, amountCents: cents))
        }

        let rate = money(shift.baseAmount)
        switch shift.payUnit {
        case .perDay:
            let fraction = shift.dayFraction ?? .full
            let fractionLabel = fraction == .full ? "Full day" : "\(fraction.label) day"
            add("Anesthesia services", "\(fractionLabel) at \(rate)/day", shift.basePay)
        case .perHour:
            if shift.isCaseTracked {
                var detail = "\(CaseTimeCalculator.durationLabel(minutes: shift.paidCaseMinutes)) at \(rate)/hr"
                if shift.minimumAdjustmentMinutes > 0 {
                    let worked = CaseTimeCalculator.durationLabel(minutes: shift.caseMinutes)
                    detail += " (daily minimum; \(worked) worked)"
                }
                add("Anesthesia time", detail, shift.basePay)
            } else {
                add("Anesthesia services", "\((shift.hoursWorked ?? 0).formatted()) hrs at \(rate)/hr", shift.basePay)
            }
        }

        add("On-call", "", shift.onCallPay)
        add("Bonus", "", (shift.splashAmount ?? 0) + (shift.bonusSplashAmount ?? 0))

        for bonus in shift.customBonuses ?? [] {
            let detail: String
            switch bonus.payUnit {
            case .perHour:
                let followsCaseTime = shift.isCaseTracked && bonus.quantity == (shift.hoursWorked ?? 0)
                let time = followsCaseTime
                    ? CaseTimeCalculator.durationLabel(minutes: shift.caseMinutes)
                    : "\(bonus.quantity.formatted()) hrs"
                detail = "\(time) at \(money(bonus.amount))/hr"
            case .perDay:
                detail = bonus.quantity == 1 ? "Flat fee" : "\(money(bonus.amount)) × \(bonus.quantity.formatted())"
            }
            add(bonus.name, detail, bonus.totalAmount)
        }

        return InvoiceDay(id: shift.id, date: shift.date, caseLines: caseLines, charges: charges)
    }

    /// The site's shifts dated from `start` through `end`, oldest first.
    static func candidateShifts(at site: Site, from start: Date, through end: Date, calendar: Calendar = .current) -> [Shift] {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.endOfDay(for: end)
        return site.shifts
            .filter { $0.date >= lower && $0.date <= upper }
            .sorted { $0.date < $1.date }
    }

    /// Shift ID → the number of the invoice that already bills it.
    static func invoiceNumbersByShift(_ invoices: [Invoice]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for invoice in invoices {
            for shiftID in invoice.shiftIDs {
                result[shiftID] = invoice.number
            }
        }
        return result
    }

    static func makeInvoice(
        number: String,
        employer: Employer,
        site: Site,
        periodStart: Date,
        periodEnd: Date,
        issuedOn: Date,
        dueOn: Date?,
        notes: String?,
        snapshot: InvoiceSnapshot
    ) throws -> Invoice {
        Invoice(
            number: number,
            employerID: employer.id,
            siteID: site.id,
            billToName: snapshot.billToName,
            siteName: snapshot.siteName,
            periodStart: periodStart,
            periodEnd: periodEnd,
            issuedOn: issuedOn,
            dueOn: dueOn,
            totalCents: snapshot.totalCents,
            notes: notes,
            snapshotData: try JSONEncoder().encode(snapshot)
        )
    }

    /// Days whose shift was edited or deleted after the invoice was created.
    static func changedDays(in snapshot: InvoiceSnapshot, shifts: [Shift]) -> [InvoiceDay] {
        var shiftsByID: [UUID: Shift] = [:]
        for shift in shifts { shiftsByID[shift.id] = shift }
        return snapshot.days.filter { day in
            guard let shift = shiftsByID[day.id] else { return true }
            return InvoiceMath.fingerprint(of: InvoiceBuilder.day(for: shift)) != InvoiceMath.fingerprint(of: day)
        }
    }

    private static func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }
}
