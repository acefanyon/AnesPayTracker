import Foundation
import SwiftData

// MARK: - Employer

@Model
final class Employer {
    var id: UUID
    var name: String
    var contactPersons: [ContactPerson]
    var payCadence: PayCadence
    var customCadenceDays: Int?
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Site.employer)
    var sites: [Site]
    
    @Relationship(deleteRule: .cascade, inverse: \StreakRule.employer)
    var streakRules: [StreakRule]
    
    @Relationship(deleteRule: .cascade, inverse: \CustomBonusType.employer)
    var customBonusTypes: [CustomBonusType]
    
    init(
        id: UUID = UUID(),
        name: String,
        contactPersons: [ContactPerson] = [],
        payCadence: PayCadence = .biweekly,
        customCadenceDays: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.contactPersons = contactPersons
        self.payCadence = payCadence
        self.customCadenceDays = customCadenceDays
        self.createdAt = createdAt
        self.sites = []
        self.streakRules = []
        self.customBonusTypes = []
    }
}

// MARK: - Custom Bonus Type

@Model
final class CustomBonusType {
    var id: UUID
    var employer: Employer?
    var name: String
    var payUnit: PayUnit
    var defaultAmount: Decimal
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        employer: Employer? = nil,
        name: String,
        payUnit: PayUnit = .perDay,
        defaultAmount: Decimal = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.employer = employer
        self.name = name
        self.payUnit = payUnit
        self.defaultAmount = defaultAmount
        self.createdAt = createdAt
    }
}

// MARK: - Contact Person

@Model
final class ContactPerson {
    var id: UUID
    var name: String
    var role: String?
    var phone: String?
    var email: String?
    
    init(id: UUID = UUID(), name: String, role: String? = nil, phone: String? = nil, email: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
    }
}

// MARK: - Site

@Model
final class Site {
    var id: UUID
    var name: String
    var employer: Employer?
    var payUnit: PayUnit
    var baseAmount: Decimal
    var defaultSplashAmount: Decimal?
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Shift.site)
    var shifts: [Shift]
    
    init(
        id: UUID = UUID(),
        name: String,
        employer: Employer? = nil,
        payUnit: PayUnit = .perDay,
        baseAmount: Decimal = 0,
        defaultSplashAmount: Decimal? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.employer = employer
        self.payUnit = payUnit
        self.baseAmount = baseAmount
        self.defaultSplashAmount = defaultSplashAmount
        self.createdAt = createdAt
        self.shifts = []
    }
    
    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Shift

@Model
final class Shift {
    var id: UUID
    var site: Site?
    var date: Date
    var payUnit: PayUnit
    var dayFraction: DayFraction?
    var hoursWorked: Double?
    var baseAmount: Decimal
    var splashAmount: Decimal?
    var bonusSplashAmount: Decimal?
    var streakBonusAmount: Decimal?
    var streakRuleTriggeredID: UUID?
    var customBonuses: [AppliedCustomBonus]?
    var notes: String?
    var sourceNote: SourceNote?
    var editHistory: [EditRecord]
    var calendarEventID: String?
    var createdAt: Date
    var lastEditedAt: Date?
    
    init(
        id: UUID = UUID(),
        site: Site? = nil,
        date: Date = Date(),
        payUnit: PayUnit = .perDay,
        dayFraction: DayFraction? = .full,
        hoursWorked: Double? = nil,
        baseAmount: Decimal = 0,
        splashAmount: Decimal? = nil,
        bonusSplashAmount: Decimal? = nil,
        streakBonusAmount: Decimal? = nil,
        streakRuleTriggeredID: UUID? = nil,
        customBonuses: [AppliedCustomBonus]? = nil,
        notes: String? = nil,
        sourceNote: SourceNote? = nil,
        editHistory: [EditRecord] = [],
        calendarEventID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.site = site
        self.date = date
        self.payUnit = payUnit
        self.dayFraction = dayFraction
        self.hoursWorked = hoursWorked
        self.baseAmount = baseAmount
        self.splashAmount = splashAmount
        self.bonusSplashAmount = bonusSplashAmount
        self.streakBonusAmount = streakBonusAmount
        self.streakRuleTriggeredID = streakRuleTriggeredID
        self.customBonuses = customBonuses
        self.notes = notes
        self.sourceNote = sourceNote
        self.editHistory = editHistory
        self.calendarEventID = calendarEventID
        self.createdAt = createdAt
        self.lastEditedAt = nil
    }
    
    var basePay: Decimal {
        switch payUnit {
        case .perDay:
            return baseAmount * (dayFraction?.multiplier ?? 1)
        case .perHour:
            return baseAmount * Decimal(hoursWorked ?? 0)
        }
    }
    
    var totalPay: Decimal {
        basePay
        + (splashAmount ?? 0)
        + (bonusSplashAmount ?? 0)
        + (customBonuses ?? []).reduce(Decimal(0)) { $0 + $1.totalAmount }
        + (streakBonusAmount ?? 0)
    }
    
    var isEdited: Bool { lastEditedAt != nil }
    var hasStreakBonus: Bool { (streakBonusAmount ?? 0) > 0 }
}

// MARK: - Streak Rule

@Model
final class StreakRule {
    var id: UUID
    var employer: Employer?
    var requiredDays: Int
    var windowType: StreakWindowType
    var windowDays: Int?
    var bonusAmount: Decimal
    var isActive: Bool
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        employer: Employer? = nil,
        requiredDays: Int = 4,
        windowType: StreakWindowType = .rollingDays,
        windowDays: Int? = 14,
        bonusAmount: Decimal = 0,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.employer = employer
        self.requiredDays = requiredDays
        self.windowType = windowType
        self.windowDays = windowDays
        self.bonusAmount = bonusAmount
        self.isActive = isActive
        self.createdAt = createdAt
    }
    
    var description: String {
        let window: String
        switch windowType {
        case .rollingDays:
            return "Work \(requiredDays) days in \(windowDays ?? 14) days → \(bonusAmount.formatted(.currency(code: "USD")))"
        case .calendarMonth:
            return "Work \(requiredDays) days in calendar month → \(bonusAmount.formatted(.currency(code: "USD")))"
        case .payPeriod:
            return "Work \(requiredDays) days in pay period → \(bonusAmount.formatted(.currency(code: "USD")))"
        }
        return window
    }
}

// MARK: - Value Types (Codable for SwiftData storage)

struct SourceNote: Codable {
    var contactName: String
    var contactedOn: Date
    var channel: ContactChannel
    
    enum ContactChannel: String, Codable, CaseIterable {
        case text = "Text"
        case email = "Email"
        case call = "Call"
        case inPerson = "In Person"
    }
}

struct EditRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var editedAt: Date
    var summary: String
}

struct AppliedCustomBonus: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var payUnit: PayUnit
    var amount: Decimal
    var quantity: Double
    
    var totalAmount: Decimal {
        switch payUnit {
        case .perDay:
            return amount * Decimal(quantity)
        case .perHour:
            return amount * Decimal(quantity)
        }
    }
}

// MARK: - Enums

enum PayCadence: String, Codable, CaseIterable {
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case custom = "Custom"
}

enum PayUnit: String, Codable, CaseIterable {
    case perDay = "Per Day"
    case perHour = "Per Hour"
}

enum DayFraction: String, Codable, CaseIterable {
    case quarter = "¼"
    case half = "½"
    case threeQuarter = "¾"
    case full = "Full"
    
    var multiplier: Decimal {
        switch self {
        case .quarter: return Decimal(0.25)
        case .half: return Decimal(0.5)
        case .threeQuarter: return Decimal(0.75)
        case .full: return Decimal(1.0)
        }
    }
    
    var label: String { rawValue }
    
    var accessibilityLabel: String {
        switch self {
        case .quarter: return "Quarter Day"
        case .half: return "Half Day"
        case .threeQuarter: return "Three Quarter Day"
        case .full: return "Full Day"
        }
    }
}

enum StreakWindowType: String, Codable, CaseIterable {
    case rollingDays = "Rolling Days"
    case calendarMonth = "Calendar Month"
    case payPeriod = "Pay Period"
}
