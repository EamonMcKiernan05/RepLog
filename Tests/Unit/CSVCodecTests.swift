import Testing
import Foundation
@testable import RepLog

@Suite("CSVCodec")
struct CSVCodecTests {
    /// Build the fixture session that the golden file was generated from
    /// (via the Python service — the reference implementation).
    private func fixtureSession() -> (Session, [ExerciseEntry]) {
        let session = Session(id: "8f2c1d90abcd", date: date("2026-09-21"))
        session.startTime = date("2026-09-21", "06:04")
        session.endTime = date("2026-09-21", "07:43")
        session.bodyweightKg = 100

        func mkSet(_ n: Int, w: Double? = nil, reps: Int? = nil, rpe: Double? = nil,
                   dur: Double? = nil, dist: Double? = nil, kcal: Double? = nil,
                   type: SetType = .working, notes: String = "") -> SetEntry {
            let s = SetEntry(setNumber: n, setType: type)
            s.weightKg = w; s.reps = reps; s.rpe = rpe
            s.durationS = dur; s.distanceM = dist; s.kcal = kcal
            s.notes = notes
            return s
        }

        let squat = ExerciseEntry(exercise: Exercise(name: "Low Bar Squat", type: .weightReps, category: Category(name: "Squats", sortOrder: 0)), sortOrder: 0)
        squat.setEntries = [
            mkSet(1, w: 160, reps: 1, rpe: 8, notes: "felt heavy, good speed"),
            mkSet(2, w: 140, reps: 4, rpe: 7),
        ]
        let bench = ExerciseEntry(exercise: Exercise(name: "Competition Bench", type: .weightReps, category: Category(name: "Bench Press", sortOrder: 1)), sortOrder: 1)
        bench.setEntries = [mkSet(1, w: 100, reps: 1, rpe: 8.5)]
        let dips = ExerciseEntry(exercise: Exercise(name: "Dips", type: .bwWeightReps, category: Category(name: "Chest", sortOrder: 2)), sortOrder: 2)
        dips.setEntries = [mkSet(1, w: 10, reps: 8, rpe: 7.5)]
        let tm = ExerciseEntry(exercise: Exercise(name: "Treadmill", type: .cardio, category: Category(name: "Cardio", sortOrder: 3)), sortOrder: 3)
        tm.setEntries = [mkSet(1, dur: 2100, dist: 5000, kcal: 320)]
        let leg = ExerciseEntry(exercise: Exercise(name: "Leg Extensions", type: .weightReps, category: Category(name: "Legs", sortOrder: 4)), sortOrder: 4)
        leg.setEntries = [mkSet(1, w: 60, reps: 15, type: .drop, notes: "Dropset")]
        let dead = ExerciseEntry(exercise: Exercise(name: "Sumo Deadlifts", type: .weightReps, category: Category(name: "Deadlift", sortOrder: 5)), sortOrder: 5)
        dead.setEntries = [mkSet(1, w: 180, reps: 1, rpe: 7.5, notes: "=HYPERLINK(\"x\")")]
        let plank = ExerciseEntry(exercise: Exercise(name: "Plank", type: .bwTime, category: Category(name: "Abs", sortOrder: 6)), sortOrder: 6)
        plank.setEntries = [mkSet(1, dur: 90)]

        let entries = [squat, bench, dips, tm, leg, dead, plank]
        session.exerciseEntries = entries
        return (session, entries)
    }

    private func date(_ d: String, _ t: String? = nil) -> Date {
        var f = CSVCodec.dateFormat
        if let t {
            f = CSVCodec.timeFormat
            let base = CSVCodec.dateFormat.date(from: d)!
            let comps = Calendar.current.dateComponents([.hour, .minute], from: f.date(from: t)!)
            return Calendar.current.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: base)!
        }
        return f.date(from: d)!
    }

    @Test("golden file: byte-identical to the Python service output")
    func golden() throws {
        let (session, _) = fixtureSession()
        let encoded = CSVCodec.encode(session: session)
        let golden = try goldenText()
        #expect(encoded == golden,
                "drift between Swift codec and Python service:\n--- got ---\n\(encoded)\n--- golden ---\n\(golden)")
    }

    @Test("round trip: encode then parse returns the same values")
    func roundTrip() throws {
        let (session, _) = fixtureSession()
        let encoded = CSVCodec.encode(session: session)
        let parsed = try CSVCodec.parse(encoded)
        #expect(parsed.count == 8)
        let first = parsed[0]
        #expect(first.sessionID == "8f2c1d90abcd")
        #expect(first.date == "2026-09-21")
        #expect(first.startTime == "06:04")
        #expect(first.endTime == "07:43")
        #expect(first.bodyweightKg == 100)
        #expect(first.exercise == "Low Bar Squat")
        #expect(first.exerciseType == "weight_reps")
        #expect(first.setNumber == 1)
        #expect(first.weightKg == 160)
        #expect(first.reps == 1)
        #expect(first.rpe == 8)
        #expect(first.notes == "felt heavy, good speed")
        // cardio row
        let tm = parsed[4]
        #expect(tm.exerciseType == "cardio")
        #expect(tm.weightKg == nil)
        #expect(tm.reps == nil)
        #expect(tm.durationS == 2100)
        #expect(tm.distanceM == 5000)
        #expect(tm.kcal == 320)
        // drop set
        let drop = parsed[5]
        #expect(drop.setType == "drop")
        // formula escape round-trips to the original text
        let dead = parsed[6]
        #expect(dead.notes == "=HYPERLINK(\"x\")")
    }

    @Test("rpe rendering: 8.0 -> 8, 8.5 -> 8.5, nil -> empty")
    func testrpeRendering8088585NilEmpty() {
        #expect(CSVCodec.rpe(8.0) == "8")
        #expect(CSVCodec.rpe(8.5) == "8.5")
        #expect(CSVCodec.rpe(nil) == "")
    }

    @Test("number rendering: no trailing .0")
    func testnumberRenderingNoTrailing0() {
        #expect(CSVCodec.num(100.0) == "100")
        #expect(CSVCodec.num(85.5) == "85.5")
        #expect(CSVCodec.num(nil) == "")
    }

    @Test("field: quotes commas, escapes leading formula chars")
    func testfieldQuotesCommasEscapesLeadingFormulaChars() {
        #expect(CSVCodec.field("a,b") == "\"a,b\"")
        #expect(CSVCodec.field("=SUM(A1)") == " =SUM(A1)")
        #expect(CSVCodec.field("plain") == "plain")
        #expect(CSVCodec.field("") == "")
    }

    @Test("bad header throws")
    func testbadHeaderThrows() {
        let bad = "wrong,header\n1,2\n"
        #expect(throws: CSVError.self) {
            _ = try CSVCodec.parse(bad)
        }
    }

    private func goldenText() throws -> String {
        let url = Bundle.module.url(forResource: "golden_session", withExtension: "csv")
            ?? Bundle.main.url(forResource: "golden_session", withExtension: "csv")
        guard let url else { throw CSVError.badHeader }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
