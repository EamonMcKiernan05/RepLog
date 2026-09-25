import Foundation

/// Placeholder weight/reps resolution (plan §3.1, §6.2, article 39).
///
/// "Latest" (default): the last time you did the *exercise*, in any session.
/// "By Routine": the last time you did that *routine*.
/// Repeat-workout: "last performance" (targets) vs "exact weights from that
/// session" (article 22).
enum Targets {

    /// What one empty box shows behind it: the previous value as TEXT, for a
    /// box that is empty and has nothing typed in it.
    ///
    /// This is a hint, never a value. It is drawn by the cell, is not
    /// hit-testable, and never reaches the model — an untouched box stays
    /// empty, so a workout records what was actually done and nothing that was
    /// merely suggested (owner, 2026-09-25: "this should only be visible while
    /// the box is empty and not interactable"). The old behaviour wrote the
    /// previous values INTO new sets, which is how a session ended up
    /// recording "0 kg x 4" that nobody entered.
    struct Hints {
        var weight = ""
        var reps = ""
        var rpe = ""
        var notes = ""

        static let none = Hints()
        var isEmpty: Bool { weight.isEmpty && reps.isEmpty && rpe.isEmpty && notes.isEmpty }
    }

    /// A past set, as the hint resolver needs it.
    struct PastSet {
        var exerciseName: String
        var sessionDate: Date
        var routineName: String?
        var setNumber: Int
        var weightKg: Double?
        var reps: Int?
        var rpe: Double?
        var notes: String

        /// A set with nothing in it was not done, so it is not "last time".
        /// Without this, opening a workout and walking away from it would blank
        /// the hints for that exercise.
        var hasValue: Bool {
            weightKg != nil || reps != nil || rpe != nil
                || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// One `Hints` per set of one exercise, index 0 = set 1.
    ///
    /// The source follows the routine's own "weight and reps" setting: with
    /// `.latest` it is the last session that contains the exercise whatever it
    /// was; with `.byRoutine` it is the last session of THIS routine (owner,
    /// 2026-09-25). Within that session the value at the SAME set index is
    /// used, and a workout with more sets than last time repeats its last set —
    /// the reference app's rule.
    static func hints(
        mode: TargetMode,
        routineName: String,
        exerciseName: String,
        history: [PastSet],
        unit: WeightUnit,
        setCount: Int
    ) -> [Hints] {
        guard setCount > 0 else { return [] }
        let mine = history.filter { $0.exerciseName == exerciseName && $0.hasValue }
        let matching = mode == .byRoutine
            ? mine.filter { $0.routineName == routineName }
            : mine
        guard let newest = matching.map({ $0.sessionDate }).max() else { return [] }
        let last = matching
            .filter { $0.sessionDate == newest }
            .sorted { $0.setNumber < $1.setNumber }
        guard !last.isEmpty else { return [] }

        return (0..<setCount).map { index in
            let past = last[min(index, last.count - 1)]
            var hint = Hints()
            if let kg = past.weightKg {
                let v = unit.convert(fromKg: kg)
                hint.weight = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
            }
            if let reps = past.reps { hint.reps = String(reps) }
            if let rpe = past.rpe { hint.rpe = rpeText(rpe) }
            hint.notes = past.notes
            return hint
        }
    }

    /// RPE reads as `8`, never `8.0` (plan §3.2). Lives here so the cells, the
    /// chips and the hints all format it the same way.
    static func rpeText(_ v: Double) -> String {
        let tenths = Int((v * 10).rounded())
        if tenths % 10 == 0 {
            return String(tenths / 10)
        }
        return String(format: "%.1f", v)
    }

    /// Repeat-workout: the exact sets from a source session for an exercise.
    static func exactSets(
        from source: Session,
        exerciseName: String
    ) -> [(weight: Double?, reps: Int?, rpe: Double?)] {
        source.exerciseEntries
            .filter { $0.exercise?.name == exerciseName }
            .flatMap { $0.setEntries }
            .map { ($0.weightKg, $0.reps, $0.rpe) }
    }

    /// Repeat-workout: latest-performance targets for a set count.
    static func latestPerformance(
        for exerciseName: String,
        setCount: Int,
        sessions: [Session]
    ) -> [(weight: Double?, reps: Int?)] {
        // Find the most recent session that contains the exercise.
        // (Temp var: guard conditions cannot contain trailing closures.)
        let matching = sessions.filter {
            $0.exerciseEntries.contains { $0.exercise?.name == exerciseName }
        }
        guard let last = matching.max(by: { $0.date < $1.date }) else { return [] }
        let sets = last.exerciseEntries
            .filter { $0.exercise?.name == exerciseName }
            .flatMap { $0.setEntries }
            .map { ($0.weightKg, $0.reps) }
        // Tile the last session's sets to fill the requested count.
        return (0..<setCount).map { i in
            sets.indices.contains(i) ? sets[i] : sets.last ?? (nil, nil)
        }
    }
}
