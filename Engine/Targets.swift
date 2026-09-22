import Foundation

/// Placeholder weight/reps resolution (plan §3.1, §6.2, article 39).
///
/// "Latest" (default): the last time you did the *exercise*, in any session.
/// "By Routine": the last time you did that *routine*.
/// Repeat-workout: "last performance" (targets) vs "exact weights from that
/// session" (article 22).
enum Targets {

    struct Placeholder {
        var weight: Double?
        var reps: Int?
        var rpe: Double?
    }

    /// Resolve the placeholder for one set of one exercise.
    ///
    /// `history` is the set history for the exercise, newest first, each
    /// item (weight, reps, rpe, routineName).
    static func placeholder(
        mode: TargetMode,
        routineName: String,
        setIndex: Int,
        history: [(weight: Double?, reps: Int?, rpe: Double?, routineName: String?)]
    ) -> Placeholder {
        let source: [(weight: Double?, reps: Int?, rpe: Double?, routineName: String?)]
        switch mode {
        case .latest:
            source = history
        case .byRoutine:
            source = history.filter { $0.routineName == routineName }
        }
        guard let entry = source.first else { return Placeholder() }
        return Placeholder(weight: entry.weight, reps: entry.reps, rpe: entry.rpe)
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
        guard let last = sessions
            .filter { $0.exerciseEntries.contains { $0.exercise?.name == exerciseName } }
            .max(by: { $0.date < $1.date })
        else { return [] }
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
