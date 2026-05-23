import SwiftUI
import SwiftData

// MARK: - Report View

struct ReportView: View {
    @Query private var employers: [Employer]
    @Query(sort: \Shift.date) private var allShifts: [Shift]
    @Query(sort: \Site.name) private var allSites: [Site]
    
    @State private var dateRange: ReportDateRange = .thisMonth
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var selectedEmployer: Employer?
    @State private var selectedSite: Site?
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var expandedNote: Shift?
    
    var filteredShifts: [Shift] {
        let (start, end) = currentDateBounds
        return allShifts.filter { shift in
            guard shift.date >= start && shift.date <= end else { return false }
            if let emp = selectedEmployer, shift.site?.employer?.id != emp.id { return false }
            if let site = selectedSite, shift.site?.id != site.id { return false }
            return true
        }
    }
    
    var totalBase: Decimal { filteredShifts.reduce(0) { $0 + $1.basePay } }
    var totalSplash: Decimal { filteredShifts.reduce(0) { $0 + ($1.splashAmount ?? 0) } }
    var totalBonusSplash: Decimal { filteredShifts.reduce(0) { $0 + ($1.bonusSplashAmount ?? 0) } }
    var totalStreak: Decimal { filteredShifts.reduce(0) { $0 + ($1.streakBonusAmount ?? 0) } }
    var grandTotal: Decimal { filteredShifts.reduce(0) { $0 + $1.totalPay } }
    
    var currentDateBounds: (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        switch dateRange {
        case .thisMonth:
            var comps = cal.dateComponents([.year, .month], from: today)
            let start = cal.date(from: comps) ?? today
            comps.month! += 1
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(from: comps) ?? today) ?? today
            return (start, end)
        case .lastMonth:
            var comps = cal.dateComponents([.year, .month], from: today)
            comps.month! -= 1
            let start = cal.date(from: comps) ?? today
            var endComps = comps; endComps.month! += 1
            let end = cal.date(byAdding: .day, value: -1, to: cal.date(from: endComps) ?? today) ?? today
            return (start, end)
        case .ytd:
            var comps = cal.dateComponents([.year], from: today)
            let start = cal.date(from: comps) ?? today
            return (start, today)
        case .custom:
            return (cal.startOfDay(for: customStart), cal.endOfDay(for: customEnd))
        case .thisPayPeriod:
            if let emp = selectedEmployer ?? employers.first {
                return StreakEngine.payPeriodBounds(containing: today, employer: emp)
            }
            return (today, today)
        case .lastPayPeriod:
            if let emp = selectedEmployer ?? employers.first {
                let (currentStart, _) = StreakEngine.payPeriodBounds(containing: today, employer: emp)
                let dayBefore = cal.date(byAdding: .day, value: -1, to: currentStart) ?? today
                return StreakEngine.payPeriodBounds(containing: dayBefore, employer: emp)
            }
            return (today, today)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Filters
                    ReportFiltersCard(
                        dateRange: $dateRange,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        selectedEmployer: $selectedEmployer,
                        selectedSite: $selectedSite,
                        employers: employers,
                        sites: allSites
                    )
                    
                    // Summary
                    if !filteredShifts.isEmpty {
                        ReportSummaryCard(
                            shiftCount: filteredShifts.count,
                            totalBase: totalBase,
                            totalSplash: totalSplash,
                            totalBonusSplash: totalBonusSplash,
                            totalStreak: totalStreak,
                            grandTotal: grandTotal
                        )
                        
                        // Table
                        ReportTableCard(
                            shifts: filteredShifts,
                            expandedNote: $expandedNote
                        )
                        
                        // Export button
                        Button {
                            generateAndSharePDF()
                        } label: {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        EmptyStateView(
                            icon: "doc.text",
                            title: "No shifts in range",
                            message: "Try a different date range or filter."
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Report")
            .sheet(isPresented: $showShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    // MARK: - PDF Generation
    
    private func generateAndSharePDF() {
        let (start, end) = currentDateBounds
        let generator = PDFReportGenerator()
        if let url = generator.generate(
            shifts: filteredShifts,
            startDate: start,
            endDate: end,
            employerFilter: selectedEmployer?.name,
            siteFilter: selectedSite?.name
        ) {
            pdfURL = url
            showShareSheet = true
        }
    }
}

// MARK: - Date Range Enum

enum ReportDateRange: String, CaseIterable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case ytd = "Year to Date"
    case thisPayPeriod = "This Pay Period"
    case lastPayPeriod = "Last Pay Period"
    case custom = "Custom"
}

// MARK: - Filters Card

struct ReportFiltersCard: View {
    @Binding var dateRange: ReportDateRange
    @Binding var customStart: Date
    @Binding var customEnd: Date
    @Binding var selectedEmployer: Employer?
    @Binding var selectedSite: Site?
    let employers: [Employer]
    let sites: [Site]
    
    var filteredSites: [Site] {
        if let emp = selectedEmployer {
            return sites.filter { $0.employer?.id == emp.id }
        }
        return sites
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            // Date range
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportDateRange.allCases, id: \.self) { range in
                        FilterChip(label: range.rawValue, isSelected: dateRange == range) {
                            dateRange = range
                        }
                    }
                }
            }
            
            if dateRange == .custom {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customStart, displayedComponents: .date)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To").font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $customEnd, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            
            if employers.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Employer").font(.caption).foregroundStyle(.secondary)
                    Picker("Employer", selection: $selectedEmployer) {
                        Text("All").tag(Optional<Employer>.none)
                        ForEach(employers) { emp in
                            Text(emp.name).tag(Optional(emp))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            if filteredSites.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Site").font(.caption).foregroundStyle(.secondary)
                    Picker("Site", selection: $selectedSite) {
                        Text("All").tag(Optional<Site>.none)
                        ForEach(filteredSites) { site in
                            Text(site.name).tag(Optional(site))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Summary Card

struct ReportSummaryCard: View {
    let shiftCount: Int
    let totalBase: Decimal
    let totalSplash: Decimal
    let totalBonusSplash: Decimal
    let totalStreak: Decimal
    let grandTotal: Decimal
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(shiftCount) shift\(shiftCount == 1 ? "" : "s")")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(grandTotal.formatted(.currency(code: "USD")))
                    .font(.title2.bold())
                    .foregroundStyle(Color.accent)
            }
            
            Divider()
            
            HStack(spacing: 0) {
                SummaryCol(label: "Base", amount: totalBase)
                if totalSplash > 0 {
                    SummaryCol(label: "Splash", amount: totalSplash)
                }
                if totalBonusSplash > 0 {
                    SummaryCol(label: "Bonus\nSplash", amount: totalBonusSplash)
                }
                if totalStreak > 0 {
                    SummaryCol(label: "🎯 Streak", amount: totalStreak)
                }
            }
        }
        .padding(16)
        .background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SummaryCol: View {
    let label: String
    let amount: Decimal
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(amount.formatted(.currency(code: "USD")))
                .font(.footnote.bold())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Report Table

struct ReportTableCard: View {
    let shifts: [Shift]
    @Binding var expandedNote: Shift?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column headers
            ReportTableHeader()
            
            Divider()
            
            // Rows
            ForEach(shifts) { shift in
                ReportTableRow(
                    shift: shift,
                    isExpanded: expandedNote?.id == shift.id,
                    onToggleNote: {
                        if expandedNote?.id == shift.id {
                            expandedNote = nil
                        } else {
                            expandedNote = shift
                        }
                    }
                )
                if shift.id != shifts.last?.id {
                    Divider()
                }
            }
            
            // Totals footer
            Divider()
            ReportTableTotals(shifts: shifts)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ReportTableHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Date").frame(width: 70, alignment: .leading)
            Text("Site").frame(maxWidth: .infinity, alignment: .leading)
            Text("Duration").frame(width: 54, alignment: .trailing)
            Text("Total").frame(width: 70, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }
}

struct ReportTableRow: View {
    let shift: Shift
    let isExpanded: Bool
    let onToggleNote: () -> Void
    
    var durationText: String {
        switch shift.payUnit {
        case .perDay: return shift.dayFraction?.label ?? "Full"
        case .perHour:
            let h = shift.hoursWorked ?? 0
            return "\(h.formatted())h"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(shift.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .frame(width: 70, alignment: .leading)
                    .font(.footnote)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(shift.site?.name ?? "—")
                            .font(.footnote.bold())
                            .lineLimit(1)
                        if shift.hasStreakBonus {
                            Text("🎯").font(.caption)
                        }
                    }
                    if let emp = shift.site?.employer?.name {
                        Text(emp).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(durationText)
                    .frame(width: 54, alignment: .trailing)
                    .font(.footnote)
                
                Text(shift.totalPay.formatted(.currency(code: "USD")))
                    .frame(width: 70, alignment: .trailing)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            if let notes = shift.notes, !notes.isEmpty {
                Button(action: onToggleNote) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(isExpanded ? "Hide notes" : notes.prefix(40) + (notes.count > 40 ? "…" : ""))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if isExpanded {
                    Text(notes)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ReportTableTotals: View {
    let shifts: [Shift]
    
    var total: Decimal { shifts.reduce(0) { $0 + $1.totalPay } }
    
    var body: some View {
        HStack(spacing: 4) {
            Text("Totals")
                .font(.footnote.bold())
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text(total.formatted(.currency(code: "USD")))
                .frame(width: 70, alignment: .trailing)
                .font(.footnote.bold())
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
