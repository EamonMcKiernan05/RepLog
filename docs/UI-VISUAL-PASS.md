# RepLog — UI / visual pass: how it was run and where the evidence is

This file records the mechanics of the dark-mode visual pass and the
accessibility checks, so the numbers in `docs/BUILD-REPORT.md` §4/§5 can be
re-checked without re-running anything. The full screen-by-screen comparison
and the 1:1 reference mapping live in `docs/BUILD-REPORT.md`.

## What was captured

Dark mode, iPhone 17 Pro simulator, app built from this repo with the
`-DemoData` launch hook (synthetic history only — routine, three sessions
with sets/RPE/notes, bodyweight; never real training data).

Final committed set: `docs/visual/` — one file per screen, plus
`docs/visual/dynamic-type/` for the Dynamic Type captures.

| File | Screen |
|---|---|
| 01-onboarding-units.png | Onboarding page 1 (kg/lb) |
| 02-onboarding-privacy.png | Onboarding page 2 (data stays on the phone) |
| 03-onboarding-sync.png | Onboarding page 3 (optional sync) |
| 04-log.png | Log tab, populated |
| 05-start-workout-sheet.png | Start Workout sheet |
| 06-repeat-workout-sheet.png | Repeat Workout sheet |
| 07-active-workout.png | Active workout, routine course loaded |
| 08-select-exercise.png | Select Exercise sheet (categories) |
| 09-select-exercise-category.png | Select Exercise, category drill-in |
| 10-rpe-sheet.png | RPE input sheet (chips 6/7/7.5/8/8.5/9) |
| 11-active-workout-populated.png | Active workout with RPE + a set note |
| 12-rest-timer.png | Rest timer sheet |
| 13-session-detail.png | Completed-session detail |
| 14-routines-list.png | Routines list |
| 15-routine-detail.png | Routine detail |
| 16-routine-exercise-editor.png | Routine exercise editor |
| 17-statistics-hub.png | Statistics hub |
| 18-chart-screen.png | Per-exercise charts (Volume + e1RM) |
| 18b-overall-volume-chart.png | Overall-metric chart screen |
| 19-personal-records.png | Personal Records sheet |
| 20-profile.png | Profile |
| 21-settings.png | Settings (top) |
| 21b-settings-scrolled.png | Settings (timer/privacy) |
| 24-edit-categories.png | Edit Categories |
| 25-export-csv-sheet.png | Export CSV sheet |
| 22-exercise-library.png | Edit Exercises (library) |
| 23-exercise-editor.png | Edit Exercise sheet |
| 26-exercise-history.png | Per-exercise history |
| 28-active-workout-foreground.png | Live Activity attempt: workout running |
| 29-home-dynamic-island.png | Live Activity attempt: app sent home |

## How it was captured

1. `xcrun simctl ui <udid> appearance dark` — the working switch. (`defaults
   write` does nothing to a booted simulator and produced the earlier
   mislabelled "dark" set that was actually light.)
2. A fresh install (`xcrun simctl uninstall`) so `-DemoData` seeds once, then
   a scripted XCUITest tour (`Tests/UI/RepLogVisualTourTests.swift`) drives
   every screen and attaches a full-resolution `XCUIScreen` screenshot per
   screen. XCUITest is used for the tour because the populated screens need
   real typing (a set's weight/reps/RPE and a note) and agent-device
   keystrokes do not update SwiftUI bindings.
3. Attachments are exported with
   `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`
   and renamed by their attachment name (the export appends `_0_<uuid>.png`).
4. The screens the tour could not land (statistics drill-ins, scrolled
   settings, the export sheet, exercise history, the Live Activity attempt)
   were captured with `xcrun simctl io booted screenshot` while navigating
   with agent-device taps — the same images the tour produces, from the same
   framebuffer.
5. Every image was inspected against the references with vision, one screen
   at a time; the comparison lines are in `docs/BUILD-REPORT.md` §4.

### Why not agent-device for everything

`agent-device type` / `fill` inject keystrokes at the OS level and SwiftUI
`@State` bindings do not receive them, so anything that types (the RPE sheet,
set notes, the sync fields) has to be driven by XCUITest. Navigation taps work
fine in both.

### Traps this pass hit (now encoded in the tour)

- A row tap in a `ScrollView` with `.buttonStyle(.plain)` only lands on the
  label's CONTENT shape — taps in the gaps (under a `Spacer`, between text
  lines) do nothing. Rows now carry `.contentShape(Rectangle())`.
- An element below the fold has a frame outside the screen, so a coordinate
  tap lands off-screen and silently misses. The tour scrolls a target into
  view before tapping it.
- Tapping a `staticText` inside a `List` row does not activate the row's
  link; tap the row cell/button instead.
- A `.navigationDestination(for:)` share with an item-based destination on the
  same view, or declared inside a pushed view, silently fails to push. The Log
  keeps its two destinations on different views; the statistics list uses
  view-based links.
- An iOS 26 toolbar clips a `.bordered` + `.capsule` text button to a circle
  showing one letter; an explicit capsule label with `.fixedSize()` renders
  correctly (this is what the Edit buttons use now).
- iOS's "Save Password?" AutoFill prompt appears after typing into the sync
  token field and swallows every later tap. The offline drill configures sync
  through launch arguments (`-SyncURL` / `-SyncToken`) instead, and the sync
  form test dismisses the prompt.
