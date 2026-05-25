import Foundation
import SwiftData

// MARK: - Seed Data

struct SeedData {

    static func insertIfNeeded(into context: ModelContext) {
        // Check if already seeded
        let descriptor = FetchDescriptor<Employer>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        // --- Employer 1: Valley Anesthesia Partners ---
        let vap = Employer(
            name: "Valley Anesthesia Partners",
            contactPersons: [],
            payCadence: .biweekly
        )

        let tanya = ContactPerson(name: "Tanya Reeves", role: "Scheduling Coordinator")
        let marcos = ContactPerson(name: "Marcos Ibáñez", role: "Medical Director")
        vap.contactPersons = [tanya, marcos]

        // Site 1: Riverside Surgical Center (per-day)
        let riverside = Site(
            name: "Riverside Surgical",
            payUnit: .perDay,
            baseAmount: 1800
        )
        riverside.employer = vap

        // Site 2: Summit General Hospital (per-hour)
        let summit = Site(
            name: "Summit General",
            payUnit: .perHour,
            baseAmount: 225
        )
        summit.employer = vap

        vap.sites = [riverside, summit]

        let highNeedBonus = CustomBonusType(
            employer: vap,
            name: "High Need Bonus",
            payUnit: .perDay,
            defaultAmount: 350
        )
        let hardToFillBonus = CustomBonusType(
            employer: vap,
            name: "Hard-to-Fill Bonus",
            payUnit: .perDay,
            defaultAmount: 200
        )
        vap.customBonusTypes = [highNeedBonus, hardToFillBonus]

        // Streak rule: 4 days in 14 rolling days → $500
        let streakRule = StreakRule(
            requiredDays: 4,
            windowType: .rollingDays,
            windowDays: 14,
            bonusAmount: 500,
            isActive: true
        )
        streakRule.employer = vap
        vap.streakRules = [streakRule]

        // --- Seed Shifts ---
        let calendar = Calendar.current
        let today = Date()

        // Helper: date offset from today
        func dateOffset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)) ?? today
        }

        // Shift 1: Riverside, full day, 20 days ago
        let shift1 = Shift(
            site: riverside,
            date: dateOffset(-20),
            payUnit: .perDay,
            dayFraction: .full,
            baseAmount: 1800,
            customBonuses: [AppliedCustomBonus(name: "High Need Bonus", payUnit: .perDay, amount: 350, quantity: 1)],
            notes: "GI suite. Smooth day.",
            sourceNote: SourceNote(
                contactName: "Tanya",
                contactedOn: dateOffset(-21),
                channel: .text
            )
        )

        // Shift 2: Summit, 8 hours, 18 days ago
        let shift2 = Shift(
            site: summit,
            date: dateOffset(-18),
            payUnit: .perHour,
            hoursWorked: 8.0,
            baseAmount: 225,
            notes: "Cardiac anesthesia. Long but routine."
        )

        // Shift 3: Riverside, half day (sent home early), 15 days ago
        let shift3 = Shift(
            site: riverside,
            date: dateOffset(-15),
            payUnit: .perDay,
            dayFraction: .half,
            baseAmount: 1800,
            customBonuses: [
                AppliedCustomBonus(name: "High Need Bonus", payUnit: .perDay, amount: 350, quantity: 1),
                AppliedCustomBonus(name: "Hard-to-Fill Bonus", payUnit: .perDay, amount: 200, quantity: 1)
            ],
            notes: "Cases cancelled after lunch.",
            sourceNote: SourceNote(
                contactName: "Tanya",
                contactedOn: dateOffset(-16),
                channel: .text
            )
        )

        // Shift 4: Summit, 10 hours, 10 days ago
        let shift4 = Shift(
            site: summit,
            date: dateOffset(-10),
            payUnit: .perHour,
            hoursWorked: 10.0,
            baseAmount: 225
        )

        // Shift 5: Riverside, full day, 8 days ago — streak trigger
        let shift5 = Shift(
            site: riverside,
            date: dateOffset(-8),
            payUnit: .perDay,
            dayFraction: .full,
            baseAmount: 1800,
            streakBonusAmount: 500,
            streakRuleTriggeredID: streakRule.id,
            customBonuses: [
                AppliedCustomBonus(name: "High Need Bonus", payUnit: .perDay, amount: 350, quantity: 1),
                AppliedCustomBonus(name: "Hard-to-Fill Bonus", payUnit: .perDay, amount: 200, quantity: 1)
            ],
            notes: "Hard-to-fill Friday. Bonus splash applied.",
            sourceNote: SourceNote(
                contactName: "Marcos",
                contactedOn: dateOffset(-9),
                channel: .email
            )
        )

        // Shift 6: Riverside, three-quarter day, 3 days ago
        let shift6 = Shift(
            site: riverside,
            date: dateOffset(-3),
            payUnit: .perDay,
            dayFraction: .threeQuarter,
            baseAmount: 1800
        )

        // Shift 7: Summit, 6 hours, yesterday
        let shift7 = Shift(
            site: summit,
            date: dateOffset(-1),
            payUnit: .perHour,
            hoursWorked: 6.0,
            baseAmount: 225
        )

        riverside.shifts = [shift1, shift3, shift5, shift6]
        summit.shifts = [shift2, shift4, shift7]

        // Insert
        context.insert(vap)
        context.insert(riverside)
        context.insert(summit)
        context.insert(highNeedBonus)
        context.insert(hardToFillBonus)
        context.insert(streakRule)
        context.insert(tanya)
        context.insert(marcos)
        context.insert(shift1)
        context.insert(shift2)
        context.insert(shift3)
        context.insert(shift4)
        context.insert(shift5)
        context.insert(shift6)
        context.insert(shift7)

        try? context.save()
    }
}
