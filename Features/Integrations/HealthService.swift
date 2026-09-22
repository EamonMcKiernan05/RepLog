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
///  - The async sample query is `HKSampleQueryDescriptor` with `predicates:`
///    (plural, `[HKSamplePredicate<HKSample>]`) and `SortDescriptor` — not the
///    older `predicate:`/`NSSortDescriptor` pair.
///  - `HKQuantityType(.bodyMass)` and `HKUnit.gramUnit(with: .kilo)` need an
///    explicit contextual type at the call site.
///  - The `HKWorkout` initialiser takes (activityType, start, end,
///    totalDistance, totalEnergyBurned, totalAscent, totalDescent,
///    numberOfPullUps, numberOfPushUps, numberOfSitUps,
///    numberOfFlightsClimbed, route, totalSwimmingStrokeCount, device,
///    workoutEvents, metadata, activities) — `workoutEvents` and `metadata`
///    are required.
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
            HKWorkoutType() as HKSampleType,
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
        let predicates: [HKSamplePredicate<HKSample>] = [
            .samples(with: type, predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: nil)),
        ]
        let sort = SortDescriptor(\HKSample.endDate, order: .reverse)
        let descriptor = HKSampleQueryDescriptor(
            predicates: predicates,
            sortDescriptors: [sort],
            limit: 1
        )
        do {
            let result = try await descriptor.result(for: store)
            guard let sample = result.samples.first as? HKQuantitySample else { return nil }
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

        let activities: [HKWorkoutActivityType] = workoutActivities(for: session)
        let workout = HKWorkout(
            activityType: .other,
            start: start,
            end: end,
            totalDistance: nil,
            totalEnergyBurned: nil,   // active-energy estimate is out of scope
            totalAscent: nil,
            totalDescent: nil,
            numberOfPullUps: nil,
            numberOfPushUps: nil,
            numberOfSitUps: nil,
            numberOfFlightsClimbed: nil,
            route: nil,
            totalSwimmingStrokeCount: nil,
            device: nil,
            workoutEvents: [],
            metadata: nil,
            activities: activities
        )
        do {
            try await store.save(workout)
            return true
        } catch {
            return false
        }
    }

    /// Map the session's exercise names to a small set of workout activity
    /// types (best-effort; Health groups the workout under these).
    private func workoutActivities(for session: Session) -> [HKWorkoutActivityType] {
        var names = Set<String>()
        for entry in session.exerciseEntries {
            if let n = entry.exercise?.name { names.insert(n.lowercased()) }
        }
        var result: [HKWorkoutActivityType] = []
        func add(_ t: HKWorkoutActivityType, _ keywords: [String]) {
            if names.contains(where: { n in keywords.contains(where: { n.contains($0) }) }) {
                result.append(t)
            }
        }
        add(.running, ["run", "sprint", "treadmill"])
        add(.cycling, ["bike", "cycle", "cycling"])
        add(.swimming, ["swim"])
        add(.yoga, ["yoga"])
        add(.coreTraining, ["abs", "core", "plank", "crunch"])
        add(.functionalStrengthTraining, ["squat", "bench", "deadlift", "press", "curl", "row", "pulldown", "dip", "leg", "shoulder", "fly", "raise", "extension", "triceps", "bicep"])
        return result.isEmpty ? [.functionalStrengthTraining] : result
    }
}
