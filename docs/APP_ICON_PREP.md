# App Icon Prep — AnesPayTracker

Goal: prepare a clean, App-Store-appropriate icon direction before the TestFlight archive step.

## Grounded project constraints

From the current repo:

- App name recommendation for continuity: `AnesPayTracker`
- Current accent color is a calm blue/teal family
- App function: track shifts, estimate paychecks, monitor bonuses/streaks
- App should feel trustworthy, professional, native, and readable at small sizes
- Current `AppIcon.appiconset` is missing the actual 1024×1024 icon image

## What the icon should communicate

Best message stack:

1. shift tracking
2. pay / paycheck confidence
3. professional reliability

Avoid trying to show too much.

## What to avoid

- no tiny text
- no detailed medical scene
- no syringe / red-cross clichés
- no cluttered spreadsheet look
- no too-many symbols in one icon
- no low-contrast pastel-on-pastel mark

## Recommended design direction

Primary recommendation:

- Apple-style rounded, simple, high-contrast icon
- blue/teal base aligned with the current app accent
- one strong metaphor combining:
  - calendar / shift card
  - pay / dollar / paycheck confidence

Why this is the best first direction:

- it matches the app’s real behavior
- it reads well at small sizes
- it stays professional without looking generic-medical

## Created concept files

I created three starter SVG concepts here:

1. `assets/icon-concepts/icon-concept-1-calendar-pay.svg`
   - strongest “calendar + pay” concept
   - best direct fit for the app’s core promise

2. `assets/icon-concepts/icon-concept-2-ledger-check.svg`
   - strongest “verified payout / reliable record” concept
   - feels more operational and accounting-like

3. `assets/icon-concepts/icon-concept-3-bars-pay.svg`
   - strongest “earnings growth / tracking” concept
   - feels more analytical than scheduling-oriented

## My recommendation

Start with Concept 1.

Why:

- best semantic match to shift tracking + paycheck estimation
- easiest for a first-time user to understand at a glance
- most likely to still work after future app expansion

## Best next manual step

1. Open the SVG files and pick a preferred direction.
2. If desired, refine the chosen concept in Figma, Sketch, Illustrator, or another editor.
3. Export a final 1024×1024 PNG.
4. Drop that PNG into:
   `AnesPayTracker/Assets.xcassets/AppIcon.appiconset/`
5. Rebuild/archive in Xcode.

## If you want Hermes to continue

The best next icon-specific task would be one of:

1. tighten one concept into a more premium final SVG
2. simplify one concept for better small-size readability
3. create a more medical-adjacent version without clichés
4. prepare a final app-icon handoff prompt for a designer or image model
