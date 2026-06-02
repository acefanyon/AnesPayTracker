# AnesPayTracker Streak + Calendar + Employer UX Plan

> **For Hermes:** Use `subagent-driven-development` or a focused implementation pass to execute this plan in small verified slices. Keep each slice buildable on iOS Simulator and Mac Catalyst. Do not commit local signing or `xcuserdata` files.

**Goal:** Implement the next product-fit pass for AnesPayTracker by correcting streak behavior, improving calendar interactions, adding on-call support, enabling global employer editing, and making pay-period details explain where money comes from.

**Architecture:** Treat this as a model-first change with UI follow-through. The highest-risk part is the streak definition change because it affects stored pay logic, reporting, calendar visuals, and pay-period explanations. Land the work in thin vertical slices: model/safety scaffolding first, then streak engine, then calendar interactions, then employer editing and pay-period UX.

**Tech Stack:** SwiftUI, SwiftData, Mac Catalyst, iOS Simulator, existing Python verification scripts under `scripts/`.

**Execution status (current):**
- Slices 1-9 are implemented locally and verified.
- Current verified files include the streak model/engine, streak explanation UI, pay-period/report updates, calendar tap-to-add flow, shift copy/paste flow, on-call defaults/snapshots/UI, global employer editing/versioning safeguards, and pay-period component breakdown.
- No further planned work.
\n ---\n

---

## Latest requested behavior to plan for

From the last client-feedback session:

1. **Streak definition must change**
   - General target behavior:
     - Each employer streak rule defines a configurable threshold (`requiredDays`) within a calendar quarter,
     - every qualifying shift **after the threshold has been met** in that same quarter earns the configured extra per-day amount,
     - that extra amount is **paid quarterly**,
     - the threshold-reaching shift itself does **not** earn the post-threshold bonus,
     - the count resets at the start of the next quarter.
   - Example scenario:
     - After 12 days worked in a calendar quarter for one employer,
     - every remaining qualifying day in that same quarter earns **an extra $200/day**,
     - so the first bonus-earning shift is **day 13**.
2. **Streak visual is not clear enough** and should better explain both progress and the post-threshold earning state.
3. **Calendar day tap should open Add Shift** with that day prefilled.
4. **Copy/paste shift** workflow should exist for repeating similar work across days.
5. **On-Call** should be a first-class shift label/flag and should support an employer-defined on-call bonus.
6. **Employer editing** should be available after creation so pay/bonus rules can be changed globally.
7. **Pay Period shift details** should explain base pay and bonus components instead of only showing a lump total.

---

## Locked business rules

These rules are now confirmed and should be treated as implementation requirements rather than assumptions.

1. The new streak bonus should be treated as **earned on qualifying post-threshold shifts** but **reported as a quarterly payout item**, similar to asynchronous bonus payout logic already added.
2. The streak model needs to support both:
   - threshold definition (`requiredDays`, quarter window)
   - post-threshold per-day reward amount (`$200/day` style behavior)
3. The **threshold-reaching shift does not earn** the post-threshold streak bonus; the **next qualifying shift after threshold completion** is the first bonus-earning shift.
4. **Partial days count as a full streak day** for threshold progress.
5. Copy/paste should duplicate **editable shift inputs**, not computed totals.
6. On-call defaults should come from the employer, but the shift should preserve a snapshot amount so historical records stay accurate after employer edits.
7. **On-call payout timing is always tied to the service date.**
8. **Employer edits must not recompute reconciled history.** Changes should only affect future shifts and existing shifts that have not yet occurred.
9. **Saved future shifts should remain unchanged after employer edits.** New employer defaults should apply only to shifts created after the edit, unless the app later adds an explicit bulk-update flow.
10. **If the StreakEngine rewrite proves unreliable, the acceptable workaround is to create a second version of the employer with the new streak rule** rather than mutating the original employer/history in place.
11. **Copy/paste should copy shift notes but not source metadata by default.**
12. **Tapping a calendar day that already has shifts should open a day sheet** listing that day's shifts plus an Add Shift action.
13. **Only one streak rule may be active per employer at a time.** Older or alternate rules should stay inactive unless the user deliberately switches, and legacy multi-active data should resolve to the newest active rule.

---

## Current files likely involved

**Models / engine**
- `AnesPayTracker/Model/Models.swift`
- `AnesPayTracker/Engine/StreakEngine.swift`
- `AnesPayTracker/Engine/SeedData.swift`
- `scripts/verify_pay_calculation_cases.py`
- `scripts/verify_bonus_payout_reports.py`

**Calendar / shift entry / review UI**
- `AnesPayTracker/Views/Review/CalendarView.swift`
- `AnesPayTracker/Views/Review/StreakStatusView.swift`
- `AnesPayTracker/Views/Review/ShiftDetailView.swift`
- `AnesPayTracker/Views/Review/PayPeriodView.swift`
- `AnesPayTracker/Views/Entry/AddShiftView.swift`

**Employer setup / editing**
- `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- `AnesPayTracker/Views/Settings/SettingsView.swift`

**Optional support files that may be needed**
- new helper/view files under `AnesPayTracker/Views/Review/`
- new copy/paste helper under `AnesPayTracker/Engine/` or `AnesPayTracker/Support/`

---

## Recommended implementation order

### Slice 1 — Safety scaffold before changing streak behavior

**Objective:** Make the streak-rule rewrite safer before touching production pay logic.

**Files:**
- Modify: `scripts/verify_pay_calculation_cases.py`
- Modify: `scripts/verify_bonus_payout_reports.py`
- Update docs if needed: `docs/RUNTIME_FEEDBACK_BACKLOG.md`

**Steps:**
1. Add explicit verification cases for quarter-based streak progression:
   - shifts before the rule's `requiredDays` threshold = no extra per-day streak payout
   - the threshold-reaching shift = still no per-day streak payout
   - the next qualifying shift after threshold completion = per-day streak amount applies
   - quarter boundary resets streak progression
   - partial-day shifts still count as full streak days toward the threshold
2. Add a payout-report expectation that quarterly streak bonus rows land in the correct quarter payout bucket.
3. Record expected example numbers using one concrete scenario from feedback (`12 days -> +$200/day starting on day 13`) while keeping the implementation rule threshold-configurable.
4. Add a forward-only employer-edit expectation: changed employer defaults must not rewrite reconciled history.

**Verification:**
- `python3 scripts/verify_pay_calculation_cases.py`
- `python3 scripts/verify_bonus_payout_reports.py`

**Why first:** The streak rewrite touches money logic and report timing. A small safety net reduces guesswork.

---

### Slice 2 — Redesign the streak model for quarterly post-threshold earning

**Objective:** Represent the new streak definition cleanly in data.

**Files:**
- Modify: `AnesPayTracker/Model/Models.swift`
- Modify: `AnesPayTracker/Engine/SeedData.swift`

**Model changes to plan for:**
1. Ensure `StreakRule` can express:
   - required qualifying days
   - quarter-based evaluation window
   - post-threshold per-day bonus amount
   - payout timing of next quarterly payout
   - rule values that can be changed later for newly evaluated shifts without rewriting preserved historical shift snapshots
2. Ensure `Shift` can store enough historical data for display/reporting, likely including:
   - whether the shift qualified for post-threshold streak earnings
   - the streak amount earned on that shift
   - payout schedule metadata if not already derivable
   - enough snapshot context to explain historical earnings even if the employer's current streak rule changes later
3. Preserve existing already-stored totals where possible so migrations stay simple.

**Design preference:**
- Prefer storing the **earned streak amount snapshot on the shift** rather than recomputing historical dollars solely from mutable employer settings.

**Verification:**
- Project still builds after model changes
- Existing verification scripts still pass or are updated intentionally

---

### Slice 3 — Rewrite the streak engine for quarter-based progression

**Objective:** Make streak computation match the real contract behavior.

**Files:**
- Modify: `AnesPayTracker/Engine/StreakEngine.swift`
- Potentially modify: `AnesPayTracker/Model/Models.swift`

**Expected behavior:**
1. Group shifts by employer and calendar quarter.
2. Sort shifts deterministically within each quarter.
3. Count each qualifying saved shift as **one full streak day**, even if it is a partial day.
4. Do **not** award the post-threshold bonus on the threshold-reaching shift unless the business rule explicitly says so.
5. Award the configured per-day streak amount starting with the first shift after the threshold is met.
6. Reset the count on quarter rollover.

**Implementation note:**
- Because partial days count fully for streak progress, streak qualification should be based on qualifying shift presence rather than prorated hours/day fractions.

**Verification:**
- `python3 scripts/verify_pay_calculation_cases.py`
- manual seeded-data spot check in app

---

### Slice 4 — Clarify streak UI and pay explanation

**Objective:** Make the user understand both progress and payout state.

**Files:**
- Modify: `AnesPayTracker/Views/Review/StreakStatusView.swift`
- Modify: `AnesPayTracker/Views/Review/ShiftDetailView.swift`
- Modify: `AnesPayTracker/Views/Review/PayPeriodView.swift`

**UI changes to plan for:**
1. `StreakStatusView` should show a progress state such as:
   - `8 of 12 days toward +$200/day quarterly streak bonus`
2. After threshold is met, it should switch to an earning state such as:
   - `Threshold reached — now earning +$200/day for the rest of this quarter`
3. `ShiftDetailView` should distinguish between:
   - money paid with the shift/service date
   - money earned now but paid later quarterly
4. `PayPeriodView` should expose a breakdown for each shift or row so the user can see:
   - base pay
   - splash / named bonuses
   - on-call bonus
   - streak-related amount and whether it is pending quarterly payout

**Verification:**
- manual UI check in running app
- Mac Catalyst build
- iOS Simulator build

---

### Slice 5 — Calendar day tap should prefill Add Shift

**Objective:** Reduce friction when adding shifts from the calendar.

**Files:**
- Modify: `AnesPayTracker/Views/Review/CalendarView.swift`
- Modify: `AnesPayTracker/Views/Entry/AddShiftView.swift`

**Planned behavior:**
1. Tapping a day cell with no shift should open Add Shift.
2. Tapping a day cell with existing shifts should open a **day sheet** showing:
   - all shifts for that date
   - tap-through into a specific shift
   - an `Add Shift` action prefilled to that date
3. Add Shift should accept an injected date and initialize the form to that date.
4. If there is a selected day state already in Calendar, reuse it rather than creating duplicate calendar-selection state.

**Verification:**
- tap a date in month view -> Add Shift opens with matching date
- save shift -> shift appears on chosen day
- existing shift detail navigation still works

---

### Slice 6 — Copy/paste shift workflow

**Objective:** Make repeated schedule entry fast.

**Files:**
- Modify: `AnesPayTracker/Views/Review/CalendarView.swift`
- Modify: `AnesPayTracker/Views/Review/ShiftDetailView.swift`
- Modify: `AnesPayTracker/Views/Entry/AddShiftView.swift`
- Optional new helper: `AnesPayTracker/Engine/ShiftDraftClipboard.swift`

**Recommended design:**
1. Create a lightweight serializable draft object containing user-editable fields only:
   - employer/site reference IDs if safe
   - date excluded or overridden on paste
   - hours/day fraction
   - shift type / schedule flags
   - notes
   - enabled custom bonuses
   - on-call flag and amount
2. Copy **notes by default**.
3. Do **not** copy source metadata by default.
4. Add a `Copy Shift` action from Shift Detail and/or calendar context menu.
5. Add a `Paste Shift` affordance when opening Add Shift from another date.
6. Default pasted shift to the currently selected target date so the user can quickly replicate the entry.

**Avoid:**
- copying computed totals directly
- copying immutable record identity or reconciliation metadata

**Verification:**
- copy existing shift
- open another day
- paste draft
- confirm date stays on target day and editable fields transfer correctly

---

### Slice 7 — Add on-call as a first-class employer + shift concept

**Objective:** Support schedules where being on call changes pay and should be visible on the calendar.

**Files:**
- Modify: `AnesPayTracker/Model/Models.swift`
- Modify: `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- Modify: `AnesPayTracker/Views/Settings/SettingsView.swift`
- Modify: `AnesPayTracker/Views/Entry/AddShiftView.swift`
- Modify: `AnesPayTracker/Views/Review/CalendarView.swift`
- Modify: `AnesPayTracker/Views/Review/ShiftDetailView.swift`

**Planned behavior:**
1. Employer can define a default on-call bonus/rate.
2. Add/Edit Shift includes an `On-Call` toggle.
3. When enabled, shift stores:
   - `isOnCall`
   - snapshot of the on-call amount used for that shift
4. On-call bonus is always treated as **service-date pay**, not deferred payout.
5. Calendar should visually distinguish on-call shifts.
6. Shift detail and pay-period detail should show the on-call component clearly.

**Verification:**
- create employer with on-call bonus
- save on-call shift
- total updates correctly
- calendar styling appears
- shift detail shows on-call line item

---

### Slice 8 — Global employer editing

**Objective:** Let the user revise employer-wide pay/bonus rules after initial setup.

**Files:**
- Modify: `AnesPayTracker/Views/Settings/SettingsView.swift`
- Modify: `AnesPayTracker/Views/Setup/EmployerSetupWizard.swift`
- Potentially modify: `AnesPayTracker/Engine/StreakEngine.swift`

**Recommended design:**
1. Reuse `EmployerSetupWizard` in an edit mode instead of building a separate large editor.
2. Prepopulate all editable fields.
3. Save back to the selected employer.
4. Do **not** mutate already-saved future shifts automatically.
5. Apply edited defaults only to **new shifts created after the edit**.
6. Do **not** recompute reconciled history.
7. Be explicit in code and UI about history behavior so the app does not silently rewrite already-settled pay records.
8. If the streak-rule migration cannot be trusted for an existing employer, support a **duplicate/version employer** fallback path:
   - create a second employer record prefilled from the original
   - attach the new streak rule to the new employer version
   - preserve the original employer and its historical shifts unchanged
   - route only newly created shifts to the new employer version
9. Enforce **one active streak rule per employer** in both setup and settings UI. If the user activates a different rule, automatically deactivate the previous one rather than trying to merge rule effects.
10. If bulk update is ever desired later, add it as a separate explicit workflow rather than hidden side-effect behavior.

**Verification:**
- edit employer name/rates/bonuses
- confirm settings persist
- add a new shift and confirm new defaults apply
- confirm old shift snapshots remain sensible
- if using employer-version fallback, confirm old employer history remains unchanged while new shifts can target the duplicated employer version

---

### Slice 9 — Pay-period component breakdown

**Objective:** Make pay periods trustworthy by exposing how each shift total is composed.

**Files:**
- Modify: `AnesPayTracker/Views/Review/PayPeriodView.swift`
- Potentially reuse components from: `AnesPayTracker/Views/Review/ShiftDetailView.swift`

**Planned behavior:**
1. Each pay-period row should support an expanded detail state or embedded breakdown card.
2. Breakdown should include at minimum:
   - base pay
   - splash / bonus splash
   - named custom bonuses
   - on-call bonus
   - streak-related amount
   - total
3. If a line item is paid later, label it accordingly rather than implying it belongs in the immediate paycheck total.

**Verification:**
- compare a known shift in Shift Detail vs Pay Period breakdown
- numbers and labels match

---

## Suggested execution order after planning

1. Slice 1 — safety scaffold
2. Slice 2 — streak model
3. Slice 3 — streak engine
4. Slice 4 — streak explanation UI
5. Slice 5 — tap-to-add date prefill
6. Slice 7 — on-call model + UI
7. Slice 8 — employer editing
8. Slice 9 — pay-period breakdown
9. Slice 6 — copy/paste shift

**Why this order:**
- It resolves money-model correctness first.
- It delivers the highest-trust fixes before convenience features.
- Copy/paste is valuable but safer once Add Shift, employer defaults, and on-call fields are stable.

---

## Remaining open questions before implementation

No blocking product decisions remain for the first implementation pass.

Optional follow-up decisions can be deferred until after the first buildable version:
1. Whether copy/paste should later offer an advanced toggle for including source metadata.
2. Whether the calendar day sheet should later support bulk actions such as duplicate, delete, or reconcile shortcuts.
3. Whether a future employer-edit flow should offer an explicit bulk-update wizard for unreconciled upcoming shifts.

---

## Verification commands

```bash
cd /Users/jasonvargas/Projects/AnesPayTracker

python3 scripts/verify_pay_calculation_cases.py
python3 scripts/verify_bonus_payout_reports.py

xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

xcodebuild \
  -project AnesPayTracker.xcodeproj \
  -scheme AnesPayTracker \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

---

## Do not commit automatically

Leave these out unless intentionally reviewed:
- `.DS_Store`
- `AnesPayTracker.xcodeproj/project.xcworkspace/xcuserdata/`
- `AnesPayTracker.xcodeproj/xcuserdata/`
- local signing/team settings in `project.pbxproj`
- `AnesPayTracker/AnesPayTracker.entitlements` unless required and reviewed
