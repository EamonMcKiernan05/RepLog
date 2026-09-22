import Testing
import Foundation
import SwiftData
@testable import RepLog

@Suite("Importer (in-app, new schema)")
@MainActor
struct ImporterTests {
    /// Build a fresh in-memory store.
    private func freshStore() -> RepLog.DataStore {
        RepLog.DataStore(inMemory: true)
    }

    private func makeSession() -> Session {
        let session = Session(id: "import-test-1", date: Date())
        session.startTime = .now
        session.endTime = .now
        session.bodyweightKg = 90
        let ex = Exercise(name: "Squat", type: .weightReps,
                          category: Category(name: "Squats", sortOrder: 0))
        let entry = ExerciseEntry(exercise: ex, sortOrder: 0)
        entry.session = session
        let s1 = SetEntry(setNumber: 1); s1.weightKg = 100; s1.reps = 5; s1.rpe = 8
        let s2 = SetEntry(setNumber: 2); s2.weightKg = 120; s2.reps = 3; s2.rpe = 9
        entry.setEntries = [s1, s2]
        session.exerciseEntries = [entry]
        return session
    }

    @Test("encode -> import rebuilds sessions and sets")
    func roundTrip() {
        let source = makeSession()
        let csv = CSVCodec.encode(session: source)

        let store = freshStore()
        let result = Importer.importCSV(csv, into: store.context)
        #expect(result.sessions == 1)
        #expect(result.sets == 2)
        #expect(result.errors.isEmpty)

        let sessions = store.sessions()
        #expect(sessions.count == 1)
        let imported = sessions[0]
        #expect(imported.id == "import-test-1")
        #expect(imported.bodyweightKg == 90)
        #expect(imported.exerciseEntries.count == 1)
        let entry = imported.exerciseEntries[0]
        #expect(entry.exercise?.name == "Squat")
        // setEntries is an unordered SwiftData relationship — sort by setNumber.
        let sets = entry.setEntries.sorted(by: { $0.setNumber < $1.setNumber })
        #expect(sets.count == 2)
        #expect(sets[0].weightKg == 100)
        #expect(sets[0].rpe == 8)
        #expect(sets[1].reps == 3)
    }

    @Test("unknown exercises are created, not dropped")
    func unknownExercise() {
        let source = makeSession()
        // Rename to something not in the seed library.
        source.exerciseEntries[0].exercise?.name = "Brand New Lift"
        let csv = CSVCodec.encode(session: source)
        let store = freshStore()
        let result = Importer.importCSV(csv, into: store.context)
        #expect(result.sessions == 1)
        #expect(result.sets == 2)
        let imported = store.sessions()[0]
        #expect(imported.exerciseEntries[0].exercise?.name == "Brand New Lift")
    }

    @Test("multiple sessions import in order")
    func multiple() {
        let a = makeSession(); a.id = "aaa"
        let b = makeSession(); b.id = "bbb"
        let csv = CSVCodec.encode(sessions: [a, b])
        let store = freshStore()
        let result = Importer.importCSV(csv, into: store.context)
        #expect(result.sessions == 2)
        #expect(result.sets == 4)
    }

    @Test("bad header reports an error, imports nothing")
    func badHeader() {
        let store = freshStore()
        let result = Importer.importCSV("not,a,valid,header\n1,2,3\n", into: store.context)
        #expect(result.sessions == 0)
        #expect(!result.errors.isEmpty)
    }
}
