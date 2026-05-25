# Client Interview App Checklist — AnesPayTracker

Date started: 2026-05-25

Purpose: collect client-interview clarifications before turning them into implementation tasks. Keep this as the human-readable checklist, then promote items into `docs/RUNTIME_FEEDBACK_BACKLOG.md` when ready to implement.

## Intake rules

For each client clarification, capture:

1. What the client/user noticed or requested.
2. Where it appears in the app.
3. Why it matters for workflow or trust.
4. Proposed app behavior.
5. Acceptance criteria.
6. Implementation priority.

---

## Captured items

### CI-001 — Shift Detail upper-left label is odd and non-functional

Status: implementation started
Priority: High, small UX/trust fix
Area: Shift Detail
Likely file: `AnesPayTracker/Views/Review/ShiftDetailView.swift`

Observation:

- There is an odd, non-functional Shift Detail label/control in the upper-left corner.
- This appears to be the old toolbar close control in the `.cancellationAction` position.

Why it matters:

- Shift Detail is a review screen. Ambiguous or non-working controls reduce user confidence when checking pay.
- The screen already has an Edit action; closing the detail view should be obvious and reliable.

Proposed behavior:

- Remove the odd upper-left close label/control from Shift Detail.
- Put clear actions in the upper-right area:
  - `Edit` to edit the shift.
  - `Done` to close/dismiss Shift Detail.

Acceptance criteria:

- Shift Detail no longer shows an odd/non-functional label in the upper-left corner.
- User can still close Shift Detail with a clear `Done` button.
- User can still edit the shift with `Edit`.
- iOS Simulator and Mac Catalyst builds still pass.

Implementation note:

- Initial code change made in `ShiftDetailView.swift`: replaced the `.cancellationAction` close toolbar item with a `.confirmationAction` toolbar group containing `Edit` and `Done`.
- Needs runtime confirmation in the Mac Catalyst app.

---

## Pending interview notes to add

Add additional client clarifications below as they come in, then promote them into the runtime backlog before coding larger changes.
