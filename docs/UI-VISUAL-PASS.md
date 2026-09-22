# RepLog — UI / visual verification handoff

Owner: Eamon or senior (handed off by the coder, 2026-09-22).
Everything below is ready to run: the app builds, the automated gate
(build + unit + XCUITest incl. the offline drill) is in
`scripts/mac-tests.sh`, and the simulator app carries a `-DemoData`
launch hook that seeds a small **synthetic** history (routine + 3 sessions
with sets/RPE/notes + bodyweight) so every screen can be captured
populated. No real training data is involved.

## What is already verified (do not re-do)

- Build: `** BUILD SUCCEEDED **` (app + RepLogWidget extension), iPhone 17 Pro sim.
- Unit tests: 36/36 (swift-testing).
- XCUITest: 7 tests — RPE entry (types 8.5, reads back), RPE chip labels
  (6/7/8/9 render without ".0"; 7.5/8.5 keep the decimal; tapping the "8"
  chip stores 8 and the cell shows "8"), session-row navigation (tap row →
  detail pushes), exercise search, sync URL+token (knob tap), set notes,
  and the in-simulator offline drill (plan §7.5: service down → finish →
  relaunch → service up → exactly one upload → delete → tombstone →
  re-import 409s).
- Service: 55/55 pytest; service-side offline drill; 6,524-row migration.
- Dark mode works: `xcrun simctl ui <udid> appearance dark` then relaunch
  (NOT `defaults write` on a shut-down simulator — that is why the earlier
  "appearance switch did not take effect" note was wrong).

## What this pass must do

1. **Dark-mode capture of every screen** (the references are dark mode).
   With the app in dark mode and `-DemoData` seeded, capture each screen
   below and compare it against the matching reference in
   `"/mnt/hermes-shared/RepCount Screenshots/"` (17 files, IMG_8144…IMG_8160).
   Record every comparison (match / difference / why) in
   `docs/BUILD-REPORT.md` §4. Only two were ever compared so far (Log tab,
   active workout).

2. **Screens to capture** (RepLog → likely reference):
   - Log tab (history, month sections, session rows) → IMG_8144
   - Active workout (populated: session card + exercise cards + set rows
     with RPE) → IMG_8156
   - Session detail (tap a session row) → one of IMG_8145/8146/8147
   - Routines list → IMG_8148/8149
   - Routine detail (Start this Workout, target mode, exercise list)
   - Select Exercise sheet (search + categories)
   - Exercise library (Edit Exercises / Edit Categories)
   - Statistics hub + a chart screen (populated)
   - Personal records
   - Profile (sync status, Export CSV, …)
   - Settings (all sections)
   - Onboarding (3 pages)
   - RPE input sheet (chips 6/7/7.5/8/8.5/9)
   - Rest timer sheet
   - Repeat Workout sheet
   The exact 1:1 mapping was not finished — identify it from the images
   themselves (they are labelled in order; IMG_8144 = Log, IMG_8156 =
   active workout are known).

3. **Known intended differences** (not bugs): RepLog adds the RPE column
   between Reps and Notes; RepLog's Profile has a Sync section where
   RepCount has an account block; RepLog ships no Premium upsell.

## Exact commands (run from the fleet host or the Mac)

```bash
# 1. Full automated gate first (build + 36 unit + 7 UI incl. offline drill):
scripts/mac-tests.sh

# 2. Boot the simulator and set dark mode (simctl ui — not defaults write):
ssh mac 'UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro" | head -1 | sed "s/.*(\\(.*\\))$/\\1/"); \
  xcrun simctl boot "$UDID"; \
  xcrun simctl ui "$UDID" appearance dark'

# 3. Build + install the app with demo data, launch:
ssh mac 'cd ~/Documents/RepLog && xcodebuild -scheme RepLog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build 2>&1 | tail -2 && \
  APP=$(find ~/Library/Developer/Xcode/DerivedData -name "RepLog.app" -path "*Debug-iphonesimulator*" | head -1) && \
  xcrun simctl install booted "$APP" && \
  xcrun simctl launch booted im.eamon.replog -ResetRepLog YES -DemoData YES'
# (onboarding shows once; tap Continue/Get Started three times, or pass
#  -ResetRepLog NO on subsequent launches to keep the seeded data)

# 4. Drive + capture (agent-device lives in Homebrew):
ssh mac 'eval "$(/opt/homebrew/bin/brew shellenv)" && agent-device screenshot /tmp/replog-<screen>.png'
# Navigation taps that do NOT type: agent-device click <x y> works.
# Anything that types (sync URL/token, notes, RPE) is already covered by
# XCUITest — do not try to type via agent-device (it does not update
# SwiftUI bindings).

# 5. Copy captures to the fleet host for comparison:
scp mac:/tmp/replog-*.png /tmp/replog-shots/
# References: "/mnt/hermes-shared/RepCount Screenshots/IMG_81*.png"

# 6. Record each comparison in docs/BUILD-REPORT.md §4 (screen, reference,
#    verdict, differences). Commit + push.
```

## Notes / pitfalls

- The app's dark palette is semantic (systemBackground/systemGray6 + teal
  accent), so it should render dark-first like the references — but verify
  per screen, do not assume.
- `-DemoData` seeds: routine "Push Day" (Competition Bench 1x1+4, Dips 3),
  sessions on today, -1d, -2d with 3–4 sets each (RPE 7–9, one note),
  bodyweight 101–102 kg. Enough to populate Log, detail, statistics,
  routines; not enough for PR tables (fine — capture the empty state too).
- The RPE chips and set-cell formatting were fixed this pass ("8" not
  "8.0"); the XCUITest asserts it, but the visual pass should confirm the
  sheet looks right against the references.
- If a screen genuinely cannot be captured (e.g. Live Activity/Dynamic
  Island on the simulator — it renders on the lock screen, capture via
  `xcrun simctl io` after `xcrun simctl spawn booted ...` or just note it
  as unverified-device), say so in the report. Do not claim it works.
- The widget extension (RepLogWidget) exists and compiles; the Live
  Activity is started when a workout begins and ended on finish. Visual
  verification of the Dynamic Island is a device/lock-screen task — mark
  unverified if not done.
