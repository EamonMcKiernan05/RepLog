import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    @State private var store: DataStore
    @State private var settings: Settings
    @State private var router = AppRouter()
    @State private var syncEngine: SyncEngine

    /// True when running as the host for a unit-test bundle. The unit tests are
    /// pure logic (metrics, codec, targets, outbox, importer) and create their
    /// own in-memory stores; they never look at the app UI. In that context the
    /// simulator's data container is not ready at app launch, so creating a
    /// SwiftData store (even in-memory) fails. Rendering a placeholder instead
    /// of the real UI means the store is never touched and the host does not
    /// crash.
    private let isUnitTestHost: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        let s = DataStore()
        let set = Settings()
        _store = State(initialValue: s)
        _settings = State(initialValue: set)
        _syncEngine = State(initialValue: SyncEngine(store: s, settings: set))
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let line = "isUnitTestHost=\(isUnitTestHost) envKey=\(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)\n"
        try? line.write(to: docs?.appendingPathComponent("replog-diag.txt"), atomically: true, encoding: .utf8)
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
