import Foundation
import SwiftData

// MARK: - Exercise library

@Model
final class Category {
    @Attribute(.unique) var name: String
    var sortOrder: Int
    @Relationship(deleteRule: .nullify, inverse: \Exercise.category)
    var exercises: [Exercise] = []

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var name: String
    var typeRaw: String
    var singleLimbRaw: String
    var bodyweightMultiplier: Double
    var builtin: Bool
    var sortOrder: Int
    var category: Category?

    init(name: String, type: ExerciseType, singleLimb: SingleLimb = .defaultNo,
         bodyweightMultiplier: Double = 1.0, builtin: Bool = false,
         sortOrder: Int = 0, category: Category? = nil) {
        self.name = name
        self.typeRaw = type.rawValue
        self.singleLimbRaw = singleLimb.rawValue
        self.bodyweightMultiplier = bodyweightMultiplier
        self.builtin = builtin
        self.sortOrder = sortOrder
        self.category = category
    }

    var type: ExerciseType {
        get { ExerciseType(rawValue: typeRaw) ?? .weightReps }
        set { typeRaw = newValue.rawValue }
    }

    var singleLimb: SingleLimb {
        get { SingleLimb(rawValue: singleLimbRaw) ?? .defaultNo }
        set { singleLimbRaw = newValue.rawValue }
    }

    /// Effective single-limb doubling, given the global setting.
    func isSingleLimb(globalDefault: Bool) -> Bool {
        switch singleLimb {
        case .yes: true
        case .no: false
        case .defaultNo: globalDefault
        }
    }
}

// MARK: - Sessions

@Model
final class Session {
    @Attribute(.unique) var id: String          // stable UUID string
    var date: Date                               // start of day (local)
    var startTime: Date?
    var endTime: Date?
    var bodyweightKg: Double?
    var notes: String
    var routineName: String
    var syncStateRaw: String
    var createdAt: Date
    var exercises: [ExerciseEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session)
    var exerciseEntries: [ExerciseEntry] = []

    init(id: String = UUID().uuidString, date: Date = .now,
         routineName: String = "") {
        self.id = id
        self.date = date
        self.routineName = routineName
        self.notes = ""
        self.syncStateRaw = SyncState.local.rawValue
        self.createdAt = .now
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    var duration: TimeInterval {
        guard let s = startTime, let e = endTime else { return 0 }
        return e.timeIntervalSince(s)
    }

    var durationText: String {
        let m = Int(duration / 60)
        if m < 1 { return "<1 min" }
        return "\(m) min"
    }

    /// Up to three "Nx Exercise" summary lines for the Log row.
    var summaryLines: [String] {
        exerciseEntries.prefix(3).map { entry in
            // setEntries is the relationship the app populates (entry.sets is
            // a dead duplicate array that is never written to).
            let n = entry.setEntries.count
            return "\(n)x \(entry.exercise?.name ?? "Exercise")"
        }
    }

    /// Accessibility label for the Log row. It belongs on the row BUTTON
    /// (LogTabView), never combined inside the button's label view — see
    /// SessionRowView for why.
    var rowAccessibilityText: String {
        let dateText = date.formatted(.dateTime.weekday(.wide).day().month())
        let name = routineName.isEmpty ? "Workout" : routineName
        // An open workout has no duration yet: say so rather than "<1 min".
        let tail = endTime == nil ? "In progress" : durationText
        return "\(dateText), \(name), \(summaryLines.joined(separator: ", ")), \(tail)"
    }
}

@Model
final class ExerciseEntry {
    var session: Session?
    var exercise: Exercise?
    var sortOrder: Int
    var supersetId: String?
    /// Vestigial, like `RoutineExercise.schemeJSON`: nothing reads or writes
    /// it since the planned-scheme concept went (owner, 2026-09-24).
    var plannedScheme: String? = nil
    var notes: String
    var unitOverrideRaw: String?      // per-exercise kg/lb override
    var sets: [SetEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.exerciseEntry)
    var setEntries: [SetEntry] = []

    init(exercise: Exercise?, sortOrder: Int, supersetId: String? = nil) {
        self.exercise = exercise
        self.sortOrder = sortOrder
        self.supersetId = supersetId
        self.notes = ""
    }

    var unitOverride: WeightUnit? {
        get { unitOverrideRaw.flatMap(WeightUnit.init(rawValue:)) }
        set { unitOverrideRaw = newValue?.rawValue }
    }

    var setType: ExerciseType { exercise?.type ?? .weightReps }

    /// Display unit for this entry, given the global unit.
    func displayUnit(global: WeightUnit) -> WeightUnit {
        unitOverride ?? global
    }
}

@Model
final class SetEntry {
    var exerciseEntry: ExerciseEntry?
    var setNumber: Int
    var weightKg: Double?
    var reps: Int?
    var rpe: Double?
    var durationS: Double?
    var distanceM: Double?
    var kcal: Double?
    var setTypeRaw: String
    var notes: String
    var sortOrder: Int

    init(setNumber: Int, setType: SetType = .working) {
        self.setNumber = setNumber
        self.setTypeRaw = setType.rawValue
        self.notes = ""
        self.sortOrder = setNumber
    }

    var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .working }
        set { setTypeRaw = newValue.rawValue }
    }

    var isDrop: Bool { setType == .drop }
    var isWarmup: Bool { setType == .warmup }
}

// MARK: - Routines

@Model
final class Routine {
    @Attribute(.unique) var name: String
    var targetModeRaw: String
    var notes: String
    var sortOrder: Int
    var exercises: [RoutineExercise] = []

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var routineExercises: [RoutineExercise] = []

    init(name: String, sortOrder: Int = 0) {
        self.name = name
        self.targetModeRaw = TargetMode.latest.rawValue
        self.notes = ""
        self.sortOrder = sortOrder
    }

    var targetMode: TargetMode {
        get { TargetMode(rawValue: targetModeRaw) ?? .latest }
        set { targetModeRaw = newValue.rawValue }
    }
}

@Model
final class RoutineExercise {
    var routine: Routine?
    var exercise: Exercise?
    var sortOrder: Int
    var warmupSets: Int
    var workingSets: Int
    /// Vestigial. A routine exercise used to carry a set SCHEME
    /// ([[weightKg, reps], ...]) that pre-filled the first sets of a new
    /// session. The owner removed the concept on 2026-09-24: an exercise in a
    /// routine is a number of sets and a note, nothing else. Nothing reads or
    /// writes this. The column stays so the store's schema is unchanged for
    /// installs that already hold data — dropping it would need a migration
    /// for no gain.
    var schemeJSON: String = "[]"
    var notes: String

    init(exercise: Exercise?, sortOrder: Int, warmupSets: Int = 0,
         workingSets: Int = 4, notes: String = "") {
        self.exercise = exercise
        self.sortOrder = sortOrder
        self.warmupSets = warmupSets
        self.workingSets = workingSets
        self.notes = notes
    }
}

// MARK: - Identifiable for SwiftUI ForEach / navigation
// SwiftData's PersistentModel does not conform to Identifiable in this SDK,
// so the views need an explicit id. Session already has `var id: String`.
extension Session: Identifiable {}
extension Exercise: Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}
extension Category: Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}
extension Routine: Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}
extension RoutineExercise: Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}
extension SetEntry: Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}

// MARK: - Bodyweight history

@Model
final class BodyweightEntry {
    @Attribute(.unique) var date: Date
    var weightKg: Double

    init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}
