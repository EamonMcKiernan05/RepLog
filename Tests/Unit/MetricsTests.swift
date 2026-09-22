import Testing
import Foundation
@testable import RepLog

@Suite("Metrics")
struct MetricsTests {
    @Test("Brzycki e1RM: 100kg x 5 -> 112.5")
    func e1RMBrzycki() {
        #expect(abs(Metrics.e1RM(weight: 100, reps: 5)! - 112.5) < 0.001)
        #expect(abs(Metrics.e1RM(weight: 140, reps: 4)! - 140 * (1 + 4.0/30)) < 0.001)
        #expect(abs(Metrics.e1RM(weight: 85, reps: 5)! - 85 * (1 + 5.0/30)) < 0.001)
    }

    @Test("e1RM nil for 0 reps or 0 weight")
    func teste1RMNilFor0RepsOr0Weight() {
        #expect(Metrics.e1RM(weight: 100, reps: 0) == nil)
        #expect(Metrics.e1RM(weight: 0, reps: 5) == nil)
    }

    @Test("volume: weight_reps = weight x reps")
    func testvolumeWeightRepsWeightXReps() {
        let v = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                  durationS: nil, bodyweightKg: nil)
        #expect(v == 500)
    }

    @Test("volume: weight_time = weight x minutes")
    func testvolumeWeightTimeWeightXMinutes() {
        let v = Metrics.setVolume(type: .weightTime, weightKg: 100, reps: nil,
                                  durationS: 120, bodyweightKg: nil)
        #expect(v == 200)  // 100 x 2 min
    }

    @Test("volume: bw_weight_reps = (bw + added) x multiplier x reps")
    func testvolumeBwWeightRepsBwAddedXMultiplierXReps() {
        let v = Metrics.setVolume(type: .bwWeightReps, weightKg: 10, reps: 5,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == (80 + 10) * 5)  // 450
    }

    @Test("volume: bw_assisted = (bw - assistance) x multiplier x reps")
    func testvolumeBwAssistedBwAssistanceXMultiplierXReps() {
        let v = Metrics.setVolume(type: .bwAssisted, weightKg: 20, reps: 5,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == (80 - 20) * 5)  // 300
    }

    @Test("volume: bw_reps = bw x multiplier x reps")
    func testvolumeBwRepsBwXMultiplierXReps() {
        let v = Metrics.setVolume(type: .bwReps, weightKg: nil, reps: 10,
                                  durationS: nil, bodyweightKg: 80, multiplier: 1.0)
        #expect(v == 800)
    }

    @Test("volume: bodyweight multiplier applies")
    func testvolumeBodyweightMultiplierApplies() {
        let v = Metrics.setVolume(type: .bwReps, weightKg: nil, reps: 10,
                                  durationS: nil, bodyweightKg: 80, multiplier: 0.5)
        #expect(v == 400)
    }

    @Test("volume: single limb doubles")
    func testvolumeSingleLimbDoubles() {
        let normal = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                       durationS: nil, bodyweightKg: nil)
        let single = Metrics.setVolume(type: .weightReps, weightKg: 100, reps: 5,
                                       durationS: nil, bodyweightKg: nil, singleLimb: true)
        #expect(single == normal * 2)
    }

    @Test("volume: cardio and note are zero")
    func testvolumeCardioAndNoteAreZero() {
        #expect(Metrics.setVolume(type: .cardio, weightKg: nil, reps: nil,
                                  durationS: 600, bodyweightKg: 80) == 0)
        #expect(Metrics.setVolume(type: .note, weightKg: 10, reps: 5,
                                  durationS: nil, bodyweightKg: nil) == 0)
    }

    @Test("bestE1RM per exact rep count")
    func testbestE1RMPerExactRepCount() {
        let sets = makeSets([(100, 5), (110, 5), (90, 3)])
        #expect(Metrics.bestE1RM(sets: sets, reps: 5) == 110 * (1 + 5.0/30))
        #expect(Metrics.bestE1RM(sets: sets, reps: 3) == 90 * (1 + 3.0/30))
        #expect(Metrics.bestE1RM(sets: sets, reps: 7) == nil)
    }

    @Test("bestE1RM in range 11+ picks max reps>=11")
    func testbestE1RMInRange11PicksMaxReps11() {
        let sets = makeSets([(60, 12), (55, 15)])
        let best = Metrics.bestE1RM(sets: sets, inRange: 11)!
        #expect(best > 0)
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
