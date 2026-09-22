import Foundation

// MARK: - Enums (frozen vocabulary — plan §4.4)

/// The eight exercise types (RepCount article 63).
enum ExerciseType: String, Codable, CaseIterable, Sendable {
    // Strength
    case weightReps = "weight_reps"
    case weightTime = "weight_time"
    // Bodyweight
    case bwWeightReps = "bw_weight_reps"
    case bwAssisted = "bw_assisted"
    case bwReps = "bw_reps"
    case bwTime = "bw_time"
    // Cardio
    case cardio = "cardio"
    // Other
    case note = "note"

    var displayName: String {
        switch self {
        case .weightReps: "Strength — Weight, Reps"
        case .weightTime: "Strength — Weight, Time"
        case .bwWeightReps: "Bodyweight — Weight, Reps (BW+)"
        case .bwAssisted: "Bodyweight — Assisted, Reps (BW−)"
        case .bwReps: "Bodyweight — Reps"
        case .bwTime: "Bodyweight — Time"
        case .cardio: "Cardio — Time, Distance, Calories"
        case .note: "Other — Note per set"
        }
    }

    var group: String {
        switch self {
        case .weightReps, .weightTime: "Strength"
        case .bwWeightReps, .bwAssisted, .bwReps, .bwTime: "Bodyweight"
        case .cardio: "Cardio"
        case .note: "Other"
        }
    }

    /// Whether the set row shows a weight cell.
    var hasWeight: Bool {
        switch self {
        case .weightReps, .weightTime, .bwWeightReps, .bwAssisted: true
        default: false
        }
    }

    /// Whether the set row shows a reps cell.
    var hasReps: Bool {
        switch self {
        case .weightReps, .bwWeightReps, .bwAssisted, .bwReps: true
        default: false
        }
    }

    /// Whether the set row shows a time (duration) cell.
    var hasTime: Bool {
        switch self {
        case .weightTime, .bwTime, .cardio: true
        default: false
        }
    }

    /// Whether bodyweight × multiplier drives volume maths.
    var usesBodyweight: Bool {
        switch self {
        case .bwWeightReps, .bwAssisted, .bwReps, .bwTime: true
        default: false
        }
    }

    /// Whether the set row shows distance + kcal cells.
    var hasCardioExtras: Bool { self == .cardio }

    /// Whether RPE applies to this type.
    var hasRPE: Bool { self != .cardio && self != .note }
}

enum SetType: String, Codable, Sendable {
    case working = "working"
    case warmup = "warmup"
    case drop = "drop"
}

/// Outbox state machine (plan §4.3).
enum SyncState: String, Codable, Sendable {
    case local      // never uploaded
    case queued     // finished offline, waiting
    case uploaded   // server has the current version
    case dirty      // edited after upload, re-post needed
    case failed     // last attempt failed, will retry
}

enum SingleLimb: String, Codable, Sendable {
    case defaultNo = "default_no"
    case yes = "yes"
    case no = "no"

    var label: String {
        switch self {
        case .defaultNo: "Default (No)"
        case .yes: "Yes"
        case .no: "No"
        }
    }
}

enum TargetMode: String, Codable, Sendable {
    case latest = "Latest"
    case byRoutine = "By Routine"
}

enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg, lb

    var display: String { rawValue }

    /// kg -> display unit.
    func convert(fromKg kg: Double) -> Double {
        self == .kg ? kg : kg * 2.2046226218
    }

    /// display unit -> kg (storage stays kg).
    func toKg(_ value: Double) -> Double {
        self == .kg ? value : value / 2.2046226218
    }
}

/// Repeat-workout choice (article 22).
enum RepeatMode: String, Codable, Sendable {
    case lastPerformance = "Last performance"
    case exactWeights = "Exact weights from that session"
}
