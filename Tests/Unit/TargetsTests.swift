import Testing
import Foundation
@testable import RepLog

@Suite("Targets")
struct TargetsTests {
    @Test("Latest mode uses the most recent set of the exercise")
    func latest() {
        let history: [(weight: Double?, reps: Int?, rpe: Double?, routineName: String?)] = [
            (100, 5, 8, "A"),   // newest first
            (90, 5, 7, "B"),
        ]
        let ph = Targets.placeholder(mode: .latest, routineName: "A",
                                     setIndex: 0, history: history)
        #expect(ph.weight == 100)
        #expect(ph.reps == 5)
        #expect(ph.rpe == 8)
    }

    @Test("By Routine mode filters to the named routine")
    func byRoutine() {
        let history: [(weight: Double?, reps: Int?, rpe: Double?, routineName: String?)] = [
            (100, 5, 8, "B"),   // newest, but wrong routine
            (90, 5, 7, "A"),    // the A routine's last set
        ]
        let ph = Targets.placeholder(mode: .byRoutine, routineName: "A",
                                     setIndex: 0, history: history)
        #expect(ph.weight == 90)
    }

    @Test("empty history yields empty placeholder")
    func empty() {
        let ph = Targets.placeholder(mode: .latest, routineName: "A",
                                     setIndex: 0, history: [])
        #expect(ph.weight == nil)
        #expect(ph.reps == nil)
    }

    @Test("exactSets returns the source session's sets in order")
    func exact() {
        let session = Session(id: "src")
        let ex = Exercise(name: "Squat", type: .weightReps)
        let entry = ExerciseEntry(exercise: ex, sortOrder: 0)
        entry.session = session
        let s1 = SetEntry(setNumber: 1); s1.weightKg = 160; s1.reps = 1; s1.rpe = 8
        let s2 = SetEntry(setNumber: 2); s2.weightKg = 140; s2.reps = 4; s2.rpe = 7
        entry.setEntries = [s1, s2]
        session.exerciseEntries = [entry]

        let exact = Targets.exactSets(from: session, exerciseName: "Squat")
        #expect(exact.count == 2)
        #expect(exact[0].weight == 160)
        #expect(exact[1].reps == 4)
        #expect(exact[1].rpe == 7)
    }

    @Test("latestPerformance tiles the last session's sets")
    func latestPerformance() {
        let session = Session(id: "src", date: .now)
        let ex = Exercise(name: "Bench", type: .weightReps)
        let entry = ExerciseEntry(exercise: ex, sortOrder: 0)
        entry.session = session
        let s1 = SetEntry(setNumber: 1); s1.weightKg = 100; s1.reps = 5
        entry.setEntries = [s1]
        session.exerciseEntries = [entry]

        let perf = Targets.latestPerformance(for: "Bench", setCount: 3,
                                             sessions: [session])
        #expect(perf.count == 3)
        #expect(perf[2].weight == 100)  // tiled
    }
}
