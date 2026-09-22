import Testing
import Foundation
@testable import RepLog

@Suite("Metrics")
struct MetricsTests {
    @Test("Brzycki e1RM: 100kg x 5 -> 112.5")
    func e1RMBrzycki() {
        let v5 = Metrics.e1RM(weight: 100, reps: 5)
        let v4 = Metrics.e1RM(weight: 140, reps: 4)
        let v5b = Metrics.e1RM(weight: 85, reps: 5)
        #expect(v5 != nil)
        #expect(v4 != nil)
        #expect(v5b != nil)
        // Brzycki: weight * 36 / (37 - reps)
        let expected5 = 100.0 * 36.0 / 32.0   // 112.5
        let expected4 = 140.0 * 36.0 / 33.0
        let expected5b = 85.0 * 36.0 / 32.0
        let d5 = abs(v5! - expected5)
        let d4 = abs(v4! - expected4)
        let d5b = abs(v5b! - expected5b)
        #expect(d5 < 0.001)
        #expect(d4 < 0.001)
        #expect(d5b < 0.001)
    }

    @Test("e1RM nil for 0 reps or 0 weight")
    func e1RMNil() {
        let a = Metrics.e1RM(weight: 100, reps: 0)
        let b = Metrics.e1RM(weight: 0, reps: 5)
        #expect(a == nil)
        #expect(b == nil)
    }

    @Test("volume: weight_reps = weight x reps")
    func volumeWeightReps() {
        let v = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                  durationS: nil, bodyweightKg: nil)
        #expect(v == 500)
    }

    @Test("volume: weight_time = weight x minutes")
    func volumeWeightTime() {
        let v = Metrics.setVolume(type: .weightTime, weightKg: 100, reps: nil,
                                  durationS: 120, bodyweightKg: nil)
        #expect(v == 200)
    }

    @Test("volume: bw_weight_reps = (bw + added) x multiplier x reps")
    func volumeBWWeightReps() {
        let v = Metrics.setVolume(type: .bwWeightReps, weightKg: 10, reps: 5,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == 450)
    }

    @Test("volume: bw_assisted = (bw - assistance) x multiplier x reps")
    func volumeBWAssisted() {
        let v = Metrics.setVolume(type: .bwAssisted, weightKg: 20, reps: 5,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == 300)
    }

    @Test("volume: bw_reps = bw x multiplier x reps")
    func volumeBWReps() {
        let v = Metrics.setVolume(type: .bwReps, weightKg: nil, reps: 10,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == 800)
    }

    @Test("volume: bodyweight multiplier applies")
    func volumeMultiplier() {
        let v = Metrics.setVolume(type: .bwReps, weightKg: nil, reps: 10,
                                  durationS: nil, bodyweightKg: 80, multiplier: 0.5)
        #expect(v == 400)
    }

    @Test("volume: single limb doubles")
    func volumeSingleLimb() {
        let normal = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                       durationS: nil, bodyweightKg: nil)
        let single = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                       durationS: nil, bodyweightKg: nil, singleLimb: true)
        #expect(single == normal * 2)
    }

    @Test("volume: cardio and note are zero")
    func volumeZeroTypes() {
        let cardio = Metrics.setVolume(type: .cardio, weightKg: nil, reps: nil,
                                       durationS: 600, bodyweightKg: 80)
        let note = Metrics.setVolume(type: .note, weightKg: 10, reps: 5,
                                     durationS: nil, bodyweightKg: nil)
        #expect(cardio == 0)
        #expect(note == 0)
    }

    @Test("bestE1RM per exact rep count")
    func bestE1RMExact() {
        let sets = makeSets([(100, 5), (110, 5), (90, 3)])
        let b5 = Metrics.bestE1RM(sets: sets, reps: 5)
        let b3 = Metrics.bestE1RM(sets: sets, reps: 3)
        let b7 = Metrics.bestE1RM(sets: sets, reps: 7)
        #expect(b7 == nil)
        #expect(b5 != nil)
        #expect(b3 != nil)
        // Brzycki: weight * 36 / (37 - reps)
        let exp5 = 110.0 * 36.0 / 32.0
        let exp3 = 90.0 * 36.0 / 34.0
        #expect(abs(b5! - exp5) < 0.001)
        #expect(abs(b3! - exp3) < 0.001)
    }

    @Test("bestE1RM in range 11+ picks max reps>=11")
    func bestE1RMRange() {
        let sets = makeSets([(60, 12), (55, 15)])
        let best = Metrics.bestE1RM(sets: sets, inRange: 11)
        #expect(best != nil)
        #expect(best! > 0)
    }

    // Helper: build SetEntry graph for a single exercise.
    private func makeSets(_ pairs: [(Double, Int)]) -> [SetEntry] {
        let ex = Exercise(name: "Test", type: .weightReps)
        let entry = ExerciseEntry(exercise: ex, sortOrder: 0)
        return pairs.enumerated().map { i, p in
            let s = SetEntry(setNumber: i + 1)
            s.weightKg = p.0
            s.reps = p.1
            s.exerciseEntry = entry
            return s
        }
    }
}
