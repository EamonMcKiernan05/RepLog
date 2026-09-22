import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    @State private var store: DataStore
    @State private var settings: Settings
    @State private var router = AppRouter()
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
        let s = DataStore()
        let set = Settings()
        _store = State(initialValue: s)
        _settings = State(initialValue: set)
        _syncEngine = State(initialValue: SyncEngine(store: s, settings: set))
        // DIAGNOSTIC (temporary): record which branch the app took.
        try? "isUnitTestHost=\(isUnitTestHost)\n".write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("replog-branch.txt"),
            atomically: true, encoding: .utf8)
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
