import SwiftUI
import SwiftData

@main
struct RepLogApp: App {
    @State private var store: DataStore
    @State private var settings: Settings
    @State private var router = AppRouter()
    @State private var syncEngine: SyncEngine

    init() {
        // Build the store first so the engine can reference it.
        let s = DataStore()
        let set = Settings()
        _store = State(initialValue: s)
        _settings = State(initialValue: set)
        _syncEngine = State(initialValue: SyncEngine(store: s, settings: set))
    }

    var body: some Scene {
        WindowGroup {
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
        .modelContainer(store.container)
    }
}
