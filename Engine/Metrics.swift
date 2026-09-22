import Foundation

/// Pure metric functions (plan §4.1: metrics are pure functions with unit
/// tests, §11: Brzycki e1RM — RepCount's own worked example 100 kg × 5 →
/// 112.5 is Brzycki, not Epley's 116.7).
enum Metrics {

    // MARK: - e1RM

    /// Brzycki: weight × (1 + reps/30). 100 × 5 → 112.5.
    static func e1RM(weight: Double, reps: Int) -> Double? {
        guard reps >= 1, weight > 0 else { return nil }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    // MARK: - Volume

    /// Volume for one set, per exercise type (plan §3.1 #9, #17, #18).
    ///
    /// - weight_reps:        weight × reps
    /// - weight_time:        weight × (duration in minutes)
    /// - bw_weight_reps:     (bodyweight + added) × multiplier × reps
    /// - bw_assisted:        (bodyweight − assistance) × multiplier × reps
    /// - bw_reps:            bodyweight × multiplier × reps
    /// - bw_time:            bodyweight × multiplier × (duration in minutes)
    /// - cardio / note:      0 (no load)
    ///
    /// Single arm/leg doubles the result (article 46).
    static func setVolume(
        type: ExerciseType,
        weightKg: Double?,
        reps: Int?,
        durationS: Double?,
        bodyweightKg: Double?,
        multiplier: Double = 1.0,
        singleLimb: Bool = false
    ) -> Double {
        var v: Double = 0
        let bw = bodyweightKg ?? 0
        let minutes = (durationS ?? 0) / 60.0

        switch type {
        case .weightReps:
            v = (weightKg ?? 0) * Double(reps ?? 0)
        case .weightTime:
            v = (weightKg ?? 0) * minutes
        case .bwWeightReps:
            v = (bw + (weightKg ?? 0)) * multiplier * Double(reps ?? 0)
        case .bwAssisted:
            v = (bw - (weightKg ?? 0)) * multiplier * Double(reps ?? 0)
        case .bwReps:
            v = bw * multiplier * Double(reps ?? 0)
        case .bwTime:
            v = bw * multiplier * minutes
        case .cardio, .note:
            v = 0
        }
        if singleLimb { v *= 2 }
        return max(0, v)
    }

    /// Total volume for a session.
    static func sessionVolume(
        sets: [SetEntry],
        bodyweightKg: Double?,
        multiplier: (SetEntry) -> Double = { _ in 1.0 },
        singleLimb: (SetEntry) -> Bool = { _ in false },
        includeWarmup: Bool = false
    ) -> Double {
        sets
            .filter { includeWarmup || !$0.isWarmup }
            .map { s in
                setVolume(
                    type: s.exerciseEntry?.setType ?? .weightReps,
                    weightKg: s.weightKg,
                    reps: s.reps,
                    durationS: s.durationS,
                    bodyweightKg: bodyweightKg,
                    multiplier: multiplier(s),
                    singleLimb: singleLimb(s)
                )
            }
            .reduce(0, +)
    }

    // MARK: - Records

    /// Best e1RM for a given exact rep count (or nil).
    static func bestE1RM(sets: [SetEntry], reps: Int) -> Double? {
        sets
            .filter { $0.reps == reps && $0.weightKg != nil }
            .compactMap { e1RM(weight: $0.weightKg!, reps: $0.reps!) }
            .max()
    }

    /// Rep ranges used by the PR table: 1…10, then 11+.
    static let repRanges: [Int] = Array(1...10) + [11]

    static func rangeLabel(_ range: Int) -> String {
        range == 11 ? "11+" : "\(range)"
    }

    static func rangeMatches(_ range: Int, _ reps: Int) -> Bool {
        range == 11 ? reps >= 11 : range == reps
    }

    /// Best e1RM within a rep range.
    static func bestE1RM(sets: [SetEntry], inRange range: Int) -> Double? {
        sets
            .filter { rangeMatches(range, $0.reps ?? 0) && $0.weightKg != nil }
            .compactMap { e1RM(weight: $0.weightKg!, reps: $0.reps!) }
            .max()
    }

    /// Seasonal (per-year) best e1RM across all sets in a year.
    static func seasonalBest(
        sessions: [Session],
        year: Int,
        exerciseName: String,
        includeWarmup: Bool = false
    ) -> Double? {
        let sets = sessions
            .filter { Calendar.current.component(.year, from: $0.date) == year }
            .flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == exerciseName }
            .flatMap { $0.setEntries }
            .filter { includeWarmup || !$0.isWarmup }
        return sets
            .filter { $0.weightKg != nil && ($0.reps ?? 0) >= 1 }
            .compactMap { e1RM(weight: $0.weightKg!, reps: $0.reps!) }
            .max()
    }

    /// Session records for one exercise: max reps, max sets, max volume.
    static func sessionRecords(
        sessions: [Session],
        exerciseName: String,
        bodyweightFor: (Session) -> Double? = { _ in nil }
    ) -> SessionRecords? {
        var maxReps: (value: Int, session: Session)?
        var maxSets: (value: Int, session: Session)?
        var maxVolume: (value: Double, session: Session)?

        for session in sessions {
            let entries = session.exerciseEntries
                .filter { $0.exercise?.name == exerciseName }
            guard !entries.isEmpty else { continue }

            let allSets = entries.flatMap { $0.setEntries }
            let reps = allSets.compactMap { $0.reps }.max() ?? 0
            let sets = entries.count
            let volume = entries.flatMap { $0.setEntries }.reduce(0.0) { acc, s in
                acc + setVolume(
                    type: s.exerciseEntry?.setType ?? .weightReps,
                    weightKg: s.weightKg, reps: s.reps, durationS: s.durationS,
                    bodyweightKg: bodyweightFor(session)
                )
            }

            if maxReps == nil || reps > maxReps!.value { maxReps = (reps, session) }
            if maxSets == nil || sets > maxSets!.value { maxSets = (sets, session) }
            if maxVolume == nil || volume > maxVolume!.value { maxVolume = (volume, session) }
        }
        guard maxReps != nil else { return nil }
        return SessionRecords(
            maxReps: maxReps!,
            maxSets: maxSets!,
            maxVolume: maxVolume!
        )
    }
}

struct SessionRecords {
    let maxReps: (value: Int, session: Session)
    let maxSets: (value: Int, session: Session)
    let maxVolume: (value: Double, session: Session)
}
