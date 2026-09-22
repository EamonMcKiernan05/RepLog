import Foundation
import SwiftData
import SwiftUI

/// All model mutation goes through DataStore (plan §4.1).
/// MainActor-isolated: it wraps the main context and is only used from views.
@MainActor
@Observable
final class DataStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    /// Static reference to the live main context, so value-type bindings
    /// (bodyweight) can record history without a view in scope.
    static var mainContextRef: ModelContext?

    init(inMemory: Bool = false) {
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
            // Explicit store URL in Application Support. Relying on SwiftData's
            // default URL resolves to /dev/null when the app runs as a unit-test
            // host, which crashes the host and fails the whole run. An explicit
            // path is valid in both the real app and the test host.
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
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // In the test-host context a store failure must not crash the host
            // (the unit tests use their own in-memory store). Fall back to an
            // in-memory container so the host app stays alive.
            let fallback = ModelConfiguration(
                "RepLog", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: false
            )
            if let mem = try? ModelContainer(for: schema, configurations: [fallback]) {
                container = mem
            } else {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
        if !inMemory {
            // App.init runs on the main thread.
            DataStore.mainContextRef = container.mainContext
        }
        seedIfNeeded()
    }

    /// Load the exercise library from the bundled JSON on first run.
    private func seedIfNeeded() {
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
