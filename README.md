# RepLog

A native SwiftUI iOS workout tracker, plus an optional self-hosted CSV sync
service. Everything is stored on-device (SwiftData, zero third-party Swift
dependencies); finished sessions can optionally sync to a flat
`sessions.csv` that AI agents can read cheaply and unambiguously.

## What it does

- **Log** — history grouped by month, session rows with date badge, routine
  name, exercise summary and duration.
- **Active workout** — one screen per workout: session card (start/end,
  bodyweight, notes), one card per exercise, set rows with weight · reps ·
  **RPE** · notes, placeholders from your last performance, rest timer with
  ring + presets.
- **All eight exercise types** — Strength (weight+reps, weight+time),
  Bodyweight (BW+, BW−, reps, time), Cardio (time/distance/calories), Other
  (note per set).
- **Routines** — create, edit, duplicate, reorder; per-exercise warm-up /
  working sets and schemes; "Start this Workout".
- **Exercise library** — 12 categories, 150+ seeded exercises, add/edit,
  single arm/leg, transfer data.
- **Statistics** — overall metrics, per-exercise history with volume and
  e1RM (Brzycki) charts, personal records per rep range, seasonal bests,
  session records.
- **Supersets, drop sets, repeat workout**, bodyweight handling
  (BW+/BW−/multiplier), single arm/leg volume doubling.
- **kg/lb** global unit with per-exercise override inside a workout.
- **CSV export** (same bytes the sync service stores) and in-app import to
  rebuild a fresh phone from a file.
- **Offline-first** — sync is manual (the sync button on the Log shows what
  is waiting); the outbox queues finished sessions and retries with backoff.
  Deleting a workout on the phone is local-only: a copy that already reached
  the sync database stays there.

## The RPE column

Per set, optional, half-point steps 1.0–10.0, displayed as `8` not `8.0`.
Appears in active-workout rows, completed-session rows, exercise history,
routine targets and the CSV — immediately after Reps, before Notes.

## The sync service (lift-sync)

A tiny FastAPI service, one Docker image, no database. The phone pushes each
finished session; the service upserts it into `sessions.csv` behind a single
writer lock (atomic temp-file + rename), appends to a JSONL audit trail, and
records tombstones so a deleted session cannot be re-imported.

- `POST /v1/sessions` — upsert by `session_id` (bearer auth)
- `DELETE /v1/sessions/{id}` — delete + tombstone
- `GET /v1/health`, `GET /v1/export.csv`

See [`service/README.md`](service/README.md) for running it. The CSV schema
is frozen in [`docs/PLAN.md`](docs/PLAN.md) §4.4.

## Layout

```
App/            entry point, router, root tab view, Info.plist
Models/         SwiftData @Model types + the frozen enums
Store/          DataStore (container + seeding), Settings, Keychain
Engine/         Metrics, Targets, CSVCodec, Importer (pure, unit-tested)
Sync/           SyncEngine, Outbox (state machine), LiftSyncClient
Features/       Log / Workout / Routines / Exercises / Statistics /
                Profile / Timer
DesignSystem/   Palette, Typography (sampled from the reference app)
Resources/      SeedExercises.json, SeedCategories.json
Tests/          Unit (swift-testing) + UI (XCUITest) + Fixtures
service/        lift-sync (FastAPI) + pytest suite + Docker
scripts/        repcount_import.py, validate_sessions.py, mac-tests.sh
docs/           PLAN.md (the spec), BUILD-REPORT.md
```

## Building (on the Mac)

```bash
cd ~/Documents/RepLog
xcodegen generate
xcodebuild -scheme RepLog -destination "platform=iOS Simulator,name=iPhone 17 Pro" build
```

Or run the whole gate (build + unit + UI tests) from the repo on any host
that can `ssh mac`:

```bash
scripts/mac-tests.sh
```

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
   --bundle im.eamon.replog --version 1.1.3 --base https://replog.eamonmckiernan.im`.
3. On the iPhone, open `https://replog.eamonmckiernan.im/replog/` **in Safari**
   and tap Install RepLog.

Ad-hoc means only devices listed in the provisioning profile can install it.

## Running the service

```bash
cd service
uv sync
export LIFT_SYNC_TOKEN=$(openssl rand -hex 16)
export LIFT_SYNC_DATA_DIR=./data
uvicorn lift_sync.app:app --port 8080
```

In the app: Profile → Settings → Sync → enter the URL
(`http://192.168.1.12:8080` or your tailnet address) and the token.

## Tests

- **Unit (swift-testing):** metrics (volume per type, bodyweight multiplier,
  single-arm doubling, Brzycki e1RM, PRs), targets, CSV codec (golden file
  byte-identical to the Python service + round trip), importer, outbox state
  machine.
- **UI (XCUITest):** every text-entry flow (RPE, search, sync URL/token,
  set notes) — agent-device cannot type into SwiftUI fields.
- **Service (pytest):** upsert idempotency, two concurrent POSTs,
  delete/tombstone + no resurrection, atomic rewrite, auth, malformed
  payloads.


## Notes

- The CSV is not encrypted at rest; it lives on a LAN/tailnet share with
  bearer auth. Fine for training data, said out loud.
- No accounts, no paywall, no analytics (the toggle exists for parity and is
  wired to nothing).
