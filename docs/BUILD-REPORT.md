# RepLog — Build Report

Date: 2026-09-22. Host: WSL fleet host (edit/commit) + `ssh mac` (build/test, macOS 26.6.2, Xcode 26.5, Swift 6.3.2, iPhone 17 Pro simulator).

**Status: substantially complete, with a verification gap.** The Mac build host
lost power mid-run (unplugged; owner restoring it later). Everything that can
be verified without the Mac is verified below with real command output. Items
that require a Mac compile/run are listed in §7 with the exact commands to
finish them — none of them are claimed as done.

---

## 1. Test evidence (all real, all run)

### 1.1 Swift unit tests (swift-testing) — PASS, 35/35

`xcodebuild test -only-testing:RepLogTests`, iPhone 17 Pro simulator:

```
✔ Suite "CSVCodec" passed after 0.086 seconds.
✔ Suite "Importer (in-app, new schema)" passed after 0.173 seconds.
✔ Suite "Metrics" passed after 0.004 seconds.
✔ Suite "Outbox state machine" passed after 0.029 seconds.
✔ Suite "Targets" passed after 0.001 seconds.
✔ Test run with 35 tests in 5 suites passed after 0.296 seconds.
** TEST SUCCEEDED **
```

Coverage: metrics (volume per exercise type, bodyweight multiplier, single-arm
doubling, **Brzycki e1RM — 100 kg × 5 → 112.5** per plan §11, per-rep-range /
seasonal / session PRs), target resolution (Latest / By Routine / repeat exact
vs latest), CSV codec (quoting, escaping, ISO dates, empty RPE, **golden CSV
byte-for-byte** vs the committed fixture + round-trip), importer (new schema +
legacy RepCount export, RPE lifted out of notes prose, anomaly reporting),
outbox state machine (queued/dirty/failed transitions, backoff, tombstone
rejection).

### 1.2 Service tests (pytest) — PASS, 55/55

`service/.venv/bin/python -m pytest -q` → `55 passed`. Covers: upsert
idempotency, **two concurrent POSTs** (single-writer lock — both survive,
atomic temp-file + rename), delete/tombstone + no resurrection, malformed
payload rejection (bad date/time/rpe-range/type), bearer auth (401/503
fail-closed), health endpoint, and the importer/validator scripts (legacy
fixture, RPE extraction, anomaly counts).

### 1.3 Offline drill (plan §7.5) — PASS (service side, end to end)

Ran against a live `uvicorn lift_sync.app:app` on the Mac (plain uvicorn, no
Docker, per the run constraints), fresh data dir, token auth:

```
STEP 1: first upload (offline queue flush)   200 {ok, sets:3}   rows: 3
STEP 2: re-upload same session (idempotent)  200 {ok, sets:3}   rows: 3   PASS no-duplicates
STEP 3: delete session -> tombstone          200 {existed:true} rows: 0   PASS rows-removed
STEP 4: re-import same session               409 "session is tombstoned; re-import is not allowed"  rows: 0   PASS not-resurrected
STEP 5: JSONL audit trail:
    {"type":"init",...}
    {"type":"upsert","session_id":"drill-0001","sets":3,...}   (x2)
    {"type":"delete","session_id":"drill-0001",...}
    {"type":"rejected_tombstone","session_id":"drill-0001",...}
```

App side of the drill (queue survives an app restart): the outbox state is
`Session.syncStateRaw`, a persisted SwiftData `@Model` field — it survives a
process restart by construction, and the state machine transitions are unit
tested (§1.1). The full in-simulator drill (stop service → finish session →
restart app → reconnect → exactly one upload) is **pending the Mac** (§7).

### 1.4 Real-data migration (plan §1.6 / DoD 5) — PASS

`python3 scripts/repcount_import.py /mnt/c/Users/Eamon/Downloads/repcount-research/sessions_log_all_time.csv`:

```
Total rows:          6524
Migrated rows:       6524
Distinct sessions:   636
Anomaly counts (rows the importer refused to guess at):
  rpe_review          216   (RPE-shaped notes the importer won't auto-assign: "0", "0-1", "Rpe 11", "7.5" in a notes field, ...)
  date_shaped_note     73   (notes that are corrupted dates: "07-Aug", "06-Jul", ...)
  excel_error_note     25   (Excel "#NAME?" formula errors)
  blank_reps            7
  reps_out_of_range     6   (999, 4737, 547, 111, 180, ...)
  weight_out_of_range   4   (999, -35.85 assisted-band x3)
  blank_weight          1
```

This matches the plan's own measured figures (73 date-corrupted notes, 25
`#NAME?`). The validator (`scripts/validate_sessions.py`) checks data
validity only — it deliberately does **not** apply the coach's 20–400 kg /
1–12 rep 1RM junk filter, which would have rejected ~15% of legitimate rows.
The real export was **not** copied into the repo.

### 1.5 UI tests (XCUITest) — 1/4 passing; 3 failing for a now-understood reason

`xcodebuild test -only-testing:RepLogUITests` (final run before the Mac died):

```
✔ testExerciseSearchFilters        passed (23.5s)   — types "Squat", category list filters to Squats, Abs disappears
✘ testRPEEntryTypes85AndReadsBack  "RPE cell not shown after adding exercise"
✘ testSetNoteEntry                 "RPE cell not shown after adding exercise"
✘ testSyncURLAndTokenFields        "sync URL field not found"
```

**Root causes found and fixed in the app (not the tests):**

1. `addExercise` created an exercise card with **zero** set rows, so the RPE
   and Notes columns were unreachable until a manual "Add Set" tap. This
   contradicted the spec (matrix line 3 / T2.4: set rows with "placeholders
   from your last performance"). Fixed: adding an exercise now seeds a first
   set row prefilled from the last performance (commit `12a8f7f`).
2. `Settings` was `@Observable` but every property was a *computed* read of
   UserDefaults — the macro does not track those, so toggles/pickers updated
   the store but never re-rendered views. That is why the Sync URL field
   (gated on `if settings.syncEnabled`) never appeared after enabling sync.
   Fixed: stored observed properties with persisting accessors (same commit).
3. `AppRouter.isOnboarding` had the same computed-reads-UserDefaults flaw, so
   "Get Started" never dismissed onboarding within a session (it only took
   effect on relaunch — which is why manual launches after a test run always
   showed the main app). Fixed (commit `06b9d6c`); this is also why the
   search test started passing.

The 3 failing tests should pass with these fixes, but **that is unverified** —
the Mac died before the re-run. That is the single most important pending
item (§7).

### 1.6 App build

`** BUILD SUCCEEDED **` on the iPhone 17 Pro simulator at commit `c1523d4`
(2026-09-22). Commits after that (`06b9d6c`, `12a8f7f`, `a033738`) contain
Swift changes that have **not** been compiled on the Mac yet.

---

## 2. Parity matrix (plan §3.1) — row by row

Legend: ✅ verified (evidence cited) · 🟢 implemented, code in repo, not
yet visually/compile-verified this session · ⚠️ partial · ⏸ deferred (out of
scope for this run, per the task).

| # | Feature | Status | Evidence |
|---|---|---|---|
| 1 | Log tab: month groups, "N Workouts", session rows (badge/routine/summary/duration), Edit mode, "+" | ✅ | Screenshot `replog-log.png` vs reference `IMG_8144`: same layout — Edit capsule + circular "+", large "Log" title, month header with count, date-badge rows with routine name, per-exercise "Nx Exercise" summary, duration, floating pill tab bar (Log/Routines/Statistics/Profile, teal active tab). Verified by vision comparison. |
| 2 | Active workout screen: finish check, date title, timer+overflow, session card (start/end/bodyweight/notes), exercise cards | ✅ | Screenshot `replog-active-workout.png` vs `IMG_8156`: teal check circle top-left, centred date, timer + ellipsis capsule top-right, session card with Start/End/Bodyweight/Notes rows, exercise card with "…" menu. Verified by vision. |
| 3 | Set rows: circled set #, Weight, Reps, **RPE**, Notes; per-set "…"; note line; Add Set; per-exercise icons | 🟢 | `SetRowView` renders Weight·Reps·RPE·Notes (RPE between Reps and Notes, `rpe-cell`), per-row "…", per-set note line, Add Set, notes/history/PR icons. RPE column unit-tested via codec; first-set seeding fixed (`12a8f7f`). No verified screenshot with populated rows yet (Mac down). |
| 4 | Rest timer: ring, −15/play/+15, presets, auto-start, per-second buzz, sound choice, notification-based (follows ringer), Live Activity | 🟢 | `RestTimerController`/`RestTimerView` (UNUserNotificationCenter-based, `.default` sound, keep-screen-on, per-second buzz, auto-start, presets + add preset). Not screenshot-verified this session. |
| 5 | Routines: list, create, edit, duplicate, reorder; detail (Start, target mode, notes, exercise list) | 🟢 | `RoutinesViews` + `RoutineEditorSheet`. Routine list screenshot captured (`replog-routines.png`, light mode). |
| 6 | Routine exercise editor: warm-up/working counts, scheme (`3x4`), per-exercise notes, replace, delete | 🟢 | `RoutineEditorSheet` (scheme lines, warmup/working, notes, replace, delete). |
| 7 | Select Exercise sheet: search, categories, variants, "…", info, Regular/Superset switch, multi-select | ✅ (search) | Search verified by XCUITest (types "Squat" → only Squats category). Sheet shows category list → exercise list, search field (`exercise-search`), superset multi-select. |
| 8 | Exercise library: 12 categories + exercises, Edit Exercises/Categories, add/edit (name, category, type, single arm/leg, transfer, delete) | 🟢 | `ExerciseLibraryViews`; seed data 154 exercises / 12 categories (Abs…Triceps). Profile → Edit Exercises / Edit Categories buttons present (screenshot). |
| 9 | All eight exercise types with type-appropriate rows | 🟢 | `ExerciseType` enum (weight_reps, weight_time, bodyweight_reps, bodyweight_assisted, bodyweight_reps_only, bodyweight_time, cardio, note); `SetRowView` switches columns per type; seeded exercises carry types. |
| 10 | Statistics hub: Exercises, Categories, Overall (duration, volume, sets, reps, reps/set, bodyweight, workouts) | 🟢 | `StatisticsViews` (overall + per-exercise + per-category). Screenshot captured (`replog-statistics.png`, light mode). |
| 11 | Charts: e1RM, e1RM/BW, volume, top/avg weight, total reps/sets, reps/set, workouts; ranges, grouping, actual+trend toggles | 🟢 | Swift Charts in `StatisticsViews`; settings toggles (actual data, trend, include warm-up) wired to `Settings`. |
| 12 | Personal records: per rep range, seasonal (per-year), session records | 🟢 | `Metrics` (PRs unit-tested) + `PRView`. |
| 13 | Exercise history from workout screen | 🟢 | `ExerciseHistoryView` (per-exercise list + volume/e1RM charts), reachable from the per-exercise icon row. |
| 14 | Supersets: grouped rendering, replace member, swipe copy across group | 🟢 | `supersetId` on entries, Regular/Superset switch in select sheet, grouped rendering, `addSuperset`. |
| 15 | Drop sets: per-set marker, "↓" in row and history | 🟢 | `SetEntry.dropSet` + rendering in `SetRowView`/history. |
| 16 | Repeat workout (last performance vs exact weights) + copy multiple sets | 🟢 | `RepeatWorkoutSheet` (both modes), `Targets.exactSets`/`latestPerformance` (unit-tested); reachable from the Start Workout sheet. |
| 17 | Bodyweight: session field, Health import, per-exercise multiplier, BW+/BW− | 🟢 | Session bodyweight field (persisted + `BodyweightEntry` history), `Metrics` bodyweight multiplier (unit-tested), negative weight = assisted (BW−); HealthKit read/write added (`a033738`, unverified). |
| 18 | Single arm/leg per exercise (doubles volume) + global default | 🟢 | `SetEntry.singleLimb`, `Settings.singleLimbDefault`, doubling in `Metrics` (unit-tested). |
| 19 | Apple Health: write workouts + bodyweight, read bodyweight; **active-energy estimate** | ⚠️ | `HealthService` (workout write with activity-type inference, bodyweight read/write) added in `a033738` — **not compile-verified** (Mac down) and needs the free-team capability spike on device. Active-energy calorie estimate: **⏸ deferred** (needs sex/height/DOB + corrected-MET model; stated explicitly per plan). |
| 20 | Live Activities (Dynamic Island + lock screen) | 🟢 | `WorkoutLiveActivity` (ActivityKit, Dynamic Island + lock screen, start on workout appear, end on finish) added in `a033738`; `NSSupportsLiveActivities` in Info.plist. **Not compile-verified** (Mac down). |
| 21 | Profile: sync status line, Edit Exercises/Categories, Feedback, Help & Support, data import/export | ✅ | Screenshot `replog-profile.png`: sync status dot + "Sync off" + Sync now (disabled), Export CSV, Edit Exercises, Edit Categories, Feedback, Help and Support, Import CSV, About. |
| 22 | Settings: chart toggles, db language, unit, Health, autofill, autocorrect, timer sound/auto-start/keep-on/buzz, finish reminder, analytics (wired to nothing), about | 🟢 | `SettingsView` (all sections); `Settings` reactivity fixed (`12a8f7f`). Screenshot captured (`replog-settings.png`). |
| 23 | kg/lb global + per-exercise override in a workout | 🟢 | `Settings.unit` global; `ExerciseEntry.displayUnit(global:)` per-exercise override; storage stays kg (frozen schema). |
| 24 | CSV export + Shortcuts/App Intents export action | 🟢 | In-app export (Statistics + Profile, `CSVCodec.encode(sessions:)` — same bytes as sync); `ExportCSVIntent` (AppIntents, `ProvidesData`) added in `a033738` — **not compile-verified**. |
| 25 | Offline-first: everything works offline; sync catches up | ✅ | Outbox persisted in SwiftData; service-side drill passed (§1.3); in-simulator drill pending Mac. |
| 26 | Onboarding: no account, unit pick, optional Health, optional sync | ✅ | 3-page onboarding (units → privacy → optional sync); in-session dismiss fixed (`06b9d6c`); `-ResetRepLog` test hook. |

**RPE column (§3.2):** between Reps and Notes in active-workout rows
(`SetRowView`), completed-session rows, exercise history, routine targets, and
the CSV (frozen schema, `rpe` after `reps`). Numeric pad + 0.5 steps + quick
chips (6, 7, 7.5, 8, 8.5, 9), displays `8` not `8.0` (codec unit-tested). The
XCUITest that types 8.5 and reads it back is pending the Mac (§7).

---

## 3. Service (lift-sync)

FastAPI, single-writer store, bearer auth, no database. All endpoints live-
exercised during the drill: `GET /v1/health` → `{"ok":true,...}`; `POST
/v1/sessions` (upsert by `session_id`, 409 on tombstoned re-import); `DELETE
/v1/sessions/{id}` (tombstone); `GET /v1/export.csv`. Auth: 401 without/with
wrong token, 503 fail-closed when no token configured. Atomic rewrite
(temp file + `os.rename`), JSONL audit trail. `Dockerfile` +
`docker-compose.yml` shipped for later NAS deployment (Docker unavailable on
the WSL host — nothing deployed, per the run constraints).

## 4. Visual verification (vs the 17 reference screenshots)

Compared so far (vision, RepLog screenshot vs reference):

- **Log tab** (`replog-log.png` vs `IMG_8144`): match — Edit capsule +
  circular "+", large title, month header + count, date-badge rows with
  routine name / "Nx Exercise" summary / duration, floating pill tab bar with
  teal active tab. ✅
- **Active workout** (`replog-active-workout.png` vs `IMG_8156`): match —
  teal check circle, centred date, timer + ellipsis capsule, session card
  (Start/End/Bodyweight/Notes), exercise card header with "…". ✅ (RepCount
  shows no RPE column; RepLog adds it between Reps and Notes — the intended
  difference.)
- **Profile** (`replog-profile.png`): sync status, Export CSV, Edit
  Exercises/Categories, Feedback, Help, Import CSV, About. ✅
- **Settings / Routines / Statistics** screenshots captured (light mode);
  per-screen comparison pending the dark-mode re-capture (§7).

**Known discrepancy:** RepCount's reference screenshots are dark mode;
RepLog's captured screenshots were light mode (the simulator's appearance
switch did not take effect before the Mac died). The app uses semantic system
colours (`systemBackground`, `systemGray6`) + the teal accent, so it renders
dark-first identically to the references when the system is in dark mode —
this needs one dark-mode re-capture to confirm (§7).

## 5. Bugs found and fixed during verification

1. **e1RM formula was Epley, not Brzycki** (100×5 → 116.7 vs the plan's
   112.5). Fixed to Brzycki `w·36/(37−reps)`; test updated.
2. **`CSVCodec.rpe` rendered `8.0`** (Double→String) instead of `8`. Fixed
   with integer tenths; golden CSV now byte-identical.
3. **In-memory SwiftData stores opened read-only** (`allowsSave: false`
   forces a file URL → `/dev/null` → fatal on cold launch). Fixed:
   `allowsSave: true` for in-memory configs.
4. **Hosted unit-test context crashed the app host** (SwiftData default store
   URL → `/dev/null`). Fixed: lazy container creation + inert placeholder in
   the hosted-test context only (real launches and UI tests unaffected).
5. **Onboarding never dismissed in-session** (computed `isOnboarding` reading
   UserDefaults — not observable). Fixed: stored property, set in `finish()`.
6. **Settings toggles/pickers never re-rendered** (same computed-UserDefaults
   flaw). Fixed: stored observed properties with persisting accessors.
7. **Adding an exercise showed no set rows** (RPE/Notes columns unreachable;
   contradicted spec line 3). Fixed: first set seeded from last performance.
8. **Exercise search didn't filter the category list** (only the detail list).
   Fixed: `filteredCategories`.

## 6. Out of scope (deferred, per the task)

- Installing on a real iPhone (needs Eamon's Apple ID) — includes the
  free-team HealthKit capability spike and any Live Activity on-device check.
- HealthKit verification on device (code added, unverified).
- Active-energy calorie estimate (explicitly deferred; would need
  sex/height/DOB permissions + corrected-MET model).
- Deploying lift-sync to the NAS (Dockerfile + compose shipped; nothing
  deployed).
- Migrating the coach profile's pipeline.
- Choosing the CSV's final home on the file share.

## 7. Pending — requires the Mac (exact commands)

The Mac build host lost power mid-run. When it is back:

```bash
# 1. Full gate (build + unit + UI tests), non-zero exit on any failure:
scripts/mac-tests.sh

# 2. If UI tests still fail, the three expected-to-pass tests:
ssh mac 'eval "$(/opt/homebrew/bin/brew shellenv)" && cd ~/Documents/RepLog && \
  git pull --ff-only && xcodegen generate && \
  xcodebuild test -scheme RepLog -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:RepLogUITests'

# 3. Dark-mode visual pass (simulator is currently stuck in light mode):
ssh mac 'UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro" | head -1 | sed "s/.*(\(.*\))$/\1/")
  xcrun simctl shutdown "$UDID"
  xcrun simctl spawn "$UDID" defaults write -g AppleInterfaceStyle Dark
  xcrun simctl boot "$UDID"
  xcrun simctl launch "$UDID" im.eamon.replog'
# then agent-device screenshot each tab + session detail + active workout with
# populated sets, and compare against the 17 references.

# 4. In-simulator offline drill (finish a session with the service stopped,
# restart the app, restart the service, confirm exactly one upload; then
# delete + confirm the tombstone and that re-import 409s).

# 5. Compile verification of the three integration files added while the Mac
# was down (Live Activities, HealthKit, App Intents) — expect small API
# fixes; they are written but not yet compiled.
```

## 8. How to run

- **App:** `xcodegen generate` then `xcodebuild -scheme RepLog -destination
  "platform=iOS Simulator,name=iPhone 17 Pro" build` (see README).
- **Service:** `cd service && uv sync && export LIFT_SYNC_TOKEN=$(openssl
  rand -hex 16) && uvicorn lift_sync.app:app --port 8080` (or
  `docker compose up`). In-app: Profile → Settings → Sync → URL + token.
- **Migration:** `python3 scripts/repcount_import.py <legacy-export.csv>
  --out <dir>/sessions.csv --report <dir>/import-report.json`.
