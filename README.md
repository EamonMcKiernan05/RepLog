# RepLog

A native SwiftUI iOS workout tracker. Everything is stored on-device in
SwiftData, with zero third-party Swift dependencies. History leaves the phone
as a CSV you choose to export — nothing syncs anywhere.

Shipped and in daily owner use. The tree is at `1.1.12` (build 15); the last
build published for testing is `1.1.11` (build 14). `docs/BUILD-REPORT.md`
carries the gate numbers and the publish hashes for each build.

## What it does

- **Log** — history grouped by month, session rows with date badge, routine
  name, exercise summary and duration. A row opens the workout as the full
  screen editor; swipe to delete.
- **Active workout** — opens as a full-screen cover with its own header, so
  the tab bar cannot be reached mid-session. Session card (start/end,
  bodyweight, notes), one card per exercise, set rows with weight · reps ·
  **RPE** · notes, placeholders from your last performance. The workout "…"
  menu holds Add Exercise, Workout Notes, **Export CSV** (this session only,
  through the share sheet) and Delete Workout.
- **Exercise types** — the picker offers **Weights** and **Cardio**. Older
  exercises stored as bodyweight or note-per-set types still render exactly as
  they did; they are simply not offered for a new exercise (converting them
  would change the volume maths on old sessions).
- **Routines** — create, edit, duplicate, reorder; warm-up / working sets and
  a note per exercise; "Start this Workout". **Routine import** takes a CSV,
  shows what it will do, then imports.
- **Exercise library** — 12 categories, 154 seeded exercises, add and edit,
  single arm/leg handling.
- **Statistics** — overall metrics, per-exercise history with volume and e1RM
  (Brzycki) charts, personal records per rep range, seasonal bests, session
  records.
- **Rest timer** — a collapsible bar pinned to the bottom of an open session,
  with a notification scheduled when it starts.
- **kg/lb** global unit with a per-exercise override inside a workout.
- **CSV out** — the whole history from Profile, the range on the chart you are
  looking at (1M / 3M / 6M / 1Y / All), or a single session from the workout
  menu. **CSV in** rebuilds a fresh phone from a file.
- **Apple Health** — reads bodyweight and writes finished workouts and
  bodyweight when the setting is on.

## The CSV format

One header line, one row per set, LF, UTF-8, no BOM. The column set and the
order are a frozen contract (`docs/PLAN.md` §4.4), implemented in
`Engine/CSVCodec.swift`.

- weight always in kg
- RPE a plain number, one decimal at most, blank when not recorded
- text fields quoted when needed; leading `= + - @` escaped with a space so a
  spreadsheet cannot execute a note

The golden fixture that guards those bytes, and the tests around it, are **not
in this repo** — see Tests below.

## Layout

```
App/            entry point, router, root tab view
Models/         SwiftData @Model types + the frozen enums
Store/          DataStore (container + seeding), Settings, routine import
Engine/         Metrics, Targets, CSVCodec, Importer (pure, no UI)
Features/       Log / Workout / Routines / Exercises / Statistics /
                Profile / Timer / Integrations
DesignSystem/   Palette, SwipeToDelete
Resources/      SeedExercises.json, SeedCategories.json
Widget/         Live Activity widget extension
scripts/        the test gates and the CSV validator
docs/           PLAN.md (the historical spec), BUILD-REPORT.md, ROUND-2.md,
                visual captures
```

`Tests/` is deliberately absent — it is gitignored.

## Building (on the Mac)

```bash
cd ~/Documents/RepLog
xcodegen generate
xcodebuild -scheme RepLog -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

The whole gate — regenerate, build, UI suite — runs from any host that can
`ssh mac`:

```bash
scripts/mac-tests.sh            # or: scripts/mac-tests.sh <ssh-host>
```

That needs a Mac. The app is SwiftUI + SwiftData against the iOS 26 SDK; a
Linux host has neither Xcode nor a simulator, so it cannot build or test this.

## Tests

**Nothing here is committed as a test.** The owner's rule is end-to-end only,
and the test files live outside version control (2026-10-27): `Tests/` is in
`.gitignore` and the suite is kept on the Mac build host.

- **The gate** — `scripts/mac-tests.sh`: pull, `xcodegen generate`, the app
  build, then the XCUITest suite. No unit suite.
- **The local scripts** — `scripts/verify.sh` (CSV schema over the golden
  fixture) and `scripts/logic-tests.sh` (Foundation-only logic, plain `swift`)
  read `Tests/Fixtures` and `Tests/Unit`. They therefore only run on a machine
  that keeps those files; in a clean clone both stop on the missing path, by
  design.
- **Any export** — `python3 scripts/validate_sessions.py <file.csv>` checks a
  file against the frozen schema. Validity only: it never judges the training.

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
   --bundle im.eamon.replog --version 1.1.12 --base https://replog.eamonmckiernan.im`.
3. On the iPhone, open `https://replog.eamonmckiernan.im/replog/` **in Safari**
   and tap Install RepLog.

Ad-hoc means only devices listed in the provisioning profile can install it.

## Notes

- Removed on 2026-10-23 (round 2): supersets, the six extra exercise types, the
  calories cell, and the self-hosted sync service in full. Nothing stored was
  dropped — the phone's history survives, and the CSV keeps its frozen
  eighteen-column shape.
- `ExerciseEntry.supersetId`, `Session.syncStateRaw`, `SetEntry.kcal` and the
  retired `ExerciseType` cases stay on the models as inert fields. Dropping a
  stored property would break an existing store and take the history with it.
- The export file is not encrypted. It is a CSV you hand to someone; treat it
  like one.
- No accounts, no paywall. The analytics toggle exists for parity and is wired
  to nothing.
