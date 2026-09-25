import Testing
import Foundation
@testable import RepLog

@Suite("Targets")
struct TargetsTests {
    /// The hint rule, as `Targets.hints` resolves it: one entry per set, from
    /// the chosen session, in the display unit. (The value path this used to
    /// test — writing the previous numbers into a new set — is gone: the owner
    /// wants them shown behind an empty box, never entered for him.)
    private func past(_ weight: Double, _ reps: Int, _ rpe: Double,
                      routine: String, date: Date, set: Int = 1) -> Targets.PastSet {
        Targets.PastSet(exerciseName: "Squat", sessionDate: date, routineName: routine,
                        setNumber: set, weightKg: weight, reps: reps, rpe: rpe, notes: "")
    }

    @Test("Latest mode hints from the most recent session of the exercise")
    func latest() {
        let now = Date()
        let history = [past(90, 5, 7, routine: "B", date: now.addingTimeInterval(-86_400)),
                       past(100, 5, 8, routine: "A", date: now)]
        let hints = Targets.hints(mode: .latest, routineName: "A", exerciseName: "Squat",
                                  history: history, unit: .kg, setCount: 1)
        #expect(hints.count == 1)
        #expect(hints[0].weight == "100")
        #expect(hints[0].reps == "5")
        #expect(hints[0].rpe == "8")
    }

    @Test("By Routine mode hints from that routine's last session")
    func byRoutine() {
        let now = Date()
        let history = [past(100, 5, 8, routine: "B", date: now),          // newest, wrong routine
                       past(90, 5, 7, routine: "A", date: now.addingTimeInterval(-86_400))]
        let hints = Targets.hints(mode: .byRoutine, routineName: "A", exerciseName: "Squat",
                                  history: history, unit: .kg, setCount: 1)
        #expect(hints[0].weight == "90")
    }

    @Test("no history yields no hints, and set 3 of a 2-set session repeats set 2")
    func emptyAndTiling() {
        let none = Targets.hints(mode: .latest, routineName: "A", exerciseName: "Squat",
                                 history: [], unit: .kg, setCount: 2)
        #expect(none.isEmpty)

        let now = Date()
        let history = [past(100, 5, 8, routine: "A", date: now, set: 1),
                       past(90, 4, 7, routine: "A", date: now, set: 2)]
        let hints = Targets.hints(mode: .latest, routineName: "A", exerciseName: "Squat",
                                  history: history, unit: .kg, setCount: 3)
        #expect(hints.count == 3)
        #expect(hints[0].weight == "100")
        #expect(hints[1].weight == "90")
        #expect(hints[2].weight == "90")   // tiles the last set
        #expect(hints[1].notes.isEmpty)
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
