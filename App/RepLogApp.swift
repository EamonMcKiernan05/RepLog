import SwiftUI
import SwiftData
import Foundation

@main
struct RepLogApp: App {
    @State private var store: DataStore
    @State private var settings: Settings
    @State private var router: AppRouter

    /// True when the app process is the host for a *hosted unit-test* bundle.
    /// In that context the app's UI is never looked at (the unit tests are pure
    /// logic and use their own in-memory stores), and the simulator data
    /// container is not ready at app launch, so creating the app's store would
    /// crash the host. Rendering a placeholder instead of the real UI keeps the
    /// store untouched. UI tests launch the app normally (no test bundle loaded
    /// into the app process), so this is false there and the real UI shows.
    private let isUnitTestHost: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        // Test hook: -ResetRepLog YES wipes persisted state so UI tests always
        // start at onboarding. -ResetRepLog NO must NOT reset: a test that
        // relaunches with NO has to find the previous run's data still there
        // (the old presence-only check wiped it either way).
        let args = CommandLine.arguments
        let resetValue = args.firstIndex(of: "-ResetRepLog").map { i in
            i + 1 < args.count ? args[i + 1] : "YES"
        } ?? "NO"
        let reset = resetValue.uppercased() != "NO"
        if reset {
            let bundleID = Bundle.main.bundleIdentifier ?? "im.eamon.replog"
            if let defaults = UserDefaults(suiteName: bundleID) {
                defaults.removePersistentDomain(forName: bundleID)
            }
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            // The SwiftData store is the other half of "persisted state":
            // without it a UI test starts at onboarding and then finds last
            // run's sessions in the Log. Safe here because the container is
            // created lazily, on first access, so nothing has it open yet.
            wipeStore()
        }
        let s = DataStore()
        let set = Settings()
        // Test hook: -DemoData seeds a small synthetic history (no real
        // training data) so the visual pass can capture populated screens.
        if CommandLine.arguments.contains("-DemoData") {
            // App.init runs on the main thread at launch.
            MainActor.assumeIsolated {
                seedDemoData(store: s, settings: set)
            }
        }
        // Created AFTER the reset so isOnboarding reads the wiped state.
        let r = AppRouter()
        _store = State(initialValue: s)
        _settings = State(initialValue: set)
        _router = State(initialValue: r)
    }

    var body: some Scene {
        WindowGroup {
            if isUnitTestHost {
                // Deliberately inert: nothing here may touch the store.
                Color.clear
            } else {
                RootTabView()
                    .environment(store)
                    .environment(settings)
                    .environment(router)
                    .tint(Palette.accent)
            }
        }
        // No .modelContainer(): nothing uses @Query or the modelContext
        // environment — every read/write goes through DataStore, whose container
        // is created lazily on first access. Attaching it here would force
        // creation at scene setup, which fails in the hosted unit-test context
        // and crashes the host.
    }
}

/// Seed a small SYNTHETIC history (no real training data) so the visual pass
/// can capture populated screens: a routine, three sessions this month with
/// sets/RPE/notes, and a bodyweight entry. Driven by the -DemoData launch
/// argument; never used in tests or on a real device.
@MainActor
private func seedDemoData(store: DataStore, settings: Settings) {
    let ctx = store.context
    settings.onboarded = true

    let cal = Calendar.current
    /// A demo session's clock time — morning workouts, but TODAY's session can
    /// never be in the FUTURE. A seeded "today 07:00" that has not happened yet
    /// outranks every session a test creates at `.now` as "the last time" an
    /// exercise was done, and the hint logic reads the newest session (found
    /// 2026-10-13: the hint test ran at 06:47, saw the seeded session as newest
    /// and read 100 where it expected 120). Pulled back far enough that the
    /// session's END (90 minutes later) lands in the past too.
    func day(_ offset: Int, hour: Int, minute: Int) -> Date {
        let base = cal.date(byAdding: .day, value: -offset, to: .now)!
        let target = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        guard offset == 0 else { return target }
        return min(target, cal.date(byAdding: .minute, value: -105, to: .now)!)
    }

    // Routine with a scheme.
    let bench = (try? ctx.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Competition Bench" })))?.first
        ?? Exercise(name: "Competition Bench", type: .weightReps, builtin: true)
    let squat = (try? ctx.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Low Bar Squat" })))?.first
        ?? Exercise(name: "Low Bar Squat", type: .weightReps, builtin: true)
    let dips = (try? ctx.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Dips" })))?.first
        ?? Exercise(name: "Dips", type: .bwWeightReps, builtin: true)

    let routine = Routine(name: "Push Day", sortOrder: 0)
    routine.notes = "Demo routine (synthetic data)."
    let re1 = RoutineExercise(exercise: bench, sortOrder: 0, warmupSets: 1, workingSets: 4,
                              notes: "")
    let re2 = RoutineExercise(exercise: dips, sortOrder: 1, warmupSets: 0, workingSets: 3,
                              notes: "")
    routine.routineExercises.append(re1)
    routine.routineExercises.append(re2)
    ctx.insert(routine)

    // Three sessions, newest first.
    func mkSession(offset: Int, name: String,
                   exSets: [(Exercise, [(Double, Int, Double?)])], bw: Double?) -> Session {
        let s = Session(date: day(offset, hour: 7, minute: 0), routineName: name)
        s.startTime = day(offset, hour: 7, minute: 5)
        s.endTime = day(offset, hour: 7, minute: 5) + 5400
        s.bodyweightKg = bw
        s.notes = offset == 0 ? "Felt strong today" : ""
        var order = 0
        for (ex, sets) in exSets {
            let entry = ExerciseEntry(exercise: ex, sortOrder: order)
            for (i, tuple) in sets.enumerated() {
                let set = SetEntry(setNumber: i + 1)
                set.weightKg = tuple.0
                set.reps = tuple.1
                set.rpe = tuple.2
                entry.setEntries.append(set)
            }
            s.exerciseEntries.append(entry)
            order += 1
        }
        ctx.insert(s)
        return s
    }

    _ = mkSession(offset: 2, name: "Push Day",
                  exSets: [(bench, [(100, 5, 7), (110, 4, 7.5), (120, 3, 8)]),
                           (dips, [(10, 8, 7), (12.5, 8, 7.5), (15, 6, 8.5)])], bw: 101.0)
    _ = mkSession(offset: 1, name: "Legs",
                  exSets: [(squat, [(160, 1, 8), (140, 4, 7), (140, 4, 7.5), (140, 4, 8)])], bw: 101.5)
    _ = mkSession(offset: 0, name: "Push Day",
                  exSets: [(bench, [(100, 5, 7.5), (110, 4, 8), (120, 3, 8.5), (125, 2, 9)]),
                           (dips, [(10, 8, 7), (12.5, 8, 8), (15, 6, 8.5)])], bw: 102.0)

    // Older history for the Statistics range-export test: sessions 40 / 150 /
    // 300 / 600 days back, so 1M, 3M, 6M, 1Y and All each hold a different
    // number of sessions. Gated on -DemoHistory so every existing capture and
    // test still sees exactly the three-session demo it always has.
    if CommandLine.arguments.contains("-DemoHistory") {
        _ = mkSession(offset: 40, name: "Legs",
                      exSets: [(squat, [(130, 5, 8)])], bw: 101.5)
        _ = mkSession(offset: 150, name: "Push Day",
                      exSets: [(bench, [(95, 5, 7.5)])], bw: 100.5)
        _ = mkSession(offset: 300, name: "Legs",
                      exSets: [(squat, [(125, 5, 8)])], bw: 99.0)
        _ = mkSession(offset: 600, name: "Push Day",
                      exSets: [(bench, [(90, 5, 8)])], bw: 97.5)
    }

    ctx.insert(BodyweightEntry(date: cal.startOfDay(for: .now), weightKg: 102.0))
    store.save()
}

/// Deletes the on-disk SwiftData store so `-ResetRepLog YES` really does start
/// from nothing. File-scope, called from `RepLogApp.init` before anything
/// creates the container (it is created lazily, on first access).
private func wipeStore() {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }
    // The directory holds RepLog.sqlite plus its -shm / -wal sidecars.
    try? fm.removeItem(at: base.appendingPathComponent("RepLog", isDirectory: true))
}

