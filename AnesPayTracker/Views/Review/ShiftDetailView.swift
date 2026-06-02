import SwiftUI
import SwiftData

// MARK: - Shift Detail View

struct ShiftDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let shift: Shift

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showEditHistory = false
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header: total pay + site
                    ShiftDetailHeader(shift: shift)

                    VStack(spacing: 20) {
                        // Pay breakdown
                        PayBreakdownCard(shift: shift)

                        // Meta info
                        ShiftMetaCard(shift: shift)

                        // Notes
                        if let notes = shift.notes, !notes.isEmpty {
                            InfoCard(title: "Notes") {
                                Text(notes)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Source note
                        if let sn = shift.sourceNote {
                            SourceNoteCard(sourceNote: sn)
                        }

                        // Edit history
                        if shift.isEdited {
                            EditHistoryCard(
                                editHistory: shift.editHistory,
                                lastEditedAt: shift.lastEditedAt,
                                isExpanded: $showEditHistory
                            )
                        }

                        // Delete button
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Shift", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Shift Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        copyShift()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button("Edit") { showEdit = true }
                    Button("Done") { dismiss() }
                }
            }
            .alert("Shift copied", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open another day and use Paste Copied Shift to reuse the editable fields on the new date.")
            }
            .sheet(isPresented: $showEdit) {
                AddShiftView(editingShift: shift)
            }
            .confirmationDialog("Delete this shift?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteShift()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func deleteShift() {
        let calSync = CalendarSyncManager.shared
        calSync.removeEvent(for: shift)

        if let employer = shift.site?.employer {
            modelContext.delete(shift)
            try? modelContext.save()
            StreakEngine.recomputeStreaks(for: employer)
            try? modelContext.save()
        } else {
            modelContext.delete(shift)
            try? modelContext.save()
        }
        dismiss()
    }

    private func copyShift() {
        ShiftDraftClipboard.shared.copy(from: shift)
        showCopiedAlert = true
    }
}

// MARK: - Header

struct ShiftDetailHeader: View {
    let shift: Shift

    var body: some View {
        VStack(spacing: 8) {
            Text(shift.totalPay.formatted(.currency(code: "USD")))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accent)

            HStack(spacing: 8) {
                Text(shift.site?.name ?? "Unknown Site")
                    .font(.title3.bold())
                Text("·")
                    .foregroundStyle(.secondary)
                Text(shift.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if shift.isEdited {
                Label("Edited", systemImage: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if shift.isOnCall {
                Label("On-Call", systemImage: "phone.badge.clock")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue, in: Capsule())
            }

            if shift.hasStreakBonus {
                Label("This shift is earning a deferred streak bonus", systemImage: "target")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.accent.opacity(0.06))
    }
}

// MARK: - Pay Breakdown Card

struct PayBreakdownCard: View {
    let shift: Shift

    private var streakPayoutDetail: String {
        let schedule = shift.streakPayoutSchedule ?? .nextQuarterlyPayout
        let payoutDate = schedule.payoutDate(for: shift.date)
        return "Earned on this shift, paid \(payoutDate.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var body: some View {
        InfoCard(title: "Pay Breakdown") {
            VStack(spacing: 0) {
                switch shift.payUnit {
                case .perDay:
                    BreakdownRow(
                        label: "\(shift.baseAmount.formatted(.currency(code: "USD"))) × \(shift.dayFraction?.label ?? "Full")",
                        value: shift.basePay,
                        isBase: true
                    )
                case .perHour:
                    let hrs = shift.hoursWorked ?? 0
                    BreakdownRow(
                        label: "\(shift.baseAmount.formatted(.currency(code: "USD")))/hr × \(hrs.formatted()) hrs",
                        value: shift.basePay,
                        isBase: true
                    )
                }

                if let splash = shift.splashAmount, splash > 0 {
                    Divider()
                    BreakdownRow(label: "Splash Bonus", value: splash)
                }

                if let bonus = shift.bonusSplashAmount, bonus > 0 {
                    Divider()
                    BreakdownRow(label: "Bonus Splash", value: bonus)
                }

                if shift.hasOnCallBonus {
                    Divider()
                    BreakdownRow(
                        label: "On-Call Bonus",
                        detail: "Paid with this shift on the service date",
                        value: shift.onCallPay,
                        highlight: true
                    )
                }

                ForEach(shift.customBonuses ?? []) { bonus in
                    if bonus.totalAmount > 0 {
                        Divider()
                        BreakdownRow(label: bonus.name, value: bonus.totalAmount)
                    }
                }

                if let streak = shift.streakBonusAmount, streak > 0 {
                    Divider()
                    BreakdownRow(
                        label: "🎯 Streak Bonus",
                        detail: streakPayoutDetail,
                        value: streak,
                        highlight: true
                    )
                }

                Divider()
                BreakdownRow(label: "Total", value: shift.totalPay, isTotal: true)
            }
        }
    }
}

struct BreakdownRow: View {
    let label: String
    var detail: String? = nil
    let value: Decimal
    var isBase: Bool = false
    var isTotal: Bool = false
    var highlight: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(isTotal ? .body.bold() : .body)
                    .foregroundStyle(highlight ? .orange : (isBase ? .secondary : .primary))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value.formatted(.currency(code: "USD")))
                .font(isTotal ? .title3.bold() : .body)
                .foregroundStyle(isTotal ? Color.accent : (highlight ? .orange : .primary))
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Meta Card

struct ShiftMetaCard: View {
    let shift: Shift

    private var streakStatusText: String {
        if shift.streakQualifiedForPayout, let amount = shift.streakPerDayBonusAmount {
            let payoutDate = (shift.streakPayoutSchedule ?? .nextQuarterlyPayout).payoutDate(for: shift.date)
            return "Earned +\(amount.formatted(.currency(code: "USD"))) on this shift, pays \(payoutDate.formatted(.dateTime.month(.abbreviated).day().year()))"
        }

        if let qualifiedCount = shift.streakQualifiedShiftCount {
            if qualifiedCount == 0 {
                return "No streak progress snapshot"
            }
            return "Counted as streak day \(qualifiedCount) for this quarter"
        }

        return "No streak progress snapshot"
    }

    var body: some View {
        InfoCard(title: "Details") {
            VStack(spacing: 0) {
                MetaRow(label: "Employer", value: shift.site?.employer?.name ?? "—")
                Divider()
                MetaRow(label: "Site", value: shift.site?.name ?? "—")
                Divider()
                MetaRow(label: "Date", value: shift.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                Divider()
                switch shift.payUnit {
                case .perDay:
                    MetaRow(label: "Day Fraction", value: shift.dayFraction?.accessibilityLabel ?? "Full Day")
                case .perHour:
                    MetaRow(label: "Hours", value: "\(shift.hoursWorked?.formatted() ?? "0") hrs")
                }
                Divider()
                MetaRow(label: "On-Call", value: shift.isOnCall ? shift.onCallPay.formatted(.currency(code: "USD")) : "No")
                Divider()
                MetaRow(label: "Streak Status", value: streakStatusText)
            }
        }
    }
}

struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Source Note Card

struct SourceNoteCard: View {
    let sourceNote: SourceNote

    var body: some View {
        InfoCard(title: "Source Note") {
            VStack(spacing: 0) {
                MetaRow(label: "Contact", value: sourceNote.contactName)
                Divider()
                MetaRow(label: "Date Contacted", value: sourceNote.contactedOn.formatted(.dateTime.month(.abbreviated).day().year()))
                Divider()
                MetaRow(label: "Channel", value: sourceNote.channel.rawValue)
            }
        }
    }
}

// MARK: - Edit History Card

struct EditHistoryCard: View {
    let editHistory: [EditRecord]
    let lastEditedAt: Date?
    @Binding var isExpanded: Bool

    var body: some View {
        InfoCard(title: "Edit History") {
            VStack(spacing: 0) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack {
                        if let date = lastEditedAt {
                            Text("Last edited \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                    ForEach(editHistory.reversed()) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.editedAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(record.summary)
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
