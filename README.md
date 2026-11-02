# RepLog

A native SwiftUI iOS workout tracker. Everything is stored on-device in
SwiftData, with zero third-party Swift dependencies. History leaves the phone
as a CSV you choose to export — nothing syncs anywhere.

Shipped and in daily owner use. Current version `1.1.10` (build 13).

## What it does

- **Log** — history grouped by month, session rows with date badge, routine
  name, exercise summary and duration. A row opens the workout as the full
  screen editor; swipe to delete.
- **Active workout** — opens as a full-screen cover with its own header, so
  the tab bar cannot be reached mid-session. Session card (start/end,
  bodyweight, notes), one card per exercise, set rows with weight · reps ·
  **RPE** · notes, placeholders from your last performance.
- **Exercise types** — the picker offers **Weights** and **Cardio**. Older
  exercises stored as bodyweight or note-per-set types still render exactly as
  they did; they are simply not offered for a new exercise (converting them
  would change the volume maths on old sessions).
- **Routines** — create, edit, duplicate, reorder; warm-up / working sets and
  a note per exercise; "Start this Workout". **Routine import** takes a CSV,
  shows what it will do, then imports.
- **Exercise library** — 12 categories, 150+ seeded exercises, add and edit,
  single arm/leg handling.
- **Statistics** — overall metrics, per-exercise history with volume and e1RM
  (Brzycki) charts, personal records per rep range, seasonal bests, session
  records.
- **Rest timer** — a collapsible bar pinned to the bottom of an open session,
  with a notification scheduled when it starts.
- **kg/lb** global unit with a per-exercise override inside a workout.
- **CSV in and out** — export the whole history from Profile, or only the
  range on the chart you are looking at (1M / 3M / 6M / 1Y / All). Import
  rebuilds a fresh phone from a file.

## The CSV format

One header line, one row per set, LF, UTF-8, no BOM. The column set and the
order are a frozen contract (`docs/PLAN.md` §4.4) — `Tests/Fixtures/golden_session.csv`
pins the exact bytes and the unit tests fail if the codec drifts from it.

- weight always in kg
- RPE a plain number, one decimal at most, blank when not recorded
- text fields quoted when needed; leading `= + - @` escaped with a space so a
  spreadsheet cannot execute a note

## Layout

```
App/            entry point, router, root tab view
Models/         SwiftData @Model types + the frozen enums
Store/          DataStore (container + seeding), Settings, routine import
Engine/         Metrics, Targets, CSVCodec, Importer (pure, unit-tested)
Features/       Log / Workout / Routines / Exercises / Statistics /
                Profile / Timer / Integrations
DesignSystem/   Palette, SwipeToDelete
Resources/      SeedExercises.json, SeedCategories.json
Widget/         Live Activity widget extension
Tests/          Unit (swift-testing) + UI (XCUITest) + Fixtures
scripts/        the test gates and the CSV validator
docs/           PLAN.md (the spec), BUILD-REPORT.md, ROUND-2.md, visual captures
```

## Building (on the Mac)

```bash
cd ~/Documents/RepLog
xcodegen generate
xcodebuild -scheme RepLog -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

The whole gate (build + unit + UI tests) runs from any host that can
`ssh mac`:

```bash
scripts/mac-tests.sh
```

## Tests

- **Unit (swift-testing), 40 tests:** CSV codec against the golden file,
  importer, routine CSV, metrics (volume per type, bodyweight multiplier,
  single-arm doubling, Brzycki e1RM, PRs), targets.
- **UI (XCUITest), 18 tests:** every text-entry flow plus the flows that
  cannot be checked without a running app — RPE entry and chips, exercise
  search, set notes, the keyboard arrows and the focused box clearing the
  software keys, finish confirmation, swipe-delete, routine notes, and the
  range-limited statistics export.
- **Fast logic gate, no Mac:** `scripts/logic-tests.sh` compiles the
  Foundation-only files and runs their tests on any machine with a Swift
  toolchain. Seconds, not the suite.
- **CSV validity, no Mac:** `scripts/verify.sh` checks the golden fixture
  against the frozen §4.4 schema with `scripts/validate_sessions.py`. Point
  that script at any exported file to check a real export.

## Installing on a device (over the air)

Ad-hoc builds are published to the fleet's app-downloads host, so a phone can
install without Xcode, a cable or Bonjour:

1. On the Mac, archive and export an ad-hoc IPA (`xcodebuild -scheme RepLog
   -configuration Release -destination "generic/platform=iOS" -archivePath
   /tmp/RepLog.xcarchive archive`, then `-exportArchive` with `method: ad-hoc`).
   Signing needs the Mac's **GUI session** (`launchctl asuser`) — a plain SSH
   session cannot reach the signing keychain.
2. Copy the IPA to the host and publish it with
   `/srv/downloads/publish.sh --slug replog --ipa /tmp/RepLog.ipa --name RepLog
   --bundle im.eamon.replog --version 1.1.10 --base https://replog.eamonmckiernan.im`.
3. On the iPhone, open `https://replog.eamonmckiernan.im/replog/` **in Safari**
   and tap Install RepLog.

Ad-hoc means only devices listed in the provisioning profile can install it.

## Notes

- Removed on 2026-10-23 (round 2): supersets, the extra exercise types, the
  calories cell, and the self-hosted sync service in full. Nothing stored was
  dropped — the phone's history survives.
- The export file is not encrypted. It is a CSV you hand to someone; treat it
  like one.
- No accounts, no paywall. The analytics toggle exists for parity and is wired
  to nothing.
