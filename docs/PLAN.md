# RepLog — a RepCount clone for iOS (native SwiftUI)

> **For Hermes:** implement with the `subagent-driven-development` skill — one subagent per task, spec review then quality review. This file is the contract; do not silently re-scope.

**Goal:** A native iOS workout tracker that reproduces RepCount's look, feel and full feature set (free + premium), adds an **RPE column** between Reps and Notes, stores everything on-device, and optionally syncs finished sessions to a **self-hosted CSV** that AI agents can read cheaply and unambiguously.

**Architecture:** Single SwiftUI app (SwiftData on-device store, zero third-party packages) + one small self-hostable sync service ("lift-sync", one Docker image) that upserts finished sessions into a flat CSV on a share the fleet already reads. The phone is the source of truth; the CSV is a mirror plus a one-time history import.

**Stack:** Swift 6 / SwiftUI / SwiftData / Swift Charts / ActivityKit / UserNotifications / HealthKit, iOS 26.0 target. Dev on the MacBook Pro (Xcode 26.5, iOS 26.5 sims) over SSH; verification in the simulator via XCUITest + agent-device screenshots I inspect myself, then a real-device pass on Eamon's iPhone.

**Status:** v3 draft for Eamon's review — 2026-09-21. Reviewed three times: twice by me, once adversarially by an independent reviewer subagent whose findings are all folded in (§11). Nothing here is built yet.

---

## 1. What RepCount is, and how it works (verified)

### 1.1 The product

RepCount (Siper Apps AB, dev "Simon") is a strength-training logger for iPhone and Android. The site says "Trusted by 2M+ lifters worldwide"; the App Store listing says the app has been "downloaded more than 1 million times"; 4.9★ from 13K US ratings. Free with an optional Premium subscription ($4.99/mo, $29.99/yr). Everything about it is built to be *fast to log with*: one screen per workout, weight × reps × notes on each set, and last session's numbers pre-filled as grey placeholders so you never retype.

Core loop (site + help centre + screenshots):

1. Open the app → **Log** shows history grouped by month; each session is a row with date, routine name, exercise summary and duration.
2. Tap **+** → new workout for today, or open a saved **Routine** → "Start this Workout".
3. Add exercises: search or browse **category → exercise** (Bench Press → Competition Bench, Close Grip Bench, …), or **+** to create a custom exercise.
4. Log each set: weight, reps, note. Previous numbers show as placeholders; swipe right or tap the keyboard checkmark to accept them. Finishing a set starts the rest timer.
5. **Finish** (teal check) → session saved to history. Export/sync happens at that moment.

### 1.2 Features as shipped (source: pricing page, features page, App Store listing, help centre)

**Free (unlimited):** unlimited workouts, routines and custom exercises; notes on every set, exercise and workout; bodyweight logging; rest timer with notifications; full history; offline use; free account for cloud sync; Apple Health (iOS) / Health Connect (Android).

**Premium:** detailed interactive charts (date ranges, grouping per session/week/month/year, trend lines, tap-a-point values); personal records across every rep range (+ seasonal bests, max reps/sets in a session); exercise history from the workout screen; supersets; drop sets; CSV export; duplicate routines; copy multiple sets.

**Not in the product:** Apple Watch app, iPad app, home-screen widgets, public API. It has no API and offers CSV export — plus, on iOS, export through **Shortcuts** and workout sync to **Apple Health** — and those are the only data doors.

Other behaviours worth copying (help centre): targets come from the last time you did the *exercise* ("Latest", the default) or the last time you did that *routine* ("By Routine"); bodyweight exercises use **BW+** (added weight) / **BW−** (assisted) with a **bodyweight multiplier** for volume maths; **single arm/leg** exercises double the logged weight in volume; repeat-workout offers "last performance" vs "exact weights from that session"; cardio is a basic log (time, distance, calories); weight units can be switched globally *or per exercise inside a workout*; the exercise-database language is switchable.

**The eight exercise types (article 63 — this is the full list, not a guess):**

| Group | Types | What is tracked |
|---|---|---|
| Strength | **Weight, Reps** · **Weight, Time** | External load; reps, or time for weighted holds |
| Bodyweight | **Weight, Reps** (added load) · **Assisted bodyweight, Reps** (load subtracted) · **Reps** (pure bodyweight) · **Time** (planks, wall sits) | Bodyweight × multiplier drives volume |
| Cardio | **time, distance, calories** | One simple cardio option |
| Other | **note per set only** | Free-form catch-all |

### 1.3 Eamon's data today (measured, not assumed)

His Premium CSV export (`Z:\Gym\2022-2026 Training\Sessions Log All Time.csv`, exported 20 Aug 2026), read with Python:

- **6,524 set rows in 7 columns** (`Workout Start, Workout End, Exercise, Weight, Reps, Notes, Category`), one row per set, timestamps `DD/MM/YYYY HH:MM`, measured at **72 bytes/row**.
- **636 sessions**, 2022-04-20 → 2026-08-10, 10.3 sets per session, 88 distinct exercises, 11 categories. Top lifts: Competition Bench (826 sets), Sumo Deadlifts (603), Low Bar Squat (382). It includes Cardio rows (e.g. Treadmill) with blank weight/reps — the new schema has to carry those.

Why the current file costs accuracy and tokens (each number measured from the file):

| Defect | Count |
|---|---|
| RPE/RIR living inside the Notes prose (bare `8`, `8.5`; `Rpe 8`; ranges like `7.5-8`; `0`; `Rpe 11`) | **1,761 rows (27%)** — 1,446 bare numbers, 188 `rpe`/`rir` prefixed, 127 ranges |
| Notes corrupted into dates by an Excel round-trip (`07-Aug`, `02-Apr`, …) | **73** |
| Notes holding Excel error text (`#NAME?`) | **25** |
| Notes using a standalone `F` (the failure marker) | **460** |
| `Dropset` markers in prose | **37** (plus warm-up markers: 13) |
| Weight logged below 20 kg (legitimate light accessory work) | **898** |
| Weight exactly 0 (bodyweight) | **44** |
| Non-numeric / blank weight · reps | **3 · 9** |
| Reps above 50 · reps exactly 0 | **14 · 35** |
| Rows whose start/end timestamps don't parse cleanly into date + time | **17** |

The coach pipeline patches over this with heuristics (RPE = "leading number with optional rpe prefix"; a junk filter that once produced a fake 1,635 kg bench e1RM from an `85×547` typo row; a warning that `07-Aug`-style notes are leaked dates). A typed CSV with its own RPE column removes the guesswork — that is the whole justification for this build. **Re-export from the app before migrating** (this copy is six weeks stale).

---

## 2. Evidence base for this plan

| Checked | Result |
|---|---|
| repcountapp.com (home, features, pricing, about, exercises) | Feature lists, FAQ answers (incl. the iOS Shortcuts export line), 176 exercise guides |
| support.repcountapp.com | 8 categories, **50 articles** (per its sitemap); key ones read: 13 supersets, 15 logging, 16 bodyweight, 21/86/87 Health, 22 repeat, 26 drop sets, 28/29/51/53/62/77/90 timer, 35/57 charts, 39 targets, 42 multiplier, 46 single arm/leg, 49 planning, 50 Premium, 63 exercise types, 70 CSV export, 79/80 units, 85 no public API |
| App Store listing (id594982044) | Free/premium split, Health integration, iOS 18+ requirement, IAP prices, 83.5 MB |
| 17 screenshots, `\\192.168.1.12\smb\HermesShared\RepCount Screenshots\` | Full UI walk-through (§6); colours sampled from the pixels (§5) |
| Existing training CSV + coach profile | The coach already reads this data via a robocopy `.bat` into `~/gym-analysis/` — the new file must land in that world, not a new one |
| Mac (192.168.2.165, `ssh mac`) | macOS 26.6.2, **Xcode 26.5**, Swift 6.3.2, iOS 26.5 simulators, agent-device + serve-sim:3200 + XcodeBuildMCP:8766, ~33 GB free |
| Fleet | Host 192.168.1.30 (Tailscale 100.109.224.42); iPhone 14 Pro on the tailnet; TrueNAS .12 runs Samba + Docker and is on Tailscale (`truenas-scale-1`, 100.66.125.70) |
| Apple capability table (iOS), read live in a browser | HealthKit and Background modes are marked available in **all three** columns, including the free "Apple Developer" tier — yet Personal-Team signing is widely reported to reject HealthKit, so this becomes a 10-minute Phase 0 spike (§7.4) instead of an assumption in either direction |

---

## 3. Scope

### 3.1 Feature parity matrix (build every line — no collapsing into "config")

| # | Feature | Source | Notes for build |
|---|---|---|---|
| 1 | Log tab: history grouped by month, "N Workouts" per month, session rows (date badge, routine name, exercise summary lines, duration) | screenshots | Month sections; Edit mode; "+" to start |
| 2 | Active workout screen: finish check, date title, timer + overflow buttons; session card (routine, start/end time, bodyweight, notes); exercise cards with set rows | screenshots | Core screen — §6.2 |
| 3 | Set rows: circled set number, Weight, Reps, **RPE (new)**, Notes; per-row "…" menu (drop set, delete, insert); per-set note line; "Add Set"; per-exercise trailing icons (notes / history / PR) | screenshots | §6.2, §3.2 |
| 4 | Rest timer: ring + time, −15s / play / +15s, preset chips (00:30…), add preset; auto-start (article 90); per-second buzz (article 51); sound choice; **sound is notification-based and follows the ringer volume — a silenced phone silences the timer and iOS offers no override** (article 53); Live Activity / lock-screen widget | screenshots + articles 28/29/51/53/62/77/90 | §6.8. We match this behaviour rather than promising the impossible |
| 5 | Routines: list, create, edit, **duplicate** (premium), reorder; detail ("Start this Workout", Weight-and-Reps target mode, routine Notes, exercise list with set schemes) | screenshots + article 49 | §6.3 |
| 6 | Routine exercise editor: warm-up sets count, working sets count, scheme display (`1x1`, `3x4`), per-exercise notes, replace, delete | screenshots | |
| 7 | Select Exercise sheet: search, category list, variants, "…" actions, built-in info marker, **Regular / Superset** switch, multi-select then Add | screenshots + article 13 | §6.4 |
| 8 | Exercise library: categories (Abs, Back, Bench Press, Biceps, Cardio, Chest, Deadlift, Forearms, Legs, Shoulders, Squats, Triceps) + exercises; Edit Exercises / Edit Categories; add & edit (name, category, type, single leg/arm, transfer data, delete) | screenshots | §6.5 |
| 9 | **All eight exercise types** — Strength (Weight+Reps, Weight+Time), Bodyweight (Weight+Reps, Assisted, Reps, Time), Cardio (time/distance/calories), Other (note per set) | article 63 | Each type gets the right entry row in the workout screen — §6.2 |
| 10 | Statistics hub: Exercises, Categories, Overall (workout duration, volume, total sets, total reps, reps per set, bodyweight, number of workouts) | screenshot + article 68 | Locked for free users in RepCount; ours ships unlocked |
| 11 | Charts: e1RM, e1RM/BW, volume, top weight, avg weight, total reps, total sets, reps per set, workouts — each with date range, grouping (session/week/month/year), actual-data + trend-line toggles, tap-a-point, zoom/pan | features/pricing + articles 35/57 | Swift Charts; defaults: actual + trend on, warm-up excluded |
| 12 | Personal records: best per rep range, seasonal (per-year) bests, session records (max reps, max sets, max volume) | article 50 | |
| 13 | Exercise history from the workout screen: per-exercise list + volume/e1RM charts | article 50 | |
| 14 | Supersets: grouped exercises in workout/routine, giant sets, replace one member, swipe-right to copy weight/reps across the group | articles 13/50 | |
| 15 | Drop sets: per-set marker, "↓" in the row and in history | article 26 | |
| 16 | Repeat workout (last performance vs exact weights) and copy multiple sets | articles 22/50 | |
| 17 | Bodyweight: session field, Apple Health import, per-exercise bodyweight multiplier for volume, BW+/BW− logging | articles 16/42 | |
| 18 | Single arm/leg toggle per exercise (doubles volume) + the global settings equivalent | article 46 + settings screenshot | |
| 19 | Apple Health: write workouts, body measurements **and active energy** (a corrected-MET calorie estimate, so it needs sex/height/date-of-birth read permissions), read bodyweight | articles 21/86/87 | §7.4. If the calorie estimate is out of scope, say so explicitly rather than half-doing it |
| 20 | Live Activities for the active workout (Dynamic Island + lock screen) | features page | `NSSupportsLiveActivities` in Info.plist |
| 21 | Profile: sync/account status line, Edit Exercises, Edit Categories, Feedback, Help & Support, Review on App Store, follow link | screenshot | No accounts here — becomes Sync status (§6.6) |
| 22 | Settings: charts toggles (actual data, trend line, include warm-up, count single-arm twice), exercise-database language, weight unit, Apple Health, autofill weight, autocorrect for set notes, timer sound, auto-start timer, keep-screen-on, finish reminder, privacy/terms/about, anonymous analytics | screenshots | Analytics toggle stays, wired to nothing (nothing is sent) |
| 23 | Weight units: global kg/lb switch + reset, **and a per-exercise override inside a workout** | articles 79/80 | Storage stays kg (§4.4) |
| 24 | Data out: CSV export + **a Shortcuts/App Intents export action** | article 70 + features FAQ | Article 70 puts export at the bottom of the Statistics tab; ours also feeds the sync file (§4.4) |
| 25 | Offline-first: everything works with no connection; sync catches up later | FAQ + pricing table | §4.3 |
| 26 | Onboarding: no account, no signup; pick unit; optional Health; optional sync setup | site ("no account or card") | §6.9 |

**Deliberately not built:** accounts / multi-device sync, StoreKit paywall, Apple Watch, iPad layout, widgets, Android.

### 3.2 Additions Eamon asked for

1. **RPE column between Reps and Notes.** Per set, optional, half-point steps 1.0–10.0; numeric pad with quick chips (6, 7, 7.5, 8, 8.5, 9); displays `8`, not `8.0`. Appears in: active-workout rows, completed-session rows, exercise history, routine exercise notes/plan targets, and the CSV.
2. **Remote, self-hostable database = a CSV the app writes finished sessions to.** One-way push per finished session to `lift-sync` (§4.2), which upserts it into `sessions.csv`. Optional; off until configured.
3. **Offline queue.** Finish offline → stored and queued. **iOS gives no "the moment connectivity returns" trigger**: a queued session is uploaded on the next foreground run, a manual "Sync now", or an opportunistic background refresh. Sessions are never lost either way.
4. **On-device first.** SwiftData is the source of truth; losing the server loses nothing. Full-history CSV import (§4.5) rebuilds a new phone from the file.
5. **Agent-readable data.** Flat CSV, one row per set, ISO dates, numeric RPE, one writer, no Excel round-trip; plus a validator and an updated coach pipeline (§4.6).

---

## 4. Architecture

### 4.1 The app

```
RepLog/
  App/            RepLogApp.swift, AppRouter, RootTabView
  Models/         @Model Session, ExerciseEntry, SetEntry, Routine, RoutineExercise,
                  Exercise, Category, BodyweightEntry, SyncState
  Store/          DataStore (ModelContainer + VersionedSchema v1), Settings
  Engine/         Metrics (volume, e1RM/Brzycki, PRs), Targets (Latest/By Routine),
                  CSVCodec (encode/parse of the sync schema), Importer
  Sync/           SyncEngine (actor), Outbox, LiftSyncClient, Connectivity, BackgroundSync
  Features/       Log/, Workout/, Routines/, Exercises/, Statistics/, Profile/, Timer/
  DesignSystem/   Palette, Typography, Card, RowStyles, Haptics
  Resources/      SeedExercises.json, SeedCategories.json
  Tests/          RepLogTests/ (swift-testing), RepLogUITests/ (XCUITest), Fixtures/
```

Rules: zero third-party dependencies (the one escape hatch is §9 R2); `@Observable` where state outlives a view; all model mutation through `DataStore`; metrics are pure functions with unit tests; no networking outside `Sync/`.

**Info.plist / capabilities, done in T0.1 — missing these breaks sync on real hardware:**
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking`, **or** explicit `NSExceptionDomains` for the LAN and tailnet hosts, because the service speaks plain `http://`.
- `NSLocalNetworkUsageDescription` — required on iOS 14+ when the app connects directly to a local host; the user sees a permission prompt, so the Sync screen must explain it.
- `UIBackgroundModes` (`fetch`) + `BGTaskSchedulerPermittedIdentifiers` for the opportunistic retry.
- `NSSupportsLiveActivities`, HealthKit usage strings, notification usage.

### 4.2 The sync service — "lift-sync"

- **What:** one small Python (FastAPI) service, one Docker image, no database.
- **Where:** custom Docker app on TrueNAS main (192.168.1.12) — it already runs Docker, holds the data, speaks SMB and has Tailscale. Fallback: a small Debian LXC on Proxmox writing to the SMB share over CIFS (the house pattern for always-on services).
- **Data dir (bind mount):** a dataset folder exposed over SMB — target is the coach's workspace, `\\192.168.1.12\smb\Gym\Hermes Coach Workspace\`, or a `sync/` subfolder of it (open Q3).
- **Endpoints:**
  - `POST /v1/sessions` — one session (id, date, start/end, bodyweight, exercises → sets). Upserts by `session_id`; rewrites `sessions.csv`; appends one line to `sessions.jsonl` (audit trail / crash safety). Returns `{ok, session_id, sets}`.
  - `DELETE /v1/sessions/{session_id}` — records a **tombstone** in `sessions.jsonl` and removes that session's rows, so deleting on the phone deletes on the server and a later re-import cannot resurrect it.
  - `GET /v1/health` — uptime checks.
  - `GET /v1/export.csv` — the current file (debugging, restore path).
- **Single writer:** every mutation is serialised behind one lock in the service, then written to a temp file and `rename`d into place. Two concurrent uploads therefore cannot lose each other's rows. Agents open the file read-only.
- **Auth:** static bearer token, generated at setup, stored in the app's Keychain and the service env; recorded in Bitwarden — no plaintext creds in the vault.
- **Transport:** LAN `http://192.168.1.12:PORT` at home; Tailscale `http://100.66.125.70:PORT` away from home (the phone is already on the tailnet). HTTPS optional later via the existing nginx LXC; unnecessary while it is LAN + tailnet only.
- **Idempotency:** the same `session_id` upserts in place, so retries and post-upload edits are safe.

### 4.3 Data flow

```
  iPhone (source of truth)
    finish workout  ─►  session saved locally, syncState = queued
        │
        ├── online  ──► POST /v1/sessions ──► 200 ──► uploaded
        │                   ▲   retry + backoff on timeout/5xx; 401 → banner, retries pause
        ├── offline ──► stays queued → retried on the next foreground run, "Sync now",
        │               or an opportunistic background refresh (never a promise of instant delivery)
        └── edit or delete an already-uploaded session ──► syncState = dirty ──► re-posted / tombstoned
                             │
                             ▼
                  sessions.csv  +  sessions.jsonl        (TrueNAS dataset, SMB-shared)
                             │
                             ▼
        fleet reads it: /mnt/… (cifs) or Z: via robocopy ──► coach pipeline ──► analysis
```

Failure modes: server down → the queue grows, nothing is lost; wrong token → visible banner; duplicate upload → same id, no duplicate rows; delete → tombstoned on both sides; phone lost → the CSV holds the full history and can be re-imported.

### 4.4 The CSV contract (v1) — freeze before any code

One row per set. Header always present, always this order, always this spelling:

```
session_id,date,start_time,end_time,bodyweight_kg,exercise,category,exercise_type,superset_id,set_number,weight_kg,reps,rpe,duration_s,distance_m,kcal,set_type,notes
```

Worked example — a squats-and-bench session as the app would write it, plus a cardio row:

```
8f2c1d90,2026-09-21,06:04,07:43,100,Low Bar Squat,Squats,weight_reps,,1,160,1,8,,,,working,"felt heavy, good speed"
8f2c1d90,2026-09-21,06:04,07:43,100,Low Bar Squat,Squats,weight_reps,,2,140,4,7,,,,working,beltless
8f2c1d90,2026-09-21,06:04,07:43,100,Competition Bench,Bench Press,weight_reps,,1,100,1,8.5,,,,working,
8f2c1d90,2026-09-21,06:04,07:43,100,Dips,Chest,bw_weight_reps,,1,10,8,7.5,,,,working,
8f2c1d90,2026-09-21,06:04,07:43,100,Treadmill,Cardio,cardio,,1,,,,2100,5000,320,working,
```

Rules (each exists because of a defect in the current file):

| Rule | Why |
|---|---|
| `date` = `YYYY-MM-DD`; `start_time`/`end_time` = `HH:MM` (24h) | Kills the `07-Aug` class of corruption; ISO sorts correctly (today's `DD/MM/YYYY` strings do not) |
| Weight always **kg** in `weight_kg`; the unit lives in the column name | No ambiguity when the app is set to lb |
| `exercise_type` ∈ `weight_reps, weight_time, bw_weight_reps, bw_assisted, bw_reps, bw_time, cardio, note` | Tells an agent how to read the rest of the row: whether bodyweight applies, whether `weight_kg` is added load or assistance, and whether `duration_s`/`distance_m`/`kcal` carry the data. Without it, bodyweight and assisted sets are unreadable — exactly the ambiguity this file exists to remove |
| `rpe` = plain number 1–10, one decimal max, **empty when not recorded** — never a range, never `0`, never `11` | The point of the exercise: no parsing RPE out of prose. Ranges like `7.5-8` become the midpoint (or blank) with the original phrase preserved in `notes`; anything outside 1–10 goes to the migration's review list |
| `rpe` sits immediately after `reps`, before `notes` | Mirrors the on-screen column order |
| `duration_s`, `distance_m`, `kcal` populated for `weight_time`, `bw_time` and `cardio` rows; empty otherwise | Cardio and static holds have no weight/reps (the current export already carries Treadmill rows with blank weight/reps) |
| `set_type` ∈ `working,warmup,drop` (blank allowed on `cardio`/`note` rows) | Warm-ups and drop sets are prose today |
| `superset_id` empty or a short group id (`s1`, `s2`) | Lets an agent group supersets without guessing |
| `session_id` = stable UUID for the session, reused across retries and edits | Idempotent upserts, stable joins, no date collisions |
| Text fields quoted; UTF-8; LF; no BOM; no formulas. A leading `=`, `+`, `-` or `@` in free text is escaped at encode time (a leading space) | Excel opens it read-only and cannot mangle it; importing today's notes verbatim would otherwise inject 13 formula-shaped cells. The escape keeps the text identical when read back |
| Single writer (the service) rewrites the file atomically; readers open it read-only | No lock races, no Excel round-trip |
| `bodyweight_kg` repeated on every row (session level) | Self-contained rows; an agent never needs a join |
| Free-text `notes` keeps everything that isn't RPE | Nothing is lost from today's file |

Size, measured by re-encoding the real 6,524 rows into this schema: **99.8 bytes/row → 636 KB** (the old 7-column file is 72 bytes/row). At his current rate (~11 sets/session, 4 sessions/week) a decade of training adds ≈ **1.4 MB**. Cheap to read whole, cheap to grep, cheap to diff.

### 4.5 One-time backfill and RPE migration (a deliverable, not a nice-to-have)

1. **Re-export from the app first** (the copy on disk is six weeks stale).
2. `scripts/repcount_import.py` converts the export into the new schema:
   - `session_id` = deterministic hash of (Workout Start, Workout End) so re-runs are stable and two sessions on one day stay distinct;
   - `date`/`start_time`/`end_time` parsed from `DD/MM/YYYY HH:MM`; `exercise`, `category`, `weight_kg`, `reps` straight across; `set_number` = order within the exercise;
   - `exercise_type` inferred: bodyweight exercise list → `bw_weight_reps`/`bw_reps`; cardio list → `cardio`; everything else → `weight_reps`;
   - **RPE migration** for the ~1,761 affected rows: bare numbers and `Rpe 8` move to `rpe`; `RIR n` → `10 − n`; ranges (`7.5-8`) → midpoint with the phrase kept in `notes`; a standalone `F` (460 rows, the failure marker) → `rpe 10` when no number is present, with the `F` kept in `notes` (a documented convention the coach should know); anything outside 1–10 (`0`, `Rpe 11`) goes to the review list, never into `rpe`;
   - **`set_type`** from prose: `Dropset` → `drop`, warm-up → `warmup`, otherwise `working`;
   - **Corruption report** listing every row the importer refused to guess at: 73 date-shaped notes, 25 `#NAME?`, 9 non-numeric reps, 3 non-numeric weights, 17 rows with unparsable timestamps — for Eamon to eyeball. Never "fixed" silently.
3. The migrated file seeds `sessions.csv`; the original is archived beside it as `Sessions Log All Time - RepCount export (archive 2026-09).csv` — never overwritten.
4. The app can import the same file (one-time, via Files) to fill a fresh phone with four years of history.

### 4.6 Agent read path (the point of the whole exercise)

- `sessions.csv` lands where the coach already works, so the existing robocopy `.bat` pattern keeps working unchanged.
- Update the coach's `powerlifting-coaching` skill + `scripts/analyze_training_log.py` for the new schema: ISO parsing, `rpe` straight from its column (drop the prose heuristics), `exercise_type`/`set_type`/`superset_id` filters, and the `F → RPE 10` convention documented. **This edits the coach profile's own skill — Eamon approves or holds the pen (open Q4).**
- **Two different filters, not one** (a review caught this): the *validator* checks **data validity** — schema and column set, ISO dates not in the future, `rpe` 1–10 or blank, `reps` 0–100 or blank, `weight_kg` 0–500 or blank, `duration_s`/`distance_m`/`kcal` ≥ 0, enums respected, no duplicate `(session_id, exercise, set_number)`, no date-shaped notes. The *coach's 1RM junk filter* (20–400 kg, 1–12 reps) stays inside the analysis script, applied only where 1RM maths happens. Conflating them would mark ~1,000 legitimate rows (15% of the file — 898 sub-20 kg sets, 44 bodyweight sets, 35 zero-rep sets and the rest) as "invalid", and the migration gate could never pass.
- Result: an agent reads one flat, typed file with `pandas.read_csv` — no OCR of screenshots, no Excel quirks, no prose heuristics.

---

## 5. Look, feel and HIG conformance

Colours sampled directly from the screenshots (dark mode — how the app is actually used):

| Token | Value | Use |
|---|---|---|
| `bg` | `#000000` | Page background |
| `card` | `#1C1C1D` (≈ systemGray6 dark) | Grouped cards, sheets |
| `accent` | ≈ `#58C5D1` teal | Selected tab, actions, timer ring, PR highlights |
| `textPrimary` | `.primary` (white) | Titles, values |
| `textSecondary` | `.secondary` (≈ `#848C8F`) | Month headers, durations, captions |
| `destructive` | system red | Delete rows |
| `success` | system green | Switches (match system) |

- **Components:** system `TabView` (iOS 26 floating Liquid Glass tab bar — matches the screenshots), a `NavigationStack` per tab, inset-grouped cards, sheets for modals, `Menu` for "…" overflow, `ContentUnavailableView` for empties, SF Symbols throughout (as RepCount does).
- **Typography:** SF Pro through Dynamic Type, no hard-coded sizes; large titles per HIG; monospaced digits for weights/reps/timer so columns don't jitter.
- **Layout:** 16pt page margins, 12–16pt card padding, 44pt minimum hit targets (set rows ~56pt, tappable across the row), hairline separators inside cards.
- **Motion:** standard push/pop and sheet transitions; a spring on set completion and PR moments; respect Reduce Motion.
- **Accessibility:** VoiceOver labels on every set row ("Set 2, 140 kilograms, 4 reps, RPE 7"), Swift Charts' built-in audio graphs plus a text summary, Dynamic Type to XXL verified per screen, contrast checked on teal-on-black, larger-text and dark-interface declared.
- **Light mode:** RepCount is dark-first; we ship both (light = system backgrounds, same accent) and verify the light palette too.

---

## 6. Screen-by-screen spec (from the screenshots)

### 6.1 Log tab
Capsule "Edit" (left) and "+" (right) above a large "Log" title; month sections ("September 2026" + "3 Workouts"); one card per month holding session rows split by hairlines. Row: two-line date badge ("Mon" / "21", secondary), routine name (bold), up to three "Nx Exercise" summary lines, duration ("99 min") trailing in secondary. Tap → completed-session detail.

### 6.2 Active workout (the core screen)
Top bar: teal check (finish; confirms if sets are empty), centred date ("21 Sep"), then a capsule group with timer and "…". Session card: routine name, Start Time, End Time, Bodyweight (kg), Notes. Then one card per exercise: name + "…" (replace, notes, history, PR, remove), the planned scheme (`1x1`, `3x4`), then the sets. The set row adapts to the exercise's type:

| type | set row columns |
|---|---|
| `weight_reps` | set · Kg · Reps · **RPE** · Notes |
| `weight_time` | set · Kg · Time · **RPE** · Notes |
| `bw_*` | set · BW± · Reps/Time · **RPE** · Notes |
| `cardio` | set · Time · Distance · kcal · Notes |
| `note` | set · Notes only |

- Circled index restarts per exercise; each cell is individually tappable; a non-empty note also renders as a second line under the row (as the current app does).
- RPE cell: tap → numeric pad sheet with 0.5 steps and quick chips; long-press → clear.
- "Add Set" row with "+", then the per-exercise icon row (notes, history chart, PR).
- Finish → validation (missing weight/reps → offer to accept the placeholders), save to history, kick the outbox, end the Live Activity, stop the timer.

### 6.3 Routines
Rows with name + chevron, "+" to add, Edit to reorder/duplicate/delete. Detail: "Start this Workout" (teal); routine card (name, "Weight and Reps" target mode [Latest | By Routine], Notes); exercises card (name, "N Sets", scheme lines); exercise editor (Warm Up Sets 0, Sets 4, scheme, per-exercise Notes, Replace, Delete).

### 6.4 Select Exercise sheet
Cancel / "Select Exercise" / "+" / "…"; search field; category list; drill into a category for variants (built-ins carry an info marker, customs a "…"); bottom segmented switch **Regular | Superset**; in Superset mode, multi-select then Add creates one grouped entry.

### 6.5 Exercise library
Edit Exercises (alphabetical, search, + to create), Edit Categories (list, + to create). Exercise editor: Name, Category, **Exercise Type (the eight types)**, Single Leg/Single Arm (Default(No) | Yes | No), Transfer Exercise Data (moves history to another exercise), Delete.

### 6.6 Profile
Settings gear top-right. Sections: **Sync** (server URL, token, status, last sync, "Sync now", "Export CSV") replacing RepCount's account block — its line "Data is synced automatically when finishing a workout." becomes true here too; Edit Exercises; Edit Categories; Feedback (Send Feedback, Help & Support); Show Your Support (Review on App Store, follow) — kept, pointing at nothing fake; **no Premium upsell**.

### 6.7 Statistics
Hub list: Exercises, Categories, Overall Statistics (workout duration, volume, total sets, total reps, reps per set, bodyweight, number of workouts), then Export. Each metric screen: chart, range picker, grouping picker (session/week/month/year), toggles for actual data and trend line, tap a point for date + value, pinch/scroll to zoom. PRs screen: per-exercise per-rep-range table, seasonal bests, session records. Exercise history: list + volume/e1RM charts.

### 6.8 Timer
Sheet with a big ring, countdown, −15s / play-pause / +15s, and a preset row (00:30, 00:45, 01:00, 01:30, +). Settings for sound, auto-start, keep-screen-on, per-second buzz. The sound is a notification sound governed by the ringer volume — silent mode silences it, exactly as in RepCount, and the settings copy says so plainly instead of pretending otherwise. Live Activity shows the exercise, set count and countdown.

### 6.9 Onboarding (first run)
Three short screens: units (kg/lb); "your data stays on this phone"; optional sync (URL + token, with a Test button, and the local-network permission prompt explained). No account, no email, nothing mandatory.

---

## 7. Build, test and delivery

### 7.1 Repo and project
- Repo `replog-ios` (private) under `EamonMcKiernan05`; working title **RepLog** (easy to rename — open Q1).
- Bundle id `im.eamon.replog` (or his preference); Xcode 26.5 project, zero Swift packages.
- Build source of truth: the Mac at `~/Documents/RepLog/`, driven from the fleet host over `ssh mac` — the pattern the FFIOM-IOS app uses.
- **Test fixtures:** the real training export does **not** go in the repo (it carries injury notes and four years of personal data). Unit tests use a small anonymised fixture in the new schema, plus a legacy-export mode for the importer that is exercised from the file on the share.

### 7.2 Build and test commands
```bash
ssh mac 'cd ~/Documents/RepLog && xcodebuild -scheme RepLog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" build'
ssh mac 'cd ~/Documents/RepLog && xcodebuild test -scheme RepLog \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"'
```
Install/launch for visual checks (note the brew shellenv prefix — agent-device lives in Homebrew and is not on a non-interactive SSH PATH):
```bash
ssh mac 'xcrun simctl boot "iPhone 17 Pro"; xcrun simctl install booted <path>/RepLog.app'
ssh mac 'xcrun simctl launch booted im.eamon.replog'
ssh mac 'eval "$(/opt/homebrew/bin/brew shellenv)" && agent-device snapshot -i'
ssh mac 'eval "$(/opt/homebrew/bin/brew shellenv)" && agent-device screenshot /tmp/replog-<screen>.png'
```
…then I look at those screenshots myself and compare them against the reference screenshots on the share.

### 7.3 Test strategy
- **Unit (swift-testing):** metrics (volume per `exercise_type`, the bodyweight multiplier, single-arm doubling, Brzycki e1RM, per-rep-range/seasonal/session PRs), target resolution (Latest / By Routine), CSV encode + parse round-trip, importer, outbox state machine, sync client against a local stub, tombstone handling.
- **Golden file:** `CSVCodec` output must be byte-identical to a committed golden CSV for a fixture session — catches column-order, quoting and escaping drift.
- **UI tests:** XCUITest drives **every text-entry flow** (RPE sheet, search fields, sync URL/token, set notes) because agent-device's keystroke injection does not update SwiftUI `@State` bindings — a limitation recorded in our own `agent-device-ios-simulator` skill. agent-device handles navigation and screenshots, which is what it is good at.
- **Simulator passes:** drive each screen, screenshot, verify against the reference; log bugs rather than fixing mid-pass.
- **Offline drill:** service stopped → finish a session → queue survives an app restart; service up → exactly one upload, no duplicate rows; then delete a session → tombstone propagates and a re-import does not resurrect it.
- **Server tests:** pytest — upsert idempotency, serialised concurrent writes (two simultaneous POSTs, both survive), atomic rewrite, delete/tombstone, malformed payload rejection, auth.
- **Real device:** layout, Dynamic Type, haptics, Live Activity, Health permissions, the local-network prompt, sync over Tailscale.

### 7.4 Getting it on the iPhone
- **Free Apple ID (Personal Team):** installs from Xcode; the app **expires every 7 days**. Apple's capability table (read from the live page — HealthKit and Background modes show a tick in all three columns, including the free "Apple Developer" tier) suggests HealthKit should work, but Personal-Team signing is widely reported to fail with "provisioning profile doesn't support the HealthKit capability". **So this is a 10-minute Phase 0 spike (T0.2), not a decision made on my word:** add the capability to a free-team target and build. Report the result; open Q5 depends on it.
- **Paid Apple Developer Program (~$99/yr; check the current UK price at signup):** 1-year installs, no weekly re-signing, TestFlight if ever wanted.
- The Mac has ~33 GB free — Xcode DerivedData will eat it; clean between phases or move DerivedData elsewhere (open Q6).

---

## 8. Task plan

Phases run in order; tasks inside a phase are mostly independent. Every task ends with a verification that must pass before it counts as done. "V:" = verify.

### Phase 0 — Skeleton, design system, capability spikes
- **T0.1** Create the Xcode project (app + unit + UI test targets), iOS 26.0 target, bundle id, `RepLog` scheme, and the full Info.plist/capability set from §4.1 (ATS local-networking exception, `NSLocalNetworkUsageDescription`, background fetch + `BGTaskSchedulerPermittedIdentifiers`, Live Activities). **V:** builds on the iPhone 17 Pro simulator; a throwaway `URLSession` call to a local `http://` address succeeds in the simulator.
- **T0.2** **HealthKit spike on a free Personal Team** — add the capability, build for a device target, record the exact result. **V:** a written pass/fail decides open Q5.
- **T0.3** Design tokens (`DesignSystem/Palette.swift`, `Typography.swift`) with the §5 values as semantic tokens + a preview screen. **V:** screenshot shows black bg, #1C1C1D cards, teal accent.
- **T0.4** Card / setting-row / set-row shell components + a haptics helper. **V:** preview screen renders each.
- **T0.5** Root `TabView` with the four tabs (Log, Routines, Statistics, Profile), SF Symbols, floating tab bar. **V:** screenshot matches the reference tab bar.
- **T0.6** `DataStore` with `VersionedSchema v1` + `ModelContainer` wired into the app. **V:** smoke test creates and fetches a Session.

### Phase 1 — Models, metrics, CSV (no UI)
- **T1.1** `@Model` types: Session, ExerciseEntry, SetEntry, Routine, RoutineExercise, Exercise, Category, BodyweightEntry; enums `ExerciseType` (the eight), `SetType`, `SyncState`. **V:** unit test round-trips an object graph.
- **T1.2** Seed data: `SeedCategories.json` (the 12 categories) and `SeedExercises.json` (Eamon's 88 logged names + common variants, each with an inferred `exercise_type`). **V:** importer test loads 100+ exercises into a fresh store.
- **T1.3** `Metrics`: volume per `exercise_type` (external, bodyweight × multiplier, assisted, single-arm doubling), Brzycki e1RM, per-rep-range, seasonal and session records. **V:** unit tests, including `100 kg × 5 → 112.5` (§11 explains the formula choice).
- **T1.4** `Targets`: placeholder weight/reps resolution (Latest vs By Routine; repeat-workout exact vs latest). **V:** unit tests over a fixture history.
- **T1.5** `CSVCodec` encode/decode for §4.4: quoting, escaping of formula-shaped text, ISO dates, empty RPE, empty cardio fields. **V:** golden-file + round-trip tests.
- **T1.6** `Importer`: read a file in the new schema **and** the legacy RepCount export; build sessions; report unparsable rows. **V:** run against the real (re-exported) file from the share; assert rows/sessions and print the anomaly report.

### Phase 2 — Logging (what he uses daily)
- **T2.1** Log tab: month sections, session rows, duration, Edit mode. **V:** screenshot vs reference.
- **T2.2** Completed-session detail: cards, per-set rows, read-only. **V:** screenshot.
- **T2.3** Start a workout: "+" → today's session (optionally from a routine); session card with start/end, bodyweight, notes. **V:** functional test + screenshot.
- **T2.4** Add exercises: search / category / variant, exercise card with the planned scheme and type-appropriate row. **V:** screenshot.
- **T2.5** Set rows for all eight exercise types, with the **RPE column**, placeholders from targets, swipe-to-accept, add/delete/insert set, per-set note line, per-row "…". **V:** screenshots + placeholder unit tests.
- **T2.6** RPE input sheet: numeric pad, 0.5 steps, quick chips, clear. **V:** XCUITest types 8.5 and reads it back.
- **T2.7** Finish flow: validation, autofill offer, save, haptic, Live Activity end, enqueue. **V:** finish in the simulator → row appears in Log; outbox shows 1 queued.
- **T2.8** Edit and delete an uploaded session/set → `dirty`/tombstone path. **V:** unit test asserts the CSV row changes and the deleted rows disappear.
- **T2.9** Exercise history + PR views from the workout screen. **V:** screenshot.

### Phase 3 — Routines
- **T3.1** Routines list (add, reorder, duplicate, delete). **V:** screenshot + tests.
- **T3.2** Routine detail (start, targets mode, notes, exercise list). **V:** screenshot.
- **T3.3** Routine exercise editor (warm-up/working sets, scheme, per-exercise notes, replace, delete). **V:** screenshot.
- **T3.4** Start from a routine → pre-filled session. **V:** end-to-end test.
- **T3.5** Repeat workout + copy multiple sets. **V:** end-to-end test.

### Phase 4 — Supersets, drop sets, bodyweight, cardio
- **T4.1** Supersets: Regular/Superset switch, multi-select, grouped rendering, swipe-right copy across the group. **V:** screenshot + test.
- **T4.2** Drop set marker + rendering. **V:** test.
- **T4.3** Bodyweight types: session field, BW+/BW−/reps-only/time entry, multiplier in volume maths. **V:** volume test.
- **T4.4** Cardio type: time, distance, calories entry + display. **V:** screenshot + round-trip through the CSV.

### Phase 5 — Statistics
- **T5.1** Statistics hub + every metric screen (empty and populated states). **V:** screenshots.
- **T5.2** Swift Charts: line + point marks, actual vs trend, range and grouping pickers, selection readout. **V:** screenshot + interaction test.
- **T5.3** PR tables (rep ranges, seasonal, session records). **V:** test against fixture data.
- **T5.4** Export CSV (share sheet + Shortcuts/App Intents action) producing the same bytes the sync engine sends. **V:** exported file parses with the frozen header.
- **T5.5** Per-exercise weight-unit override inside a workout. **V:** screenshot; storage stays kg in the CSV.

### Phase 6 — Timer, notifications, Live Activity
- **T6.1** Timer engine (background-safe: store a deadline, never a tick counter) + sheet UI + presets. **V:** test that a 90 s timer survives backgrounding.
- **T6.2** Notification-based timer sound and honest settings copy (ringer volume governs it; silent mode is silent); per-second buzz; sound choice. **V:** manual device test.
- **T6.3** Live Activity + Dynamic Island for workout and timer. **V:** device screenshot.
- **T6.4** Settings screen (all toggles from §3.1#22) wired to a settings store. **V:** screenshot + persistence test.

### Phase 7 — Sync
- **T7.1** `lift-sync`: FastAPI app with a single-writer lock, upsert, delete/tombstone, atomic rewrite, JSONL audit, bearer auth, health, Dockerfile, compose file. **V:** pytest suite passes, including two concurrent POSTs.
- **T7.2** Deploy (TrueNAS custom app or LXC), mount the dataset, confirm the CSV appears on the share and is readable from the fleet host. **V:** `curl` from the fleet host + file visible over SMB.
- **T7.3** `SyncEngine` + `Outbox`: state machine (local → queued → uploaded / dirty / failed), retry with backoff, `NWPathMonitor`, `BGAppRefreshTask`, background URLSession. **V:** unit tests for every transition (including edit-after-upload) + a fake-server integration test.
- **T7.4** Profile → Sync section: URL, token (Keychain), Test, status, last sync, "Sync now", off switch, and the local-network permission prompt handled gracefully. **V:** end-to-end on device over Tailscale.
- **T7.5** Offline drill: airplane-mode finish → queue survives restart → reconnect → exactly one upload; then delete → tombstone, no resurrection. **V:** CSV row count before/after.
- **T7.6** `scripts/validate_sessions.py` (validity only, §4.6) + a periodic check that the file is still valid and growing. **V:** run against the seeded file; expect zero schema errors and a printed anomaly count.

### Phase 8 — Health, polish, delivery
- **T8.1** HealthKit: write workouts + body measurements (+ active energy if we keep it), read bodyweight and the sex/height/DOB the calorie estimate needs. **V:** device test; depends on T0.2's result.
- **T8.2** Accessibility + Dynamic Type pass (VoiceOver labels, XXL, Reduce Motion, contrast). **V:** XL/XXL screenshots + VoiceOver spot-check.
- **T8.3** In-app import (fresh phone ← CSV via Files). **V:** wipe the simulator, import, count sessions.
- **T8.4** App icon + launch screen in our own visual language (never a copy of RepCount's icon — its artwork is theirs). **V:** icon shows on the simulator home screen.
- **T8.5** Dogfood: Eamon logs a real session on his phone; compare it against RepCount's own output for the same session. **V:** his sign-off.
- **T8.6** Coach-side: migrate the pipeline (with approval) and have the coach answer a real question (e.g. "how has my squat e1RM trended since July?") from the new file, without screenshots. **V:** coach session log.

---

## 9. Risks and open questions

| # | Risk / question | My recommendation |
|---|---|---|
| R1 | **Disk on the Mac** — repo on a volume with ~33 GB free; Xcode + DerivedData runs 10–20 GB | Clear DerivedData between phases, keep one simulator runtime, check disk in every build task |
| R2 | SwiftData migration pain later | Versioned schema from day one; if it bites, move the store to raw SQLite (or accept GRDB as the project's one third-party dependency) behind the same `DataStore` API |
| R3 | 8 GB RAM Mac — builds and simulator runs are slow but workable | Reuse DerivedData, one simulator at a time |
| R4 | Real-device friction (7-day expiry on a free account) | Decide after the T0.2 spike (§7.4) |
| R5 | Copying RepCount's name/icon/artwork would be a copyright problem | Clone the interaction design and layout; use our own name, icon, palette and copy. No RepCount assets, no scraped guide images |
| R6 | Fitness data sits in plain text on a share | Token auth, LAN/Tailscale only, no third party, and no fixture of the real data in the repo. The CSV is **not** encrypted at rest — fine for training data, but said out loud |
| R7 | Scope creep back into "port the whole product" | The §3.1 matrix is the contract; anything not on it needs Eamon's yes |
| R8 | The migration gate could fail on legitimate data | Validator checks validity; the 20–400 kg / 1–12 rep filter stays where 1RM maths happens (§4.6) |

**Open questions for Eamon (answers change work, not direction):**

1. **Name and bundle id** — happy with "RepLog" / `im.eamon.replog`?
2. **iOS 26 minimum** — the screenshots show the iOS 26 floating tab bar, so I'm assuming your phone runs iOS 26 and we target 26.0 and skip 18.x compatibility. Confirm?
3. **Where the CSV lives** — coach workspace root (`Z:\Gym\Hermes Coach Workspace\sessions.csv`, replacing the old file after archiving) or a `sync/` subfolder beside it?
4. **Coach skill edits** — approve me updating `powerlifting-coaching` + `analyze_training_log.py` to the new schema, or will you do that yourself?
5. **Paid Apple Developer account** — depends on the T0.2 HealthKit spike; if HealthKit works on a free team, the only cost of staying free is re-installing weekly.
6. **Mac DerivedData** — OK to keep builds on the Mac's internal disk and clean up between phases, or shall I park DerivedData on the NAS?
7. **Apple Health calories** — keep the active-energy estimate (needs sex/height/DOB reads and more HealthKit surface), or write workouts + bodyweight only for v1?
8. **Anything you've always wanted changed in RepCount?** — cheap to do now, expensive later.

---

## 10. Definition of done

1. Every row of the §3.1 matrix exists and is reachable, plus the RPE column in the five places listed in §3.2.
2. A full session logged on his phone: RPE recorded, session in history, PRs and charts updated, uploaded to the self-hosted CSV exactly once.
3. The offline drill passes, including edit-after-upload and delete/tombstone (T7.5).
4. The coach answers a real coaching question from `sessions.csv` alone — no screenshots, no spreadsheet.
5. `sessions.csv` reports **zero schema errors** and carries the migrated 2022–2026 history with RPE extracted from the old notes, plus a **counted anomaly report** for the rows the migration refused to guess at (the count is the acceptance criterion, not cleanliness of the source data).
6. Layout/HIG pass complete: Dynamic Type XXL, VoiceOver spot-check, dark and light, on the simulator and on the device.

---

## 11. Review notes

**My pass 1 — full read with a calculator and the real data file.** Fixed: an unquoted comma inside a note in my own CSV example; an RPE sample that broke my own "plain number" rule; a wrong date range (the file ends 2026-08-10, not September); "dozens" of date-corrupted notes is really **73** (plus 25 `#NAME?`); the help centre has 50 articles, not 49; **bodyweight/assisted sets were unreadable** in the first schema, so `load_type` was introduced (later replaced by the more general `exercise_type`); garbled ASCII in the data-flow diagram; and a "four places" count that contradicted its own section.

**My pass 2 — feasibility and external checks.** Verified the e1RM arithmetic: RepCount's own worked example (100 kg × 5 → 112.5 kg) is **Brzycki**; **Epley** — used by the coach's existing script — gives 116.7, so the plan matches the reference app and flags the ~4% divergence. Softened the HealthKit claim to what sources support; confirmed the Mac's Xcode/Swift/simulator versions before promising a build loop; re-read the settings screenshots so every toggle reached the settings task.

**My pass 3 — measuring the numbers I cite.** Re-ran the file probe myself rather than trusting the reviewer's figures: 898 rows below 20 kg (excluding the 44 at zero), 460 rows using a standalone `F`, 37 `dropset` marks, 13 warm-up marks, and 17 rows whose timestamps don't parse cleanly — all now in §1.3 and §4.5. Also measured the new schema's real cost by re-encoding all 6,524 rows: **99.8 bytes/row, 636 KB**, ~1.4 MB per decade (§4.4).

**Independent review pass (separate reviewer subagent, prompted to report only evidenced defects).** It found real holes, all now fixed: (a) my validator's 20–400 kg / 1–50 rep ranges were lifted from the coach's *1RM junk filter* and would have failed ~1,000 legitimate rows (~15%), making the migration gate impossible — validator and junk filter are now separated and DoD 5 counts anomalies instead of demanding a spotless file; (b) **iOS network plumbing was missing entirely** — no ATS exception and no `NSLocalNetworkUsageDescription`, so the first POST would have failed on a real phone; (c) the exercise-type list was wrong (**eight** types, article 63), so the CSV needed `exercise_type`, `duration_s`, `distance_m` and `kcal` — without them cardio and holds could not be mirrored at all; (d) no delete/tombstone path and no dirty-on-edit transition, so the "mirror" could silently diverge from the phone; (e) the service's "append-only" claim contradicted its own rewrite and concurrent uploads could lose rows — now explicitly single-writer; (f) background upload was overpromised (iOS has no instant-on-connectivity trigger); (g) agent-device cannot type into SwiftUI text fields — XCUITest now covers every typing flow, and the `brew shellenv` prefix is in the build commands; (h) it corrected my HealthKit claim by reading Apple's live capability table, which marks HealthKit available on the free tier — I verified that myself (all three columns read `alt="yes"`) and turned it into a 10-minute spike instead of a belief; (i) smaller corrections: the silent-mode timer promise (impossible on iOS, article 53), units switching per exercise (article 79), the Shortcuts export, "2M+ lifters" vs "1 million downloads", the byte-per-row estimate, and the GRDB-vs-zero-dependencies contradiction.

*(Deliberately not done: no code, no repo, no deployed service — this is the plan for review.)*
