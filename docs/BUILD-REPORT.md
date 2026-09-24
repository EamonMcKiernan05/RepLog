# RepLog — Build Report

Date: 2026-09-23 (pass ran 22–23 Sep 2026). Host: WSL fleet host (edit/commit)
+ `ssh mac` (build/test — macOS 26.6.2, Xcode 26.5, iPhone 17 Pro simulator,
iOS 26.5).

## Testing policy (owner, 2026-09-24)

**End-to-end only.** New behaviour is proven by UI tests that drive the app in a
simulator and assert what the owner can see — he tests on a phone, and that is
the thing that has to work. Unit tests are not written for new work: they prove
internals he never touches. The five pre-existing unit files (CSV codec,
importer, metrics, outbox, targets) stay where they are — they cover the sync
engine and the maths, which a UI test cannot reach — but nothing new is added to
them. The seven unit tests written for the routine pre-fill rule on 2026-09-24
were removed the same day under this rule.

Gate: `scripts/mac-tests.sh` — build, the unit suite, then the UI suite
(including the in-simulator offline drill) in one run.

## Build status

**Status: the whole Mac gate is green at commit `ff1cb43`** — `** BUILD
SUCCEEDED **`, 36/36 unit tests, **12/12 UI tests** including the in-simulator
offline drill, in one `scripts/mac-tests.sh` run (§1.1, §0.1 and §0.3). The dark-mode visual
pass covers every screen against the 17 reference screenshots (§4), and the
Dynamic Type / accessibility checks are in §5. What cannot be shown in a
simulator is listed as device-only and is never claimed to work (§6).

The commits after `1941ab8` were documentation only until the inline-entry
change recorded in §0 below, which *is* code; that section carries its own gate
re-run.

The previous version of this report said 35/35 units and "the Mac lost power
mid-run"; both were stale and are gone.

---

## 0. Inline entry — no text-entry sheets (2026-09-23, after the gate above)

Owner feedback on the screens that mirror the reference: the cells that opened
a sheet with a text box now take the value **straight in the box**.

**What is typed in place now**

- Set rows: weight, reps, time, distance, kcal, **RPE** and the set note.
- The exercise note (the notes icon now puts the caret in the inline field
  instead of opening a sheet), the workout note, and the routine name + notes.
- The routine exercise editor's warm-up / working set counts (typed fields; they
  were steppers).

**Rules kept**

- Values commit on submit or focus loss, never per keystroke — a half-typed
  `1.` must not be parsed and written back, or the field rewrites itself and
  eats the decimal point.
- RPE keeps its half-step snapping and 1–10 clamp, now in the cell's commit.
- The RPE quick chips (6 · 7 · 7.5 · 8 · 8.5 · 9) moved inline: they appear
  under the row whose RPE box is being edited. A chip tap discards a half-typed
  draft rather than overwriting it.
- A cleared NUMBER box means "no value"; a cleared TEXT box means empty.
  Unparseable input is refused and the box snaps back to the stored value.
- The routine name reverts if you clear it (an empty name would blank the list
  row and the navigation title).
- One keyboard **Done** per screen clears whatever cell is focused — the number
  pads have no return key.
- Still a sheet, deliberately: **creating** a routine (`RoutineEditorSheet` asks
  for the name before the routine exists). No other text-entry sheet remains in
  these flows.

**Deleted:** `RPEInputSheet`, `NumberInputSheet`, `SetNoteSheet`,
`ExerciseNotesSheet`, `SessionNotesSheet`, `RoutineNotesSheet`
(`Features/Workout/InputSheets.swift` is gone); replaced by `InlineCell` /
`InlineTextField` (`Features/Workout/InlineCells.swift`).

**Gate re-run after the change** (`bash scripts/mac-tests.sh`, one run):

```
** BUILD SUCCEEDED **
✔ Test run with 36 tests in 5 suites passed after 0.650 seconds.
Test Case '-[RepLogUITests.RepLogUITests testExerciseSearchFilters]' passed (23.502 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOfflineDrill]' passed (93.929 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEChipsDisplayWholeValues]' passed (31.939 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEEntryTypes85AndReadsBack]' passed (30.690 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSessionRowOpensDetail]' passed (40.137 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSetNoteEntry]' passed (30.646 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSyncURLAndTokenFields]' passed (34.357 seconds).
	 Executed 7 tests, with 0 failures (0 unexpected) in 285.200 (285.215) seconds
** TEST SUCCEEDED **
All Mac tests passed.
```

The UI tests were rewritten onto the inline boxes (type → keyboard Done → read
the value back); they no longer touch a sheet.

**Two defects the work surfaced, both fixed**

1. With a custom `prompt:` style, iOS rendered the text *being typed* in the
   prompt's grey while the keyboard was up, so a value you were entering looked
   like a placeholder until it was committed (seen in the capture
   `10b-set-cell-typed.png`). The empty state is now a sibling `Text`, the field
   always renders bold/primary, and an empty box keeps a 44 pt minimum so it
   stays focusable.
2. `-ResetRepLog YES` wiped UserDefaults but **not** the SwiftData store. The
   outbox is rebuilt from each session's `syncState`, so a session left queued
   by an earlier run re-uploaded as soon as a sync URL was configured: after a
   visual-tour run the offline drill uploaded 8 rows of the tour's session on
   top of its own and read **9** where it asserts **1**. The hook now deletes
   the store as well. It passed before only while the store happened to hold no
   queued sessions.

**Evidence:** `docs/visual/10-rpe-inline.png` (RPE box focused, chips inline
under the row), `10b-set-cell-typed.png` (140 typed into an empty weight box,
caret in the box, keyboard up), `11-active-workout-populated.png` (typed note +
a typed value), `15-routine-detail.png`, `16-routine-exercise-editor.png`.
The `docs/visual/dynamic-type/` set is from the earlier pass and predates this
change — those four screens are the ones whose layout moved.

---

## 0.1 The six owner-reported fixes — gate re-run and re-publish (2026-09-24)

The six fixes landed on 2026-09-23 (`4e228ab` → `a83f355`, 22:52–23:36) but
two things were left undone, and the owner found both on the phone:

1. **The published build was older than the fixes.** The IPA on the install
   host was archived from `b4b1732` at 20:50 BST — three hours before them — so
   installing 1.0.0 gave the pre-fix app. Nothing was re-archived or
   re-published after the fixes.
2. **The UI suite was red at that commit, not 7/7.** Five of the ten UI tests
   failed (`testEditModeRevealsRowDelete`, `testFinishAsksBeforeEnding`,
   `testOfflineDrill`, `testOpenWorkoutReopensEditorAfterLeavingIt`,
   `testSessionRowOpensDetail`) — the finish-confirmation change had made the
   tests' dialog queries unusable on iOS 26 (below). The earlier "7/7" figure
   was true when the suite had seven tests; it was never re-established after
   the suite grew to ten.

Both are fixed at `b07e0c5`, and 1.0.1 is published (§0.1.5).

### 0.1.1 Gate — one `bash scripts/mac-tests.sh` run at `b07e0c5`

```
** BUILD SUCCEEDED **
✔ Test run with 36 tests in 5 suites passed after 0.221 seconds.
Test Case '-[RepLogUITests.RepLogUITests testEditModeRevealsRowDelete]' passed (52.776 seconds).
Test Case '-[RepLogUITests.RepLogUITests testExerciseSearchFilters]' passed (23.112 seconds).
Test Case '-[RepLogUITests.RepLogUITests testFinishAsksBeforeEnding]' passed (37.209 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOfflineDrill]' passed (99.940 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOpenWorkoutReopensEditorAfterLeavingIt]' passed (46.898 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEChipsDisplayWholeValues]' passed (31.682 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEEntryTypes85AndReadsBack]' passed (30.482 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSessionRowOpensDetail]' passed (44.006 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSetNoteEntry]' passed (30.474 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSyncURLAndTokenFields]' passed (35.443 seconds).
	 Executed 10 tests, with 0 failures (0 unexpected) in 432.021 (432.037) seconds
** TEST SUCCEEDED **
All Mac tests passed.
```

The suite is **ten** UI tests, not seven (`scripts/mac-tests.sh`'s header and
the status block above now say 10/10).

### 0.1.2 The six items, as the code stands

| # | The owner's item | Where it lives now | Test |
|---|---|---|---|
| 1 | Delete a workout, local only; the uploaded copy stays | `Sync/SyncEngine.swift:100-106` (`sessionDeleted` drops the outbox entry and never calls the service), `Features/Log/SessionDetailView.swift:97-106` (`delete()` then `dismiss()`), `LogTabView.swift:61-70` (per-row trash in Edit mode) and `:180-188` (confirm + "It stays in the sync database…"). | `testEditModeRevealsRowDelete`; the drill asserts the CSV row count stays 1 after a phone delete and that no delete event is sent |
| 2 | Never strand an open workout | `LogTabView.swift:112-124` (a session with no end time opens the EDITOR), `SessionRowView.swift:31-32` + `Models.swift:122` ("In progress"), `ActiveWorkoutView.swift:147` (End Time row always renders) | `testOpenWorkoutReopensEditorAfterLeavingIt` |
| 3 | The finish checkmark must ask first | `ActiveWorkoutView.swift:59-70` (sets `confirmFinish`), `:124-129` (the dialog, with `finish-confirm` / `finish-cancel`) | `testFinishAsksBeforeEnding` |
| 4 | Sync is a manual action at the top of the Log | `SyncEngine.swift:80-82` (the `NWPathMonitor` auto-upload is gone), `:110` (`syncNow`), `LogTabView.swift:192-232` (state text: "N to sync" / spinner / "Up to date · <relative>" / auth failure) | the drill: zero rows upload until the sync button is tapped, then exactly one upsert |
| 5 | Centre the narrow set cells under their column titles | `Features/Workout/InlineCells.swift:33, 62, 83, 88-94` — narrow cells centre, only the wide Notes column is leading | capture `11-active-workout-populated.png` (100 / 5 / 8 sit under Kg / Reps / RPE) |
| 6 | Drop the dead "Scheme" section from the routine-exercise editor | `Features/Routines/RoutinesViews.swift:358` — the read-only section is gone; the `scheme` model field and the set prefill (`StartWorkoutSheet.swift:70-78`) stay | capture `16-routine-exercise-editor.png` |

Schemes are no longer editable anywhere in the app (`plannedScheme` is still
shown read-only on the exercise card, and the routine's scheme lines still
prefill a started workout). No data was migrated.

### 0.1.3 Two iOS 26 traps the re-run exposed (in the tests, not the app)

Measured on the iPhone 17 Pro simulator, 2026-09-24:

- **A `confirmationDialog` button is nested.** `Button, identifier:
  'finish-confirm'` sits INSIDE a second element with the same identifier, both
  with the same frame, so `app.buttons["finish-confirm"]` raises *"Multiple
  matching elements found"* on any attribute access (including `.exists` inside
  a polling helper). Every dialog tap now goes through `.firstMatch`.
  `app.buttons["Finish"]` (by label) had the same problem.
- **The dialog has no reachable Cancel.** `app.descendants(matching: .any)`
  matching a "Cancel" label returns **zero** elements, and the dialog is a
  POPOVER pinned near the top of the screen (the button's frame starts at
  y=132pt of 874) with no dimmed backdrop. Cancelling is therefore done by
  tapping well below the card (`dx 0.5, dy 0.85`); a tap at `dy 0.12` lands
  inside the card and does nothing, which is what silently broke two tests and
  two captures.

The tour and the tests both carry these notes now, so the next pass does not
re-learn them.

### 0.1.4 Captures refreshed

`docs/visual/04-log.png` (sync control top-right), `11-active-workout-populated.png`
(centred cells), and three new files: `12b-finish-confirm.png` (the dialog),
`12c-log-in-progress.png` (the Log with the open workout marked "In progress"),
`12d-open-workout-reopened.png` (tapping it reopens the editor), plus
`16-routine-exercise-editor.png` (no Scheme section). `docs/UI-VISUAL-PASS.md`
lists them and records both traps.

### 0.1.5 Published

1.0.1 (build 2) — `im.eamon.replog`, **661,378 bytes**, sha256
`e2a20a3a07de3c4ecc43bd25af04d2a56bdca418337ae9a387470ebe7e5a1630`, archived
from `b07e0c5` through the Mac's GUI session, ad-hoc profile valid to
2027-09-23 with the owner's iPhone UDID. The served file's sha256 was read back
over HTTPS and matches. Install page: <https://replog.eamonmckiernan.im/replog/>.

---

## 0.2 Owner round 2 — End Time finishes the session, no 0x4 pre-fill, the note under the name, a working exercise menu (2026-09-24)

Owner report from the phone, with a screenshot of the reference app's exercise
panel.

### 0.2.1 "click on the 'end time' row ... and it will automatically mark the session as finished"

The row was plain text with no gesture on it. It is now a button
(`ActiveWorkoutView.endTimeRow`, identifier `end-time-row`, with the chevron
that says it is tappable) which opens `EndTimePickerSheet` **at the current
time**. Done sets the end time and runs the same completion path as the
checkmark: save, stop the rest timer, queue the session for sync, end the Live
Activity, write to Health when enabled, and pop back to the Log. A picked time
earlier than the start rolls to the next day, so a workout that ran past
midnight cannot end before it began.

**Evidence:** `testEndTimeRowFinishesTheWorkout` (33.2 s — asserts the row is
tappable, the picker appears, and the session lands in the Log without the
"In progress" marker) and capture `11c-end-time-picker.png`.

### 0.2.2 "remove the autofilled 0 and 4 under weight and reps for new sessions"

**Cause:** a routine exercise's stored scheme row defaulted to `[0, 4]` —
"0 kg x 4" — and starting a workout wrote it straight into set 1, where it
looked like something the owner had entered and counted as a real set. Two
changes:

- `RoutinesViews.addExercise` no longer seeds `[[0, 4]]`; schemes are no longer
  editable in the app, so a new exercise simply has none.
- Both start paths (the "+" sheet and the routine's "Start this Workout") now
  go through **`Engine/SchemePrefill`**: a scheme row with no weight pre-fills
  nothing, so the row shows its placeholder instead of a committed zero. Set
  ROWS still come from the routine's warm-up/working counts, and a scheme row
  with a real weight still pre-fills weight and reps as before.

**Evidence:** `Tests/Unit/SchemePrefillTests.swift` — 7 tests, including "a
zero-weight scheme row pre-fills nothing", "a half-written row pre-fills
nothing", and the row-count formula. The unit suite went 36 -> 43.

### 0.2.3 "the '1x4' under 'low bar squat' title should be where the exercise note is displayed"

The line under the exercise name **is** the exercise note now: displayed and
typed in place with the same inline field ("Add Note" while empty), in the
position RepCount uses. `plannedScheme` is no longer rendered or written, and
the separate "Add Note" row is gone — one place for the note, under the name.

### 0.2.4 "the three dots on the end of the title row on exercises doesnt do anything"

**Cause:** it was a bare `Image(systemName: "ellipsis")` with no frame and no
content shape, so its hit target was the glyph itself — which is why it read as
dead — and it offered only four items. It is now a 44 pt target
(`exercise-menu`) opening the reference panel's action set:

| Action | What it does |
|---|---|
| **Move** | `MoveExercisesSheet` — drag-to-reorder the workout's exercises; written back on Done |
| **Replace** | exercise picker; the sets, notes and unit override already logged stay with the entry |
| **Delete** | confirm, then removes the exercise from the session |
| **Edit Note** | puts the caret in the note under the name |
| **History** | `ExerciseHistoryView` |
| **Charts** | `ExerciseChartsSheet` — the statistics screen *pushes* `ExerciseDetailView`, which has no title-bar button of its own, so the sheet wrapper supplies Done |
| **Personal Records** | `PRView` |
| **Weight Unit** | per-exercise kg/lb override (nil = follow the global unit); storage stays kg |

**Evidence:** `testExerciseMenuOffersTheReferenceActions` (32.2 s — opens the
menu and asserts all eight actions are present) and capture
`11b-exercise-menu.png`.

### 0.2.5 Gate at `383e39d` — one `bash scripts/mac-tests.sh` run

```
** BUILD SUCCEEDED **
✔ Test run with 43 tests in 6 suites passed after 0.287 seconds.
Test Case '-[RepLogUITests.RepLogUITests testEditModeRevealsRowDelete]' passed (52.414 seconds).
Test Case '-[RepLogUITests.RepLogUITests testEndTimeRowFinishesTheWorkout]' passed (33.175 seconds).
Test Case '-[RepLogUITests.RepLogUITests testExerciseMenuOffersTheReferenceActions]' passed (32.196 seconds).
Test Case '-[RepLogUITests.RepLogUITests testExerciseSearchFilters]' passed (22.731 seconds).
Test Case '-[RepLogUITests.RepLogUITests testFinishAsksBeforeEnding]' passed (37.539 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOfflineDrill]' passed (100.139 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOpenWorkoutReopensEditorAfterLeavingIt]' passed (47.235 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEChipsDisplayWholeValues]' passed (31.782 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEEntryTypes85AndReadsBack]' passed (30.431 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSessionRowOpensDetail]' passed (43.938 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSetNoteEntry]' passed (30.516 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSyncURLAndTokenFields]' passed (34.760 seconds).
   Executed 12 tests, with 0 failures (0 unexpected) in 496.856 (496.874) seconds
** TEST SUCCEEDED **
All Mac tests passed.
```

### 0.2.6 Published

**1.1.0 (build 3)** — `im.eamon.replog`, 686,575 bytes, sha256
`b1c6bd13e8104660e0fd703f87bd11df4714676014ab9da06faf6de0a75156cb`, archived
from `383e39d` through the Mac's GUI session (ad-hoc profile valid to
2027-09-23 with the owner's UDID). The **served** file's sha256 was read back
over HTTPS and matches, and the shipped binary contains the new copy ("Done
finishes the workout and saves it.", "Replace Exercise"). Install page:
<https://replog.eamonmckiernan.im/replog/>

---

## 0.3 Workout card legibility (owner report, 2026-09-24, against a reference screenshot)

"increase the spacing for columns and rows a bit more, and shrink the size of
the set number circle - everything feels a bit cramped / overcrowded. move the
add note, graph, and star icon at the bottom of a workout to the right of the
row like in repcount."

| What | Before | Now |
|---|---|---|
| Set number circle | 28 pt in a 40 pt slot, `.footnote` number | 23 pt in a 32 pt slot, `.caption2` number |
| Column gap | none — cells butted together at their 44 pt minimum | 14 pt between cells, same 44 pt minimum width |
| Set row height | 6 pt above/below | 11 pt, plus 4 pt between a column's label and its value |
| Row inset | 12 pt | 16 pt, matching the header and the card's own inset |
| Second-line set note | 48 pt inset | 40 pt, following the smaller circle slot |
| Exercise icons | their own row under "Add Set", left-aligned, no tap target | on the **"Add Set" row, right-aligned**, each in a 34 pt frame with a content shape and its own identifier |
| Card header | 10 pt above/below | 12 pt |

The label/value gap was changed in **both** the read-only column and the
editing cell, so a typed row and a finished row line up identically. No
identifier used by a test changed; the icon buttons gained identifiers
(`exercise-note-button`, `exercise-history-button`, `exercise-pr-button`).

**Evidence:** the visual tour at `ff1cb43` — `docs/visual/11-active-workout-populated.png`
(the row rhythm, the smaller circle, and the icons on the Add Set row) and
`docs/visual/07-active-workout.png` (a populated card top to bottom). Gate:
`** BUILD SUCCEEDED **`, 36/36 unit, 12/12 UI, `All Mac tests passed.`

---

## 1. Test evidence (all real, all run)

### 1.1 The gate — `bash scripts/mac-tests.sh` (one run, pasted raw)

```
=== build tail ===
note: Removed stale file '/Users/eamon/Library/Developer/Xcode/DerivedData/RepLog-adxaljfebupsngcpevwhfpancuev/Build/Products/Debug-iphonesimulator/RepLog.app/PlugIns'

** BUILD SUCCEEDED **
=== unit summary ===
✔ Test run with 36 tests in 5 suites passed after 0.688 seconds.
2026-09-23 00:25:59.451 xcodebuild[74166:1882612] [MT] IDETestOperationsObserverDebug: 21.471 elapsed -- Testing started completed.
2026-09-23 00:25:59.451 xcodebuild[74166:1882612] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
=== suites ===
✔ Suite "CSVCodec" passed after 0.218 seconds.
✔ Suite "Importer (in-app, new schema)" passed after 0.417 seconds.
✔ Suite "Metrics" passed after 0.008 seconds.
✔ Suite "Outbox state machine" passed after 0.025 seconds.
✔ Suite "Targets" passed after 0.015 seconds.
=== UI tests ===
Test Case '-[RepLogUITests.RepLogUITests testExerciseSearchFilters]' passed (25.937 seconds).
Test Case '-[RepLogUITests.RepLogUITests testOfflineDrill]' passed (106.059 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEChipsDisplayWholeValues]' passed (34.269 seconds).
Test Case '-[RepLogUITests.RepLogUITests testRPEEntryTypes85AndReadsBack]' passed (32.853 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSessionRowOpensDetail]' passed (51.736 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSetNoteEntry]' passed (32.981 seconds).
Test Case '-[RepLogUITests.RepLogUITests testSyncURLAndTokenFields]' passed (35.623 seconds).
=== UI summary ===
	 Executed 7 tests, with 0 failures (0 unexpected) in 319.458 (319.483) seconds
=== final ===
** TEST SUCCEEDED **
** TEST SUCCEEDED **
All Mac tests passed.
```

### 1.2 Service tests + the fast gate — `bash scripts/verify.sh`

Run on the fleet host at the same commit (seconds, no simulator — this is the
goal gate used while working):

```
    _PortalFactoryType = Callable[[], AbstractContextManager[anyio.abc.BlockingPortal]]

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
55 passed, 2 warnings in 0.36s
==> validate committed CSV fixtures (frozen §4.4 header)
File:         Tests/Fixtures/golden_session.csv
Rows:         8
Sessions:     1
Schema errors: 0
Anomaly counts (informational, not errors):
  (none)
verify.sh: PASS
```

### 1.3 The in-simulator offline drill (plan §7.5)

Part of the 7/7 UI run above (`testOfflineDrill`, ~107 s). What it does, in
order: service stopped → finish a session → the queue survives an app restart
→ service up → exactly one upload → delete in the app → tombstone on the
server → re-import the same session gets 409 and cannot resurrect it.

Evidence from the service side of that run (uvicorn access log in the drill's
fresh data dir, and its JSONL audit):

```
INFO:     127.0.0.1:57369 - "POST /v1/sessions HTTP/1.1" 200 OK
{"type":"init","ts":"..."}
{"type":"upsert","session_id":"6937DA44-...","sets":1,"ts":"..."}
```

The service starts in a fresh data dir every run, so a single row in its CSV
*is* the "exactly one upload" assertion. The service-side drill (the same
sequence driven directly against uvicorn) passed earlier and is unchanged by
this pass.

### 1.4 Unit tests (swift-testing) — 36/36

Included in §1.1. Coverage: metrics (volume per exercise type, bodyweight
multiplier, single-arm doubling, **Brzycki e1RM — 100 kg × 5 → 112.5** per
plan §11, per-rep-range / seasonal / session PRs), target resolution (Latest /
By Routine / repeat exact vs latest), CSV codec (quoting, formula escaping,
ISO dates, empty RPE, **golden CSV byte-for-byte** vs the committed fixture +
round-trip), importer (new schema + legacy RepCount export, RPE lifted out of
notes prose, anomaly reporting), outbox state machine (queued/dirty/failed
transitions, backoff, tombstone rejection).

### 1.5 Real-data migration (plan §1.6 / DoD 5) — unchanged, still true

`python3 scripts/repcount_import.py` (run in the earlier pass, not rebuilt):

```
Total rows:          6524
Migrated rows:       6524
Distinct sessions:   636
Anomaly counts (rows the importer refused to guess at):
  rpe_review          216   (RPE-shaped notes it will not auto-assign)
  date_shaped_note     73   ("07-Aug", "06-Jul", ...)
  excel_error_note     25   (#NAME? formula errors)
  blank_reps            7
  reps_out_of_range     6
  weight_out_of_range   4
  blank_weight          1
```

This matches the plan's own measured figures (73 date-corrupted notes, 25
`#NAME?`). The validator (`scripts/validate_sessions.py`) checks data validity
only — it deliberately does **not** apply the coach's 20–400 kg / 1–12 rep 1RM
junk filter, which would have rejected ~15% of legitimate rows. The real
export was never copied into the repo.

---

## 2. What this pass actually fixed (with the evidence for each)

### 2.1 A real app bug: rows that look tappable but are not

The three failing UI tests were not (only) test bugs. The `testSessionRowOpensDetail`
failure led, via a coordinate scan, to this: with `.buttonStyle(.plain)` a row's
tap target is the label's **content shape**, not its frame. Taps that land in
the gaps — under a `Spacer`, between two text lines — did nothing. Measured on
the Log before the fix (x-scan at the second row's centre line):

```
tap (201,320) -> detail-open: 0      tap ( 60,320) -> detail-open: 1
tap (280,320) -> detail-open: 0      tap (120,320) -> detail-open: 1
tap (201,480) -> detail-open: 0      tap (340,320) -> detail-open: 1
```

Every session row except the top one was dead, and so was every exercise row
in the routine detail. Fixed by `.contentShape(Rectangle())` on those rows;
after the fix all four scan points open the detail:

```
tap (201,320) -> detail-open: 1
tap (280,320) -> detail-open: 1
tap (201,480) -> detail-open: 1
tap (201,245) -> detail-open: 1
```

Related, same pass:
- `SessionRowView` carried `.accessibilityElement(children: .combine)` inside
  the row button's label; the identifier/label now live on the button itself
  and the row view is pure content.
- The statistics exercise list used a value-based push inside a stack that
  mixes view-based pushes, and the pushed screen popped straight back; it now
  uses a view-based link.
- `-ResetRepLog NO` reset anyway (presence-only flag), which would have wiped
  the queued session and sync config during the drill's relaunch step.

### 2.2 The three failing UI tests

| Failure (run `Test-RepLog-2026.09.22_21-44-01`) | Cause | Fix |
|---|---|---|
| `testSyncURLAndTokenFields`, `testOfflineDrill`: "sync URL field not found" | `tapSwitchKnob` tapped `(dx 0.45, dy 0)` — normalised offsets are top-left based, so that is the row's LABEL at its top edge. The toggle never flipped. | Tap `(0.92, 0.5)` (right edge, vertically centred) and assert the value flips `0` → `1`, so the next failure names the toggle. |
| `testSessionRowOpensDetail`: "session row not shown in Log after finishing" | `app.buttons["session-row-"]` is an exact identifier match; real ids are `session-row-<8 chars>`. It can never match. | `BEGINSWITH` predicate query, plus a dump of matching elements on failure. The row also really was dead (2.1). |
| `testOfflineDrill`: drill stalled after the token was typed | iOS's AutoFill "Save Password?" prompt (a system alert) is up after typing into the token field and **swallows every later tap** — visible in the failure screenshot over the Profile screen. | The drill takes its sync config from `-SyncURL` / `-SyncToken` launch arguments (same writes the Settings screen makes) and never types; the sync-form test dismisses the prompt if it appears. |
| `testOfflineDrill`: "expected one set row, got 0" with a 200 OK in the service log | The drill read the session id from the Log's *first* row; the Log also holds earlier sessions, so it could count rows for the wrong session. | The service starts in a fresh data dir per run: poll for exactly one CSV data row, take the session_id from that row, delete that exact row, and check the tombstone against the full id. |

### 2.3 Harness and gate scripts

- `scripts/mac-tests.sh`: kills a stale drill supervisor **and** a leaked
  uvicorn before starting; `trap` stops them on every exit path; hard-fails if
  the supervisor never comes up (a skipped drill would otherwise let the gate
  look green); `-skip-testing` keeps the gate at exactly the 7 gating tests.
- `scripts/verify.sh` (new): the fast deterministic gate — service pytest plus
  `validate_sessions.py` over the committed fixtures. Seconds, exits non-zero
  on any failure.
- `scripts/drill_supervisor.py`: kills whatever holds the service port before
  starting, fails if its own child exits (bind failure) instead of trusting a
  health response from a stale process, and stops the child on SIGTERM.
- New test classes (not part of the gate): `RepLogAccessibilityTests`
  (`performAccessibilityAudit()`, findings printed — §5) and
  `RepLogVisualTourTests` (the dark-mode capture tour — §4).

### 2.4 Visual defects found by the pass and fixed

- The Log's and Routines' **Edit** buttons rendered as a clipped circle showing
  a single letter (an iOS 26 toolbar clips a `.bordered` + `.capsule` text
  button). They are now an explicit capsule label with `.fixedSize()`, matching
  IMG_8144 (verified in `docs/visual/04-log.png`; the clipped rendering is in the
  earlier capture set kept in the pass log).

---

## 3. Parity matrix (plan §3.1) — row by row, as it stands now

Legend: ✅ verified in this pass with the evidence cited · 🟢 implemented,
proved by unit tests/code, no visual capture · ⏸ device-only, listed in §6.

| # | Feature | Status | Evidence |
|---|---|---|---|
| 1 | Log tab: month groups, "N Workouts", session rows (badge/routine/summary/duration), Edit mode, "+" | ✅ | `docs/visual/04-log.png` vs `IMG_8144` — month header + count, date-badge rows, "Nx Exercise" lines, durations, floating tab bar. Rows read "4x Competition Bench / 3x Dips" (never "0x"). Row tap covered by `testSessionRowOpensDetail` (green). |
| 2 | Active workout: finish check, date title, timer+overflow, session card, exercise cards | ✅ | `07-active-workout.png`, `11-active-workout-populated.png` vs `IMG_8156`/`IMG_8157` — teal check, centred date, timer + ellipsis capsule, session card (Start/End/Bodyweight/Notes), exercise cards with schemes. |
| 3 | Set rows: circled number, Weight, Reps, **RPE**, Notes, per-row "…", note line, Add Set, per-exercise icons | ✅ | `11-active-workout-populated.png` shows the RPE column between Reps and Notes with a value and a note line; RPE entry + chips covered by two green UI tests. |
| 4 | Rest timer: ring, −15/play/+15, presets, auto-start, per-second buzz, sound choice, notification-based, Live Activity | ✅ (sheet) | `12-rest-timer.png` (ring, ±15 s, play, presets). Sound/behaviour settings visible in `21b-settings-scrolled.png`. Live Activity: §6. |
| 5 | Routines: list, create, edit, duplicate, reorder; detail (Start, target mode, notes, exercise list) | ✅ | `14-routines-list.png` vs `IMG_8145`; `15-routine-detail.png` vs `IMG_8146` (Start this Workout, Weight and Reps → Latest, exercises card). |
| 6 | Routine exercise editor: warm-up/working counts, scheme, notes, replace, delete | ✅ | `16-routine-exercise-editor.png` vs `IMG_8147` — Warm Up Sets 1 / Sets 4, scheme rows, Notes, Replace Exercise, Delete. |
| 7 | Select Exercise sheet: search, categories, variants, "…", info marker, Regular/Superset, multi-select | ✅ | `08-select-exercise.png` vs `IMG_8148`, `09-select-exercise-category.png` vs `IMG_8149`; search covered by a green UI test. |
| 8 | Exercise library: 12 categories + exercises, Edit Exercises/Categories, add & edit | ✅ | `22-exercise-library.png` vs `IMG_8159`, `23-exercise-editor.png` vs `IMG_8150`/`IMG_8151`, `24-edit-categories.png` vs `IMG_8160`. |
| 9 | All eight exercise types with type-appropriate rows | 🟢 | `ExerciseType` enum + type-driven columns in `SetRowView`; the Dips card (bw_weight_reps) is visible in the active-workout captures; metrics per type are unit-tested. No per-type visual sweep — an agent-authored demo history would be needed to populate all eight. |
| 10 | Statistics hub: Exercises, Categories, Overall (duration, volume, sets, reps, reps/set, bodyweight, workouts) | ✅ | `17-statistics-hub.png` vs `IMG_8152`, all rows unlocked (RepLog ships unlocked — intended difference, no lock icons). |
| 11 | Charts: e1RM, volume, top/avg weight, reps, sets, workouts; ranges, grouping, actual+trend toggles | ✅ (partial) | `18-chart-screen.png` (per-exercise Volume + e1RM (Brzycki)) and `18b-overall-volume-chart.png` (overall metric screen). The nine metrics share two chart views; only Volume/e1RM were captured populated. |
| 12 | Personal records: per rep range, seasonal, session records | ✅ | `19-personal-records.png` — "Best per rep range" (2/3/4/5 reps), "Seasonal bests" (2026), "Session records" (max reps/sets/volume). |
| 13 | Exercise history from the workout screen | 🟢 | `ExerciseHistoryView` is wired to the per-exercise icon row (the notes/history/PR icons are visible in `07-active-workout.png` and `13-session-detail.png`); the capture attempt for the history screen itself did not land in this pass, so the evidence is code + the icon row. |
| 14 | Supersets: grouped rendering, replace member, swipe copy across the group | 🟢 | `supersetId` on entries, Regular/Superset switch visible in `08-select-exercise.png`, grouped rendering + `addSuperset` in code; `addSuperset` path not exercised in the captures. |
| 15 | Drop sets: per-set marker, "↓" in row and history | 🟢 | `SetEntry` drop flag + rendering in `SetRowView`/history; no drop set in the synthetic history to capture. |
| 16 | Repeat workout (last performance vs exact weights) + copy multiple sets | ✅ | `06-repeat-workout-sheet.png` — "Repeat Sep 22 — Push Day", Last performance \| Exact weights, Start. |
| 17 | Bodyweight: session field, Health import, per-exercise multiplier, BW+/BW− | ✅ (minus Health import) | Bodyweight rows visible in the session card (`11-...`, `13-session-detail.png`); multiplier + assisted handling unit-tested. Health import is §6. |
| 18 | Single arm/leg per exercise + global default | ✅ | Per-exercise "Single Leg / Single Arm" row in `23-exercise-editor.png`; global "Count Single Arm / Single Leg twice" in `21-settings.png`; doubling unit-tested. |
| 19 | Apple Health: write workouts + bodyweight, read bodyweight; active-energy estimate | ⏸ | Code present and compiles; needs a device + Health permissions (§6). The active-energy estimate stays explicitly out of scope. |
| 20 | Live Activities (Dynamic Island + lock screen) | ⏸ device-only | The widget extension compiles and the workout start/stop hooks are in place. Simulator attempt: with a workout running (`docs/visual/28-active-workout-foreground.png`) and the app sent home (`29-home-dynamic-island.png`), the Dynamic Island shows **no Live Activity content** — so this is unverified and claimed nowhere. |
| 21 | Profile: sync status line, Edit Exercises/Categories, Feedback, Help & Support, import/export | ✅ | `20-profile.png` vs `IMG_8153` — Sync section replaces the account block (intended), no Premium upsell (intended), plus Import CSV. |
| 22 | Settings: chart toggles, db language, unit, Health, autofill, autocorrect, timer sound/auto-start/keep-on/buzz, finish reminder, analytics, about | ✅ | `21-settings.png` vs `IMG_8154` (charts toggles, language, unit, Health, Workout Log); `21b/21c-settings-scrolled.png` vs `IMG_8155` (timer sound, auto-start, keep-screen-on, finish reminder, privacy links, analytics + its honest caption). |
| 23 | kg/lb global + per-exercise override; storage stays kg | ✅ | Weight Unit row in `21-settings.png`; per-exercise override in code (`ExerciseEntry.displayUnit`); storage frozen in kg by the CSV schema (validator enforces the header). |
| 24 | CSV export + Shortcuts/App Intents export action | ✅ | `25-export-csv-sheet.png` (Export CSV sheet); the same bytes come from `CSVCodec.encode`; the App Intent ships in code. |
| 25 | Offline-first: everything works offline; sync catches up | ✅ | The in-simulator drill (§1.3) + outbox unit tests. |
| 26 | Onboarding: no account, unit pick, optional Health, optional sync | ✅ | `01/02/03-onboarding-*.png` — units, "your data stays on this phone", optional sync. |

**RPE column (§3.2):** between Reps and Notes in the active workout and the
session detail, with the numeric pad + chips (6, 7, 7.5, 8, 8.5, 9) and `8`
rendering as "8" not "8.0" — the chips test and the read-back test are green,
the column is visible in `11-active-workout-populated.png`, and `rpe` sits
after `reps` in the frozen CSV header (validator-enforced).

**Deliberately not built (plan §3.1):** accounts / multi-device sync, StoreKit
paywall, Apple Watch, iPad layout, Android.

---

## 4. Visual pass vs the 17 reference screenshots

References: `"/mnt/hermes-shared/RepCount Screenshots/"`, IMG_8144–IMG_8160,
all dark mode. Every image below was captured in dark mode from a build with
the synthetic `-DemoData` history and inspected with vision. The full capture
method (and the traps) are in `docs/UI-VISUAL-PASS.md`.

### 4.1 What each reference actually is (the 1:1 map, finally)

| Ref | Screen |
|---|---|
| IMG_8144 | Log tab (month sections, session rows) |
| IMG_8145 | Routines list |
| IMG_8146 | Routine detail (SBD) |
| IMG_8147 | Routine exercise editor ("Low Bar Squat": Warm Up Sets 0, Sets 4, 1x1 / 3x4, Replace, Delete) |
| IMG_8148 | Select Exercise sheet (category list, Regular/Superset) |
| IMG_8149 | Select Exercise → category drill-in ("Bench Press" variants) |
| IMG_8150 | Edit Exercise sheet ("Wide Grip Bench") |
| IMG_8151 | Add Exercise sheet |
| IMG_8152 | Statistics hub (locked rows in RepCount) |
| IMG_8153 | Profile (RepCount: account block + Premium banner) |
| IMG_8154 | Settings top (Charts, language, unit, Health, Workout Log) |
| IMG_8155 | Settings scrolled (timer, privacy, analytics) |
| IMG_8156 | Active workout top (session card, Low Bar Squat sets) with the rest-timer dock |
| IMG_8157 | Active workout scrolled (Competition Bench + Sumo Deadlifts, Add Set, PR icons) |
| IMG_8158 | Rest timer sheet (ring, ±15 s, presets) |
| IMG_8159 | Edit Exercises list |
| IMG_8160 | Edit Categories list |

### 4.2 Screen | reference | verdict

| Screen (file in `docs/visual/`) | Reference | Verdict |
|---|---|---|
| 04-log.png | IMG_8144 | Match. Same structure: Edit capsule (its clipping was found and fixed this pass), circular "+", large "Log" title, month header with count, date-badge rows, duration trailing, floating tab bar with the teal active tab. RepLog's rows carry the RPE-informed summaries ("4x Competition Bench"), RepCount's read the same way. |
| 07/11-active-workout*.png | IMG_8156/8157 | Match, with the intended difference: RepLog adds the RPE column between Reps and Notes (RepCount has no RPE). Everything else lines up: teal check, centred date, timer + ellipsis capsule, session card rows, exercise cards with schemes ("1x5 / 1x4 / 1x3 / 1x2"), circled set numbers, Add Set + per-exercise icons, rest-timer dock. |
| 12-rest-timer.png | IMG_8158 | Match: big ring with the countdown, ✕, −15 s / play / +15 s, "Timers" row with presets. |
| 14-routines-list.png | IMG_8145 | Match (name + chevron rows). |
| 15-routine-detail.png | IMG_8146 | Match: "Start this Workout" capsule, routine card (name, "Weight and Reps" → target mode, Notes), exercises card with "N Sets" and scheme lines. |
| 16-routine-exercise-editor.png | IMG_8147 | Match: Warm Up Sets / Sets steppers, scheme rows, Notes, Replace Exercise, Delete. |
| 08-select-exercise.png | IMG_8148 | Match: Cancel / title / "+", search field, the 12 categories, Regular/Superset segmented switch. |
| 09-select-exercise-category.png | IMG_8149 | Match with a minor difference: RepLog's drill-in keeps the plain search placeholder ("Search Exercises") and shows no "+"/"…" in that bar; RepCount names the category in the title and repeats it in the placeholder. Cosmetic, not behavioural. |
| 22-exercise-library.png | IMG_8159 | Match: back, title, "+", search, alphabetical list with chevrons. |
| 23-exercise-editor.png | IMG_8150/8151 | Match: Name, Category, Exercise Type, Single Leg / Single Arm, Transfer Exercise Data, Delete (and the Add variant's empty name row). |
| 24-edit-categories.png | IMG_8160 | Match: the category list with chevrons and "+". |
| 17-statistics-hub.png | IMG_8152 | Match with the intended difference: no lock icons and no "premium" locks — RepLog ships everything unlocked; "Export to Excel" becomes "Export CSV". |
| 20-profile.png | IMG_8153 | Match with the intended differences: Sync section (status dot, Server, Sync now, Export CSV) replaces RepCount's account block and its "synced automatically" line; no Premium banner; Import CSV added under Data. |
| 21-settings.png + 21b/21c | IMG_8154/8155 | Match: Charts toggles (actual data, trend, warm-up, single-limb twice), language, Weight Unit, Apple Health, Autofill Weight + autocorrect, timer sound, auto-start, keep-screen-on, finish reminder, privacy/terms/about, and the analytics toggle with the honest "nothing is sent" caption. |
| No reference: 01/02/03-onboarding, 05-start-workout-sheet, 06-repeat-workout-sheet, 10-rpe-sheet, 13-session-detail, 18/18b chart screens, 19-personal-records, 25-export-csv-sheet | — | RepCount has no equivalent screenshots in the set. All render in the same dark palette/card language; the RPE sheet shows chips 6/7.5/8/8.5/9 and Clear, matching the spec rather than a reference. |

Explicitly intended differences (not bugs): the RPE column, Profile's Sync
section in place of an account block, no Premium upsell, unlocked statistics,
and Export CSV instead of "Export to Excel".

---

## 5. HIG checks possible in the simulator

- **Dynamic Type at `accessibility-extra-extra-extra-large`** — captures in
  `docs/visual/dynamic-type/` (dark and light): the heaviest screens (Log,
  active workout, statistics, settings, session detail). Findings: the Log, Statistics hub, Settings and the active workout's session card all
  re-wrap and stay legible: labels wrap to two or three lines, values right-align
  and nothing is clipped, truncated or overlapping. The one caveat is layout, not
  text: the bottom-most row sits behind the floating tab bar at rest (iOS 26's
  scroll-edge effect — scrolling reveals it), which matters more at XXL because
  the readable viewport is smaller. The scripted quick-mode tour's taps drift at
  XXL (rows grow), so the XXL set covers the Log, Statistics hub, Settings and
  the active workout's session card (the set rows sit below the fold in that
  capture), plus the sheets that happened to be up; the set-row columns were not
  re-checked at XXL itself. Files: `docs/visual/dynamic-type/xxl-*.png` (dark) and
  `docs/visual/dynamic-type/light-xxl-*.png` (light).
- **VoiceOver proxy — `performAccessibilityAudit()`** — run standalone via
  `-only-testing:RepLogUITests/RepLogAccessibilityTests` (findings are printed,
  never gated). Results: 33 findings, reported not gated:
  - Contrast (5): the Profile "About" caption and 4 unnamed rows on Profile/Settings,
    plus the onboarding Continue button.
  - Dynamic Type partly/unsupported (15): the Log's date-badge weekday labels and
    Edit button; the active workout's date title, bodyweight field and "—"
    placeholders; Settings' Done; several static labels at non-scaling sizes.
  - Hit area < 44 pt (6): the workout card's "…" menu, the Kg cell, "Add Set" and
    the three per-exercise icons (notes/history/PR).
  - Text clipped (3): the Log's date-badge weekday labels ("Wed"/"Mon"/"Tue")
    at large type.
  - No description (3): three unlabelled elements on onboarding.
None of these blocks the app; they are the queued polish list for the
accessibility pass, and the same audit is now a repeatable command (§7).
- **Reduce Motion / contrast** — the app uses system materials and semantic
  colours, and the audit's contrast check covers the teal-on-black pair; no
  custom animations beyond standard transitions.

Device-only, deferred and listed rather than claimed: real-device layout and
haptics, the local-network permission prompt, HealthKit authorisation and a
real workout write, Live Activities on a physical lock screen, sync over
Tailscale, and the on-device VoiceOver pass.

---

## 6. Out of scope (deferred, per the task)

- Installing on Eamon's iPhone with his Apple ID — includes the free-team
  HealthKit capability spike and any on-device Live Activity check.
- HealthKit verification on device (code compiles; permissions and a real
  workout write need a device).
- The active-energy calorie estimate (needs sex/height/DOB reads + a
  corrected-MET model; explicitly deferred, not half-done).
- Deploying lift-sync to the NAS (Dockerfile + compose shipped; nothing
  deployed).
- Migrating the coach profile's pipeline.
- Choosing the CSV's final home on the file share.

---

## 7. How to run

```bash
# The fast gate (seconds): service pytest + the CSV validator over fixtures
bash scripts/verify.sh

# The full Mac gate: build + 36 unit + 7 UI (incl. the offline drill)
bash scripts/mac-tests.sh              # pulls, builds, tests, cleans up

# The two standalone test classes (not part of the gate)
ssh mac 'cd ~/Documents/RepLog && xcodebuild test -scheme RepLog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:RepLogUITests/RepLogAccessibilityTests'      # HIG audit
ssh mac 'cd ~/Documents/RepLog && xcodebuild test -scheme RepLog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:RepLogUITests/RepLogVisualTourTests'         # capture tour
```

- **App:** `xcodegen generate` then `xcodebuild -scheme RepLog -destination
  "platform=iOS Simulator,name=iPhone 17 Pro" build`.
- **Service:** `cd service && uv sync && export LIFT_SYNC_TOKEN=$(openssl
  rand -hex 16) && uvicorn lift_sync.app:app --port 8080` (or
  `docker compose up`). In-app: Profile → Settings → Sync → URL + token.
- **Migration:** `python3 scripts/repcount_import.py <legacy-export.csv>
  --out <dir>/sessions.csv --report <dir>/import-report.json`.
