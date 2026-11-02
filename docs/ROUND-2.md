# Round 2 — the owner's list (2026-10-23)

Owner's words, split by what they ask for.

**Done on branch `round-2` (2026-10-23, uncompiled — the Mac is unreachable):**
supersets, the two exercise types and calories are out; sync is gone with its
drill, its tests and its settings; one-session CSV export is in the workout
menu; the routine-import reader and its 13 tests are in, and
`scripts/logic-tests.sh` runs them on this machine (green). **Next:** the
routine import UI, then the note, session-presentation and timer work, all of
which need the Mac to look at.

## Rule for this round: nothing that already stores data may lose a column

The app on the phone holds months of real training. `ExerciseEntry.supersetId`, `Session.syncStateRaw`
and the bodyweight/kcal cells are stored properties in a SwiftData model; dropping one breaks the
existing store, and the only "fix" is a fresh store, which deletes his history. So every removal below
is a **removal of the UI, the writers and the readers — never of the stored property**. Removed things
stay in the file as inert fields, hidden. New fields must be optional so the store migrates by itself.

That rule is why the removals are mechanical rather than a rewrite, and it is not negotiable.

## Order

1. **Removals** (supersets, extra exercise types, calories, sync) — everything after this is smaller
   and simpler because the dead paths are gone.
2. **Notes** — multi-line exercise and set notes, rows that grow, return inserts a newline.
3. **Session presentation** — the session opens over the app with its own header, app chrome hidden.
4. **Timer bar** — the collapsible bar replaces the full-screen timer, plus a local notification when
   it fires with the app closed.
5. **Per-session CSV export** — a menu item between Workout Notes and Delete Workout.
6. **Routine import** — CSV, schema below, pending the owner's nod.

Programs are drafted at the bottom and are **not** built this round.

---

## 1. Removals

### 1a. Supersets

- `ExerciseEntry.supersetId` stays (inert, always nil for new entries).
- `SelectExerciseSheet`: drop the `Regular | Superset` picker, `allowSuperset`, `onSuperset`,
  `Mode.superset`, `addSuperset()`.
- `ActiveWorkoutView`: drop `addSuperset`, the `allowSuperset:`/`onSuperset:` arguments.
- `StartWorkoutSheet`: drops the copied `supersetId` when duplicating an exercise.
- `CSVCodec`: unchanged. `superset_id` and `kcal` stay in the header and are written empty, so the export
  keeps its frozen v1 shape, old files still import, and the golden-file test does not have to move.
- Proof: add two exercises in a row in a UI test; no Superset control exists.

### 1b. Exercise types

The picker offers exactly two: **Weights** (weight, reps) and **Cardio** (time, distance).

- `ExerciseType` keeps all its cases so existing rows still decode (`ExerciseType(rawValue:) ?? .weightReps`
  already falls back safely — do not rely on that, keep the cases).
- Add `ExerciseType.selectable: [ExerciseType] = [.weightReps, .cardio]`; every creation/edit picker
  reads it instead of `CaseIterable`.
- `displayName`: `.weightReps` → `Weights`, `.cardio` → `Cardio — Time, Distance`.
- Calories: `hasCardioExtras` stops being read by `SetRowView`/`InlineCells`; the kcal input and column
  disappear. `SetEntry.kcal` keeps its stored values (invisible), and stays out of the export.
- An exercise already stored as `bw_reps` etc. keeps rendering exactly as it does today — it is no
  longer offered for new exercises, and is converted to Weights only if the owner edits it.
- Proof: the picker's rows in a UI test are exactly the two names.

### 1c. Sync

"export CSV only now" — the lift-sync upload goes, the export stays.

- Delete `Sync/SyncEngine.swift`, `Sync/Outbox.swift`, `Sync/LiftSyncClient.swift`,
  `Tests/Unit/OutboxTests.swift`, and the `SyncEngine` environment wiring.
- `Session.syncStateRaw` stays (inert). The `SyncState` enum itself went on 2026-10-27
  (`cleanup-retired-sync`) — nothing read it, and the stored raw string is what keeps old stores
  decoding.
- `ProfileViews`: the sync URL/token/status section goes.
- `LogTabView` / `ActiveWorkoutView`: the status control and `sessionEdited` calls go.
- `Sync/` also holds nothing else, so the folder goes. `service/` (the Python server) was left in the
  repo untouched and unused this round — **deleted 2026-10-27** in `cleanup-retired-sync`, on the
  owner's instruction once the app had been in daily use without it.
- Every UI test that drives sync is removed with it; the count in the build report is corrected to the
  new total, not left stale.
- Proof: `grep -r SyncEngine` is empty outside the shim; the app builds and the remaining suite is green.

## 2. Notes — multi-line, growing rows

- `InlineTextField` / `InlineCell` grow a `multiline: Bool` mode: `TextField("", text:, axis: .vertical)`
  with `lineLimit(2...)` and `.submitLabel(.return)`; the return key inserts a newline instead of
  committing. Commit happens on focus loss (and on the keyboard bar's ✓).
- Exercise header note and set-row note both use it; both start at **2 lines** of height.
- The card / row heights are intrinsic (`fixedSize(horizontal: false, vertical: true)`), so a new line
  pushes the card taller; no manual measuring.
- `focusOrder` and the scroll-into-view step keep working — the boxes keep their `CellFocus` addresses.
- Proof: one UI test types `a\nb` into an exercise note, asserts the field holds two lines (the value
  contains a newline and the field's height grew), and that the keyboard is still up.

## 3. Session presentation

- The session opens as a full-screen cover over the tab bar, not a push: `fullScreenCover` from the Log
  and from the start list, so the tab bar cannot be reached mid-workout.
- `.toolbar(.hidden, for: .navigationBar)`; the screen draws its own header row — check, date, and the
  `⋯` + timer capsule — matching the reference screenshot.
- The way out is the check (finish) or the menu's Delete; a finished record gets a plain "Back" header.
- Proof: a UI test starts a workout, asserts the tab bar is gone, and that the header's controls exist.

## 4. Timer bar

Replaces the `showTimer` toolbar button and the current `safeAreaInset` sheet-style timer.

- A permanent bar pinned to the bottom of an open session: play/pause, the remaining time in mono,
  and a control that collapses/expands it. Expanded, it shows the ring, `-15s` / `+15s`, and the preset
  chips (the reference screenshots).
- State lives in the existing `RestTimerController` (start/pause/+15/-15/presets already exist there);
  this is a presentation change plus a collapse `@State`.
- Notification: when a countdown starts, schedule a `UNUserNotificationCenter` local notification at the
  fire date; cancel it on pause/reset/±15. Permission is requested the first time a timer starts (not at
  launch). When the app is foregrounded the in-app finish still plays; the notification is what carries
  when the app is closed.
- Live Activity (already wired) stays as the lock-screen surface.
- Proof: UI test that starts a 30s timer, collapses the bar, sees the countdown still running, expands
  it again; notification scheduling is proven by reading pending requests in a test hook
  (`UNUserNotificationCenter.current().pendingNotificationRequests`), not by waiting 30 minutes.

## 5. Per-session CSV export

- New menu item in the workout menu, between Workout Notes and Delete Workout:
  **Export CSV**, `square.and.arrow.up`.
- Encodes just this session with `CSVCodec` (already the canonical writer) into a temp `.csv`, shares it
  with the system share sheet, cleans up the file afterwards.
- Proof: UI test taps it, the share sheet appears; the file's bytes are asserted through the same codec
  in a unit-level check (pure function, no UI needed).

## 6. Routine import (CSV)

Header-driven, order-independent, unknown columns ignored. One row per exercise.

```
routine,position,exercise,type,category,warmup_sets,working_sets,notes
SBD,1,Low Bar Squat,weights,Legs,1,4,heavy single then 3x4
SBD,2,Bench Press,weights,Chest,0,4,paused
```

- `routine` (required) — routine name. An existing routine with that name is **replaced** (its exercise
  list is rebuilt); the import preview says so before writing.
- `position` — exercise order, 1-based; rows without it keep file order.
- `exercise` (required) — matched to the library case-insensitively; created if missing.
- `type` — `weights` or `cardio`, only used when the exercise is created. Default `weights`.
- `category` — only used when the exercise is created; created if missing.
- `warmup_sets`, `working_sets` — integers, default 0 and 4.
- `notes` — exercise note, free text, quoting as in `CSVCodec` (a leading `= + - @` escaped with a space).
- No reps/RPE/weight columns: the routine model holds set counts only. Prescribed reps, weights and RPE
  arrive with Programs (below); the same file grows columns then.
- Rejected rows (bad number, missing routine/exercise) fail the whole import with a line-numbered error
  list rather than half-importing.
- Proof: pure-function tests over good, quoted, CRLF, unknown-column and broken files; one UI test that
  imports a file through the picker and sees the routine in the list.

## 7. Programs — draft only, do not build

Owner's shape, recorded so the model work is not guessed later:

- A program is a list of sessions; each session is a list of exercises; each exercise is a list of
  prescribed sets (`target_weight`, `target_reps`, `target_rpe`, `pct_of_training_max`).
- Starting a workout picks a session from the program. Set rows then grey-fill **from the prescription**
  instead of last time's numbers — but only for squat, bench, deadlift and their named variations.
  Accessories keep the existing last-time hints.
- Training maxes are entered per lift and per variation (sumo / paused / tempo / box / long-pause /
  touch-and-go …). A variation without its own max falls back to the parent lift's max, and then to the
  last entered numbers.
- Import is CSV again: one file for the program, one for the maxes.
- The programme builder is a separate screen: session list, exercise list, per-set targets.

## Open decisions

1. **The exercise-type change** — confirm legacy bodyweight types stay working-but-hidden rather than
   being converted. Converting changes volume maths on old sessions.
2. **`service/`** — **resolved 2026-10-27:** deleted, with the drill supervisor and the one-off
   `repcount_import.py` migration, on branch `cleanup-retired-sync`.
3. **Routine CSV** — the shape above, or does the routine need prescribed reps before programs land?
