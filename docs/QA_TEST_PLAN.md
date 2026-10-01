# QA Test Plan

Last updated: 2026-10-01 (build 5)

Two layers:

1. **Automated checks** — run on every push by GitHub Actions (`.github/workflows/build.yml`) and locally with `for f in scripts/verify_*.py; do python3 "$f"; done`. Part A lists what they cover; Part B lists the functions that still need real, logic-executing tests.
2. **Manual simulator pass** — Part C. A scripted walk through every feature with test data whose correct totals are worked out in advance. Run it before every TestFlight/App Store upload.

The single most important rule across both: **the same money must show the same number everywhere** — Home, Pay Periods, the three Report modes, PDFs, and Shift Detail.

---

## Part A — What the automated checks cover today

The 17 `scripts/verify_*.py` scripts. All but one are *static* checks: they read the Swift source and confirm required code is present. They catch accidental deletions and regressions in wiring, but they do not run the app's logic.

| Area | Scripts |
|---|---|
| Pay formulas (Python re-implementation of the formulas, 10 worked cases) | `verify_pay_calculation_cases.py` |
| Paycheck anchors, payout schedules, estimator | `verify_paycheck_schedule_model.py`, `verify_paycheck_estimator_report.py`, `verify_bonus_payout_reports.py` |
| Streaks | `verify_streak_engine_slice3.py`, `verify_streak_ui_slice4.py`, `verify_single_active_streak_rule.py` |
| Shift entry, bonuses, on-call, copy/paste | `verify_bonus_entry_flow.py`, `verify_on_call_slice7.py`, `verify_copy_paste_slice6.py` |
| Calendar, pay periods | `verify_calendar_slice5.py`, `verify_slice9_payperiod_breakdown.py` |
| Employer editing, history snapshots | `verify_employer_editing_slice8.py` |
| TestFlight fixes, data safety, build number | `verify_testflight_seed_and_employer_edit.py`, `verify_testflight_ui_regressions.py`, `verify_remaining_finish_items.py` |
| Home tab | `verify_home_screen.py` |

CI also compiles the app for the iOS Simulator in both Release (what TestFlight ships) and Debug.

---

## Part B — Functions that should get real automated tests

These are the functions where a mistake changes someone's pay or loses data. Today they are only checked statically or by hand. Each should become an XCTest that runs the real Swift code (CI can run them on the simulator). In priority order:

1. **Pay formulas** — `Shift.basePay`, `Shift.bonusPay`, `Shift.onCallPay`, `Shift.totalPay`, `AppliedCustomBonus.totalAmount`
   - The 10 cases in `docs/PAY_CALCULATION_SAFETY_CHECKLIST.md`.
   - Prorating: per-day bonus with *Prorate for partial day* on → half day pays half; off → full amount.
   - On-call never prorates; streak bonus prorates by day fraction.
2. **Clock-in/out rounding** — `ClockTimeCalculator.ceilingQuarterHours`
   - 8:00 → 8.00; 8:01 → 8.25; 8:15 → 8.25; 8:16 → 8.50.
   - A shift that ends after midnight (clock-out earlier on the clock than clock-in).
3. **Pay periods and paydays** — `StreakEngine.payPeriodBounds(containing:employer:)`, `StreakEngine.paycheckDate(for:employer:)`
   - Oracle: work period Jun 7–20 paid Jun 26; next period paid Jul 10; prior period paid Jun 12.
   - Dates before the anchor; a period spanning New Year's stays one period; monthly cadence.
   - Employers *without* anchors fall back to a guessed (Jan-1-based biweekly) schedule; the UI flags those dates as estimated — see Fixed issue 2.
4. **Bonus payout schedules** — `BonusPayoutSchedule.payoutDate(for:)`
   - Monthly → last day of the following month.
   - Quarterly → Q1 Apr 30, Q2 Jul 31, Q3 Oct 31, Q4 Jan 31 (next year).
5. **Paycheck assignment** — `StreakEngine.paycheckAggregationRows(for:)`
   - Base and on-call land on the paycheck for the shift's period; each custom bonus and the streak bonus land on the paycheck for their payout date; zero amounts produce no row.
6. **Streaks** — `StreakEngine.recomputeStreaks(for:)`, `StreakEngine.progress(for:relativeTo:)`
   - Each window type (rolling days, calendar month, calendar quarter, pay period); the threshold shift; post-threshold per-day earning; only one active rule; totals recompute after a shift is edited or deleted.
7. **History safety** — editing a saved shift after its site's rate changed must keep the shift's original rate (fixed 2026-10-01; statically checked by `verify_history_and_pay_schedule_safety.py`).
8. **Migration defaults** — every required stored property added after its entity was created declares a default (`verify_model_migration_defaults.py`). Missing defaults made pre-June-1 development stores fail to open with "missing attribute values on mandatory destination attribute" (found 2026-10-01 in the simulator; fixed for build 5).
9. **Data safety** — `StoreSafety.backUpStoreIfNeeded()` copies the store once per build and keeps the last three; a store that can't be opened shows `StoreOpenFailedView` and deletes nothing; a store written by builds 1–4 opens in the current build with every record intact.
10. **Reconciliation invariant** — for any set of shifts, the sum of Pay Periods totals equals the sum of Paycheck Estimator rows (once every row's paycheck date has passed).

---

## Part C — Manual simulator pass

### Before you start

- **Fresh-install test (no sample data):** in Xcode choose **Product → Scheme → Edit Scheme… → Run → Build Configuration: Release**, then delete the app from the simulator (press and hold the icon → Remove App) and press ⌘R. Switch the setting back to **Debug** afterward. Debug runs always create the sample employer.
- **Simulator shortcuts:** ⌘S saves a screenshot to the Desktop; ⇧⌘A toggles light/dark mode; **Features → Toggle In-Call Status Bar** and **Device → Rotate** for layout checks.

### Test data

Create this employer in the setup wizard. The expected values below depend on it exactly.

- Employer **Test Group**, pay cadence **Biweekly**, default on-call amount **$250**
- Paycheck anchors: known pay-period end **Sun, Sep 27, 2026**; paycheck for that period **Fri, Oct 2, 2026**
- Site **Test Surgical** — per day, **$1,000**
- Site **Test Hospital** — per hour, **$150**
- Custom bonus **Holiday** — per day, **$250**, **Prorate for partial day: on**, paid **with shift**
- Streak rule — **Rolling Days**, **10 days in 14**, any bonus amount (set high on purpose so it doesn't trigger during this pass)
- One contact, any name

Then log these shifts:

| Date | Site | Entry | Expected total |
|---|---|---|---|
| Tue, Sep 22 | Test Surgical | Full day | **$1,000.00** |
| Thu, Sep 24 | Test Surgical | ½ day + Holiday | **$625.00** ($500 + $125 prorated) |
| Fri, Sep 25 | Test Hospital | Clock In/Out 7:00 AM → 3:01 PM | **$1,237.50** (rounds up to 8.25 hrs) |
| Tue, Sep 29 | Test Surgical | Full day + On-Call | **$1,250.00** |
| Wed, Sep 30 | Test Surgical | ½ day + On-Call | **$750.00** (on-call is not prorated) |

Pay periods produced by the anchors: **Sep 14–27 → paid Fri, Oct 2** and **Sep 28–Oct 11 → paid Fri, Oct 16**.

### Checklist

**C1. First launch (Release run)**
- [ ] No sample employer appears; the Welcome screen offers **Get Started**.
- [ ] The setup wizard opens and the employer above can be created.

**C2. Shift entry**
- [ ] Each shift's preview total matches the table *before* saving, and Shift Detail shows the same total after saving.
- [ ] Clock In/Out shows 8.25 hours for 7:00 → 3:01.
- [ ] Copy a shift and paste it onto another day; the pasted shift has the same total. Delete the copy afterward.

**C3. Home tab** — values depend on the day you test:

| | Testing Oct 1–2 | Testing Oct 3–16 |
|---|---|---|
| This work period | Sep 28 – Oct 11, **$2,000.00** earned, 2 shifts, paid **Fri, Oct 16** | same |
| Next paycheck | **Fri, Oct 2 — $2,862.50**, for work Sep 14 – 27, includes **$125.00** in bonuses | **Fri, Oct 16 — $2,000.00**, for work Sep 28 – Oct 11, includes **$500.00** in bonuses |

- [ ] Values match the table above.
- [ ] Streaks card shows **5 of 10 days** (when testing on or before Oct 5; the 14-day window then starts dropping the Sep 22 shift); **Details** opens the full streak screen and Back returns to Home.
- [ ] Recent shifts lists the five shifts newest first; tapping one opens its detail.
- [ ] Turn off **Use paycheck calendar anchors** in the employer editor → Home hides both cards and shows **Pay schedule not set up**; Pay Periods shows **Pay period dates are estimated**; the editor shows an orange warning under the toggle. Turn it back on with the same dates.

**C4. Same numbers everywhere**
- [ ] **Pay Periods:** Sep 14–27 = **$2,862.50**; Sep 28–Oct 11 = **$2,000.00**.
- [ ] **Report → Earnings**, September: **$4,862.50**.
- [ ] **Report → Paycheck Estimator:** Oct 2 check = **$2,862.50**; Oct 16 check = **$2,000.00** — identical to Home.
- [ ] **Report → Bonus Payouts:** Holiday $125.00 and on-call $500.00 appear on the expected dates.
- [ ] Export each report as PDF: the totals in the PDF match the screen.

**C5. Editing and deleting**
- [ ] Edit the Sep 22 shift's notes only → total stays $1,000.00; Shift Detail shows an edit-history entry.
- [ ] Delete the Sep 30 shift → Home earned drops to $1,250.00, Pay Periods updates, Streaks shows one day fewer. Re-add it.

**C6. History safety**
- [ ] In Settings, change Test Surgical's rate to **$1,200**. Existing shifts still show their old totals.
- [ ] A *new* Test Surgical full-day shift totals **$1,200.00**. Delete it afterward.
- [ ] Edit the Sep 22 shift: the edit screen shows a lock note — *Paid at this shift's saved rate of $1,000.00/day* — and after changing only the notes the total is still **$1,000.00**. Set the rate back to $1,000.

**C7. Employer editing**
- [ ] **Open Full Employer Editor**, delete the contact, save, reopen → the contact stays deleted.
- [ ] In the editor, sites, streak rules and bonuses that existing shifts use cannot be deleted.
- [ ] **Create Versioned Copy** creates a second employer and leaves the original and its shifts unchanged.

**C8. Calendar**
- [ ] Month and week views both show all five shifts on the right days.
- [ ] Tapping a day shows its shifts; adding a shift from a day pre-fills that date.

**C9. Exports and integrations**
- [ ] Shift Detail → share as calendar file (.ics): the share sheet opens with an event for that date.
- [ ] Settings → Calendar Sync: turning it on asks for calendar permission; a new shift then appears in the simulator's Calendar app.
- [ ] PDF previews open and can be shared.

**C10. Data safety and persistence**
- [ ] Stop the app in Xcode (■) and run it again: every shift and setting is still there.
- [ ] **Upgrade test** — mirrors what happens on a tester's phone. First delete the app from the simulator so the test starts clean. Then in Terminal:
  ```
  git switch --detach f5531f6
  ```
  This checks out build 3 (the build testers had). Run in Xcode (⌘R) — it creates the old sample data — and add one shift of your own. Then return to the current code:
  ```
  git switch hermes/initial-mac-plan
  ```
  Run again (⌘R). The shift is still there, and the store was copied aside first:
  ```
  open "$(xcrun simctl get_app_container booted com.anespay.tracker data)/Library/Application Support/StoreBackups"
  ```
  shows a `before-build-5` folder.

**C11. Display**
- [ ] Repeat Home, Add Shift and Calendar on an **iPhone SE (3rd generation)** simulator (smallest screen) and an **iPhone Pro Max**.
- [ ] Dark mode (⇧⌘A): all text readable.
- [ ] Largest text size (Xcode → Debug bar → Environment Overrides → Dynamic Type at the maximum): calendar day numbers don't truncate to "…"; no buttons overlap.
- [ ] Rotate to landscape: nothing is cut off.
- [ ] iPad simulator: the app launches and is usable.
- [ ] Mac Catalyst: choose **My Mac (Mac Catalyst)** and run; the app launches.

---

## Fixed issues (found while writing this plan, fixed 2026-10-01 for build 5)

1. **Editing a saved shift repriced it to the site's current rate.** `AddShiftView` sets `shift.baseAmount = site.baseAmount` on every save, including edits. After a site's rate changes in Settings, editing any old shift — even just its notes — silently changes its pay. This violated the history-safety rule in `AGENTS.md`. **Fixed:** an edited shift keeps its own `baseAmount` unless it moves to another site or the site's pay unit changes; the edit screen says which rate applies, and rate changes are recorded in edit history.
2. **Employers without paycheck anchors got guessed pay periods shown as fact.** The biweekly and custom fallbacks count from January 1 of each year, so the dates are almost always off and a period spanning New Year's splits in two. **Fixed:** `Employer.hasReliablePayPeriods` (monthly, or a known period end date) gates Home's work-period card; Pay Periods labels guessed dates as estimated; setup warns clearly when the anchors are off. The fallback math itself is unchanged, so existing data and reports are not affected.
