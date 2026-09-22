import Foundation
import SwiftData
import SwiftUI

/// All model mutation goes through DataStore (plan §4.1).
/// MainActor-isolated: it wraps the main context and is only used from views.
///
/// The container is created lazily on first access, not in init(). Creating it
/// in init() (i.e. at app launch) fails in the unit-test host context even for
/// an in-memory store; by the time the first view accesses it the app is fully
/// launched and creation succeeds. In the test host the UI is not exercised, so
/// it is never created there and the host app does not crash.
@MainActor
@Observable
final class DataStore {
    @ObservationIgnored private var _container: ModelContainer?
    @ObservationIgnored private let inMemory: Bool

    /// Static reference to the live main context, so value-type bindings
    /// (bodyweight) can record history without a view in scope.
    static var mainContextRef: ModelContext?

    var container: ModelContainer {
        if let c = _container { return c }
        let c = makeContainer()
        _container = c
        if !inMemory {
            DataStore.mainContextRef = c.mainContext
        }
        seedIfNeeded(with: c.mainContext)
        return c
    }

    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            Session.self, ExerciseEntry.self, SetEntry.self,
            Routine.self, RoutineExercise.self, Exercise.self,
            Category.self, BodyweightEntry.self,
        ])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(
                "RepLog", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: false
            )
        } else {
            // Explicit store URL in Application Support.
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            let dir = base.appendingPathComponent("RepLog", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            config = ModelConfiguration(
                "RepLog", schema: schema,
                url: dir.appendingPathComponent("RepLog.sqlite"),
                allowsSave: true
            )
        }
        if let ok = try? ModelContainer(for: schema, configurations: [config]) {
            return ok
        }
        // Last resort: an in-memory container so the app never crashes.
        let fallback = ModelConfiguration(
            "RepLog", schema: schema,
            isStoredInMemoryOnly: true, allowsSave: false
        )
        return (try? ModelContainer(for: schema, configurations: [fallback]))!
    }

    /// Load the exercise library from the bundled JSON on first run.
    private func seedIfNeeded(with context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0 else { return }

        let categories = loadJSON([SeedCategory].self, "SeedCategories") ?? []
        let exercises = loadJSON([SeedExercise].self, "SeedExercises") ?? []
        guard !exercises.isEmpty else { return }

        var catByName: [String: Category] = [:]
        for c in categories {
            let cat = Category(name: c.name, sortOrder: c.sortOrder)
            context.insert(cat)
            catByName[c.name] = cat
        }
        for (i, e) in exercises.enumerated() {
            let ex = Exercise(
                name: e.name,
                type: ExerciseType(rawValue: e.type) ?? .weightReps,
                singleLimb: SingleLimb(rawValue: e.singleLimb) ?? .defaultNo,
                bodyweightMultiplier: e.bodyweightMultiplier,
                builtin: e.builtin,
                sortOrder: i,
                category: catByName[e.category]
            )
            context.insert(ex)
        }
        try? context.save()
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Convenience queries

    func sessions() -> [Session] {
        let d = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    func routines() -> [Routine] {
        let d = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(d)) ?? []
    }

    func allExercises() -> [Exercise] {
        let d = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(d)) ?? []
    }

    func categories() -> [Category] {
        let d = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context.fetch(d)) ?? []
    }

    func exercise(named name: String) -> Exercise? {
        var d = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func save() {
        try? context.save()
    }
}

struct SeedCategory: Codable {
    let name: String
    let sortOrder: Int
}

struct SeedExercise: Codable {
    let name: String
    let category: String
    let type: String
    let singleLimb: String
    let builtin: Bool
    let bodyweightMultiplier: Double
}
