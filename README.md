# RepLog

A native SwiftUI iOS workout tracker. Everything is stored on-device in
SwiftData, with zero third-party Swift dependencies. History leaves the phone
as a CSV you choose to export — nothing syncs anywhere.

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

