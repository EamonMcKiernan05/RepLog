import Foundation
import SwiftData

/// Apply a parsed routine CSV to the store (owner request, 2026-10-23).
///
/// The rule: the FILE is the truth for the routines it names. An existing
/// routine with the same name is replaced wholesale (its exercise list is
/// rebuilt), because merging two lists leaves rows nobody asked for and makes a
/// re-import non-idempotent. Exercises are matched case-insensitively and are
/// created, with their category, only when they do not exist.
extension DataStore {

    struct RoutineImportSummary {
        var imported: [String] = []
        var replaced: [String] = []
        var createdExercises: [String] = []
        var createdCategories: [String] = []

        var isEmpty: Bool { imported.isEmpty }
    }

    @discardableResult
    func importRoutines(_ parsed: [RoutineCSV.ParsedRoutine]) -> RoutineImportSummary {
        var summary = RoutineImportSummary()
        let before = routines()

        for parsedRoutine in parsed {
            let routine: Routine
            if let match = before.first(where: {
                $0.name.caseInsensitiveCompare(parsedRoutine.name) == .orderedSame
            }) {
                // Replace: drop the old rows, keep the routine itself so its
                // name, target mode and anything else on it survive.
                for row in match.routineExercises { context.delete(row) }
                match.routineExercises.removeAll()
                routine = match
                summary.replaced.append(match.name)
            } else {
                routine = Routine(name: parsedRoutine.name,
                                  sortOrder: (before.map(\.sortOrder).max() ?? -1) + 1)
                context.insert(routine)
            }

            for (index, row) in parsedRoutine.exercises.enumerated() {
                let exercise = findOrCreateExercise(
                    named: row.exercise,
                    type: row.type,
                    categoryName: row.category,
                    summary: &summary
                )
                let entry = RoutineExercise(
                    exercise: exercise,
                    sortOrder: index,
                    warmupSets: row.warmupSets,
                    workingSets: row.workingSets,
                    notes: row.notes
                )
                routine.routineExercises.append(entry)
            }
            summary.imported.append(routine.name)
        }

        save()
        return summary
    }

    /// Case-insensitive match against the library; creates the exercise (and
    /// its category) when it is new.
    private func findOrCreateExercise(
        named name: String,
        type: String,
        categoryName: String,
        summary: inout RoutineImportSummary
    ) -> Exercise {
        if let existing = allExercises().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }

        var category: Category?
        if !categoryName.isEmpty {
            category = categories().first {
                $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
            }
            if category == nil {
                let created = Category(name: categoryName,
                                       sortOrder: (categories().map(\.sortOrder).max() ?? -1) + 1)
                context.insert(created)
                summary.createdCategories.append(categoryName)
                category = created
            }
        }

        let exercise = Exercise(
            name: name,
            type: type == "cardio" ? .cardio : .weightReps,
            category: category
        )
        context.insert(exercise)
        summary.createdExercises.append(name)
        return exercise
    }
}
