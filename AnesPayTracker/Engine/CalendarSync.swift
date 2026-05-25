import Foundation
import EventKit

// MARK: - Calendar Sync Manager

@Observable
final class CalendarSyncManager {
    
    static let shared = CalendarSyncManager()
    
    private let store = EKEventStore()
    private(set) var isAuthorized = false
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var selectedCalendarID: String?
    
    private let selectedCalendarKey = "selectedCalendarID"
    private let calendarOptInKey = "calendarOptIn"
    var isOptedIn: Bool {
        get { UserDefaults.standard.bool(forKey: calendarOptInKey) }
        set { UserDefaults.standard.set(newValue, forKey: calendarOptInKey) }
    }
    
    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .fullAccess
        selectedCalendarID = UserDefaults.standard.string(forKey: selectedCalendarKey)
    }
    
    // MARK: - Authorization
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Calendar Management
    
    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }
    
    func setSelectedCalendar(_ calendar: EKCalendar) {
        selectedCalendarID = calendar.calendarIdentifier
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: selectedCalendarKey)
    }
    
    func createWorkCalendar() -> EKCalendar? {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Work"
        calendar.cgColor = CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
        
        if let source = store.defaultCalendarForNewEvents?.source {
            calendar.source = source
        } else if let iCloudSource = store.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = iCloudSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            return nil
        }
        
        do {
            try store.saveCalendar(calendar, commit: true)
            setSelectedCalendar(calendar)
            return calendar
        } catch {
            return nil
        }
    }
    
    // MARK: - Event CRUD
    
    @discardableResult
    func addEvent(for shift: Shift) -> String? {
        guard isOptedIn, isAuthorized else { return nil }
        
        let calendarID = selectedCalendarID
        guard let calendar = calendarID.flatMap({ store.calendar(withIdentifier: $0) })
                ?? store.defaultCalendarForNewEvents else { return nil }
        
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = eventTitle(for: shift)
        event.notes = eventNotes(for: shift)
        event.startDate = shift.date
        event.endDate = shift.date
        event.isAllDay = true
        
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }
    
    func updateEvent(for shift: Shift) {
        guard isOptedIn, isAuthorized, let eventID = shift.calendarEventID else { return }
        
        guard let event = store.event(withIdentifier: eventID) else {
            // Event gone, add fresh
            return
        }
        
        event.title = eventTitle(for: shift)
        event.notes = eventNotes(for: shift)
        event.startDate = shift.date
        event.endDate = shift.date
        event.isAllDay = true
        
        try? store.save(event, span: .thisEvent)
    }
    
    func removeEvent(for shift: Shift) {
        guard let eventID = shift.calendarEventID,
              let event = store.event(withIdentifier: eventID) else { return }
        try? store.remove(event, span: .thisEvent)
    }
    
    // MARK: - Formatting
    
    private func eventTitle(for shift: Shift) -> String {
        let siteName = shift.site?.name ?? "Work"
        let pay = shift.totalPay.formatted(.currency(code: "USD"))
        return "\(siteName) — \(pay)"
    }
    
    private func eventNotes(for shift: Shift) -> String {
        var lines: [String] = []
        
        switch shift.payUnit {
        case .perDay:
            lines.append("Day fraction: \(shift.dayFraction?.label ?? "Full")")
        case .perHour:
            let hrs = shift.hoursWorked ?? 0
            lines.append("Hours: \(hrs.formatted())")
        }
        
        lines.append("Base pay: \(shift.basePay.formatted(.currency(code: "USD")))")
        
        if let splash = shift.splashAmount, splash > 0 {
            lines.append("Splash: \(splash.formatted(.currency(code: "USD")))")
        }
        if let bonus = shift.bonusSplashAmount, bonus > 0 {
            lines.append("Bonus splash: \(bonus.formatted(.currency(code: "USD")))")
        }
        for bonus in shift.customBonuses ?? [] where bonus.totalAmount > 0 {
            lines.append("\(bonus.name): \(bonus.totalAmount.formatted(.currency(code: "USD")))")
        }
        if let streak = shift.streakBonusAmount, streak > 0 {
            lines.append("🎯 Streak bonus: \(streak.formatted(.currency(code: "USD")))")
        }
        lines.append("Total: \(shift.totalPay.formatted(.currency(code: "USD")))")
        
        if let notes = shift.notes, !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }
        
        return lines.joined(separator: "\n")
    }
}
