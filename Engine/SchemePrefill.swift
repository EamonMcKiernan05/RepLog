import Foundation

/// The one rule for turning a routine's stored scheme into a started workout's
/// set values.
///
/// A scheme row is `[weightKg, reps]`. Routine rows defaulted to `[0, 4]`
/// ("no weight, 4 reps"), and the pre-fill wrote that straight into the first
/// set: the owner saw a committed **0 kg x 4** sitting in a brand-new session,
/// which looks like data he entered and counts as a set in the metrics. A
/// scheme row with no weight is not a prescription, so it pre-fills nothing and
/// the row shows its placeholder instead.
enum SchemePrefill {

    /// The values a scheme row contributes to a set, or nil when it contributes
    /// nothing (missing row, no weight, or no reps).
    static func values(for row: [Double]?) -> (weightKg: Double, reps: Int)? {
        guard let row, row.count >= 2 else { return nil }
        let weight = row[0]
        let reps = Int(row[1])
        guard weight > 0, reps > 0 else { return nil }
        return (weight, reps)
    }

    /// How many set rows a routine exercise contributes when it is started
    /// (warm-up + working sets, never fewer than its scheme rows).
    static func setCount(warmupSets: Int, workingSets: Int, schemeRows: Int) -> Int {
        max(warmupSets + workingSets, schemeRows)
    }
}
