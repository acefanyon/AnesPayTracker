# AnesPay — Shift Pay Tracker

A clean, native SwiftUI pay-tracking app for a 1099/contract anesthesiologist.

## Requirements

- Xcode 15+
- iOS 17+ / macOS 14+
- An Apple Developer account (free or paid) for device builds

## How to Open

1. Clone or download this repository
2. Open `AnesPayTracker.xcodeproj` in Xcode
3. Select your development team in **Signing & Capabilities** (AnesPayTracker target)
4. Choose a simulator or your device and press **Run**

The app seeds realistic example data on first launch so you can explore everything immediately.

## CloudKit Sync Setup (for real device / production use)

1. In Xcode, select the **AnesPayTracker** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** → add **iCloud**
4. Check **CloudKit** and create a container (e.g. `iCloud.com.anespay.tracker`)
5. Build and run — SwiftData handles the sync automatically

For development/simulator testing, CloudKit is set to `.automatic` and will gracefully fall back to local-only storage if iCloud isn't configured.

## Architecture

```
AnesPayTracker/
├── App/
│   ├── AnesPayTrackerApp.swift   # App entry point, ModelContainer, CloudKit config, seed
│   ├── ContentView.swift         # Root tab view + welcome / setup flow
│   └── Theme.swift               # Accent color, font helpers, Dynamic Type notes
│
├── Model/
│   └── Models.swift              # SwiftData @Model classes:
│                                 #   Employer, Site, Shift, StreakRule, ContactPerson
│                                 #   + value types: SourceNote, EditRecord, all enums
│
├── Engine/
│   ├── StreakEngine.swift         # Streak computation, progress tracking, pay period math
│   ├── CalendarSync.swift         # EventKit integration (opt-in)
│   └── SeedData.swift             # First-launch example data
│
└── Views/
    ├── Setup/
    │   └── EmployerSetupWizard.swift   # 4-step guided wizard
    ├── Entry/
    │   └── AddShiftView.swift          # Fast shift entry (hot path)
    ├── Review/
    │   ├── CalendarView.swift          # Month grid with shift chips
    │   ├── ShiftDetailView.swift       # Full pay breakdown + edit history
    │   ├── PayPeriodView.swift         # Grouped by pay period with totals
    │   └── StreakStatusView.swift      # Progress bars + trigger history
    ├── Report/
    │   ├── ReportView.swift            # Filterable table + export
    │   └── PDFReportGenerator.swift    # UIGraphicsPDFRenderer export
    ├── Settings/
    │   └── SettingsView.swift          # Employer/site/streak editing, calendar, text size
    └── Components/
        └── CurrencyField.swift         # Decimal currency input
```

## Domain Model

- **Employer** — who pays her. Has contact persons, pay cadence, streak rules.
- **Site** — hospital or surgical center under an employer. Has pay unit (per-day or per-hour) and base rate.
- **Shift** — one worked day. Records date, duration (fraction or hours), splash/bonus-splash amounts, source note, edit history.
- **StreakRule** — N qualifying days within a window (rolling/month/pay period) → flat bonus. Engine attributes the bonus to the triggering shift.

## Key Features

- **Fast shift entry** — site tiles (recently used float to top), big day-fraction buttons, stepper for hours, splash toggles with defaults
- **Streak engine** — automatically recomputes after every save/edit; shows live progress ("3 of 4 days toward $500")
- **Calendar sync** — opt-in EventKit integration; creates a "Work" calendar on first run if desired
- **Pay period view** — grouped by employer's cadence with expandable period breakdowns
- **Report + PDF** — filterable by date range, employer, and site; exports a clean print-ready PDF via `UIGraphicsPDFRenderer`
- **Edit audit trail** — every edit records a summary and timestamp; "edited" badge visible in all views
- **Dynamic Type** — all text uses SwiftUI system fonts; tested up to Accessibility XXXL
- **No sign-in, no third-party SDKs, no analytics**

## Things to Finish in Xcode

1. **Signing** — assign your development team (required to run on device)
2. **CloudKit container** — add iCloud capability and create a container ID
3. **App icon** — drop your 1024×1024 icon into `Assets.xcassets/AppIcon.appiconset/`
4. **Bundle ID** — change `com.anespay.tracker` to your own reverse-domain if desired
5. **Mac Catalyst** — `TARGETED_DEVICE_FAMILY = "1,2"` covers iPhone + iPad; add `"6"` for Mac Catalyst or create a native macOS target
6. **Accessibility audit** — run Xcode's Accessibility Inspector against the shift entry flow to verify tap target sizes on your target devices

## Spec Coverage

| Feature | Status |
|---|---|
| Employer + site setup wizard | ✅ |
| Per-day (fraction) and per-hour shifts | ✅ |
| Splash + bonus splash toggles | ✅ |
| Streak engine (rolling / month / pay period) | ✅ |
| Streak bonus attributed to triggering shift | ✅ |
| Calendar view with shift chips + streak badge | ✅ |
| Pay period view with totals breakdown | ✅ |
| Shift detail with full pay breakdown | ✅ |
| Streak status with progress bars + history | ✅ |
| Report with date range + employer/site filter | ✅ |
| PDF export via share sheet | ✅ |
| Edit audit trail (summary + timestamp) | ✅ |
| Source note (who/when/how) | ✅ |
| EventKit calendar sync (opt-in) | ✅ |
| SwiftData + CloudKit config | ✅ |
| Seed data (1 employer, 2 sites, 1 streak rule) | ✅ |
| Dynamic Type support | ✅ |
| No third-party dependencies | ✅ |
