import Foundation
import SwiftData

/// In-app importer (plan §4.5.4, T8.3): read a new-schema sync CSV from the
/// Files app and rebuild sessions in a fresh phone's store.
///
/// The legacy RepCount 7-column export is converted first by
/// `scripts/repcount_import.py` (the one-time migration); this importer
/// reads the frozen new schema that script (and the sync service) produce.
enum Importer {
    struct Result {
        var sessions: Int
        var sets: Int
        var errors: [String]
    }

    /// Parse `text` (new-schema CSV) and insert sessions into `context`.
    /// Exercises are matched by name; missing ones are created in a
    /// "Imported" category so nothing is lost.
    @MainActor
    static func importCSV(_ text: String, into context: ModelContext) -> Result {
        var errors: [String] = []
        let parsed: [CSVCodec.ParsedSet]
        do {
            parsed = try CSVCodec.parse(text)
        } catch {
            return Result(sessions: 0, sets: 0, errors: ["Could not parse CSV: \(error)"])
        }

        // Group by session id, preserving order.
        var order: [String] = []
        var bySession: [String: [CSVCodec.ParsedSet]] = [:]
        for set in parsed {
            if bySession[set.sessionID] == nil { order.append(set.sessionID) }
            bySession[set.sessionID, default: []].append(set)
        }

        // Resolve / create categories and exercises.
        var catCache: [String: Category] = [:]
        func category(_ name: String) -> Category? {
            let key = name.isEmpty ? "Imported" : name
            if let c = catCache[key] { return c }
            var d = FetchDescriptor<Category>(predicate: #Predicate { $0.name == key })
            d.fetchLimit = 1
            if let existing = try? context.fetch(d).first {
                catCache[key] = existing
                return existing
            }
            let c = Category(name: key, sortOrder: 0)
            context.insert(c)
            catCache[key] = c
            return c
        }
        var exCache: [String: Exercise] = [:]
        func exercise(_ name: String, cat: String, type: String) -> Exercise? {
            if let e = exCache[name] { return e }
            var d = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
            d.fetchLimit = 1
            if let existing = try? context.fetch(d).first {
                exCache[name] = existing
                return existing
            }
            let e = Exercise(
                name: name,
                type: ExerciseType(rawValue: type) ?? .weightReps,
                category: category(cat)
            )
            context.insert(e)
            exCache[name] = e
            return e
        }

        // Build sessions.
        var sessionCount = 0
        var setCount = 0
        for sid in order {
            guard let sets = bySession[sid], let first = sets.first else { continue }
            guard let date = CSVCodec.dateFormat.date(from: first.date) else {
                errors.append("session \(sid): bad date \(first.date)")
                continue
            }
            let session = Session(id: sid, date: date)
            if !first.startTime.isEmpty, let t = CSVCodec.timeFormat.date(from: first.startTime) {
                session.startTime = t
            }
            if !first.endTime.isEmpty, let t = CSVCodec.timeFormat.date(from: first.endTime) {
                session.endTime = t
            }
            if let bw = first.bodyweightKg { session.bodyweightKg = bw }
            context.insert(session)

            // Group sets by exercise (in order of appearance).
            var entryOrder: [String] = []
            var byExercise: [String: [CSVCodec.ParsedSet]] = [:]
            for set in sets {
                if byExercise[set.exercise] == nil { entryOrder.append(set.exercise) }
                byExercise[set.exercise, default: []].append(set)
            }
            var sortOrder = 0
            for exName in entryOrder {
                guard let exSets = byExercise[exName], let firstSet = exSets.first else { continue }
                guard let ex = exercise(exName, cat: firstSet.category, type: firstSet.exerciseType) else {
                    errors.append("session \(sid): could not create exercise \(exName)")
                    continue
                }
                let entry = ExerciseEntry(exercise: ex, sortOrder: sortOrder,
                                          supersetId: firstSet.supersetID.isEmpty ? nil : firstSet.supersetID)
                for set in exSets {
                    let se = SetEntry(setNumber: set.setNumber,
                                      setType: SetType(rawValue: set.setType) ?? .working)
                    se.weightKg = set.weightKg
                    se.reps = set.reps
                    se.rpe = set.rpe
                    se.durationS = set.durationS
                    se.distanceM = set.distanceM
                    se.kcal = set.kcal
                    se.notes = set.notes
                    entry.setEntries.append(se)
                    setCount += 1
                }
                session.exerciseEntries.append(entry)
                sortOrder += 1
            }
            sessionCount += 1
        }
        try? context.save()
        return Result(sessions: sessionCount, sets: setCount, errors: errors)
    }
}
