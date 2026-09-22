import Foundation
import HealthKit

/// Apple Health integration (plan §3.1 line 19):
///  - WRITE: finished workouts (HKWorkout) + bodyweight (HKQuantityType(.bodyMass))
///  - READ:  latest bodyweight, to prefill the session bodyweight field
/// The active-energy calorie estimate is deliberately NOT implemented (out of
/// scope for this run — see docs/BUILD-REPORT.md); writing it would require
/// sex/height/DOB read permissions and a corrected-MET model.
///
/// SDK notes (verified against the Xcode 26.5 SDK, 2026-09-22):
///  - The strength-training activity type is `.functionalStrengthTraining`
///    (there is no `.strengthTraining` case).
///  - `HKWorkoutType()` is unavailable — use `HKObjectType.workoutType()`.
///  - The async sample query is `HKSampleQueryDescriptor<HKQuantitySample>`
///    with `predicates:` (plural, `[HKSamplePredicate<HKQuantitySample>]`
///    built via `.quantitySample(type:predicate:)`) and `SortDescriptor`;
///    `result(for:)` returns the sample array directly.
///  - The `HKWorkout(...)` initialiser is deprecated (iOS 17) — workouts are
///    built with `HKWorkoutBuilder` (beginCollection -> endCollection ->
///    finishWorkout).
@MainActor
final class HealthService {
    private let store = HKHealthStore()
    private(set) var isAvailable = false

    init() {
        isAvailable = HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKQuantityType> {
        [HKQuantityType(.bodyMass)]
    }

    private var writeTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass) as HKSampleType,
            HKObjectType.workoutType() as HKSampleType,
        ]
    }

    /// Ask for the permissions we use. Returns whether authorization succeeded.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// The most recently recorded bodyweight, if any.
    func latestBodyweightKg() async -> Double? {
        guard isAvailable else { return nil }
        let type: HKQuantityType = HKQuantityType(.bodyMass)
        let predicates: [HKSamplePredicate<HKQuantitySample>] = [
            .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: nil)),
        ]
        let sort = SortDescriptor(\HKQuantitySample.endDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: predicates,
            sortDescriptors: [sort],
            limit: 1
        )
        do {
            let samples = try await descriptor.result(for: store)
            guard let sample = samples.first else { return nil }
            let unit: HKUnit = .gramUnit(with: .kilo)
            return sample.quantity.doubleValue(for: unit)
        } catch {
            return nil
        }
    }

    /// Record a bodyweight sample (called from the session bodyweight field).
    func saveBodyweight(kg: Double, date: Date = .now) async -> Bool {
        guard isAvailable else { return false }
        let type: HKQuantityType = HKQuantityType(.bodyMass)
        let unit: HKUnit = .gramUnit(with: .kilo)
        let quantity = HKQuantity(unit: unit, doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    /// Write a finished workout to Health (type inferred from the exercises).
    func saveWorkout(session: Session) async -> Bool {
        guard isAvailable else { return false }
        let start = session.startTime ?? session.date
        let end = session.endTime ?? .now
        guard end > start else { return false }

        let config = HKWorkoutConfiguration()
        config.activityType = workoutActivityType(for: session)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    /// Map the session's exercise names to a workout activity type
    /// (best-effort; Health groups the workout under it).
    private func workoutActivityType(for session: Session) -> HKWorkoutActivityType {
        var names = Set<String>()
        for entry in session.exerciseEntries {
            if let n = entry.exercise?.name { names.insert(n.lowercased()) }
        }
        func has(_ keywords: [String]) -> Bool {
            names.contains { n in keywords.contains { n.contains($0) } }
        }
        if has(["run", "sprint", "treadmill"]) { return .running }
        if has(["bike", "cycle", "cycling"]) { return .cycling }
        if has(["swim"]) { return .swimming }
        if has(["yoga"]) { return .yoga }
        if has(["abs", "core", "plank", "crunch"]) { return .coreTraining }
        return .functionalStrengthTraining
    }
}
