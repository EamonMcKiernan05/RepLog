import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    @State private var store: DataStore
    @State private var settings: Settings
    @State private var router: AppRouter
    @State private var syncEngine: SyncEngine

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
        // start at onboarding. -ResetRepLog NO must NOT reset: the offline
        // drill relaunches with NO because the queued session and the sync
        // config have to survive the restart (the old presence-only check
        // wiped them, which would have broken the drill's later steps).
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
        // Test hook: -SyncURL <url> -SyncToken <token> pre-configures sync so
        // the offline drill does not have to type into the Settings form.
        // Typing into the token SecureField triggers iOS's AutoFill "Save
        // Password?" prompt, and while that alert is up every later tap in a
        // UI test is swallowed (that is what stalled the drill twice on
        // 2026-09-22). This writes exactly what the Settings screen writes:
        // URL + enabled in UserDefaults, token in the Keychain.
        let launchArgs = args
        if let i = launchArgs.firstIndex(of: "-SyncURL"), i + 1 < launchArgs.count {
            set.syncURL = launchArgs[i + 1]
            if let j = launchArgs.firstIndex(of: "-SyncToken"), j + 1 < launchArgs.count {
                set.syncToken = launchArgs[j + 1]
            }
            set.syncEnabled = true
        }
        // Created AFTER the reset so isOnboarding reads the wiped state.
        let r = AppRouter()
        _store = State(initialValue: s)
        _settings = State(initialValue: set)
        _router = State(initialValue: r)
        _syncEngine = State(initialValue: SyncEngine(store: s, settings: set))
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
                    .environment(syncEngine)
                    .tint(Palette.accent)
                    .task {
                        syncEngine.start()
                    }
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
    func day(_ offset: Int, hour: Int, minute: Int) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0,
                 of: cal.date(byAdding: .day, value: -offset, to: .now)!)!
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
                              scheme: [[100, 5], [110, 4], [120, 3], [125, 2]], notes: "")
    let re2 = RoutineExercise(exercise: dips, sortOrder: 1, warmupSets: 0, workingSets: 3,
                              scheme: [[10, 8], [12.5, 8], [15, 6]], notes: "")
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

    ctx.insert(BodyweightEntry(date: cal.startOfDay(for: .now), weightKg: 102.0))
    store.save()
}
