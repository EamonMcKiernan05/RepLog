import Testing
import Foundation
@testable import RepLog

/// The routine import's rules. Pure logic, no store, no UI — `scripts/logic-tests.sh`
/// runs this file on Linux with the same bytes Xcode runs it with.
@Suite("RoutineCSV")
struct RoutineCSVTests {

    private let header = "routine,position,exercise,type,category,warmup_sets,working_sets,notes\n"

    @Test("A plain two-row routine parses with its set counts and notes")
    func happyPath() throws {
        let csv = header + """
        SBD,1,Low Bar Squat,weights,Legs,1,4,heavy single then 3x4
        SBD,2,Bench Press,weights,Chest,0,4,paused
        """
        let out = try RoutineCSV.parse(csv)
        #expect(out.count == 1)
        #expect(out[0].name == "SBD")
        #expect(out[0].exercises.count == 2)
        #expect(out[0].exercises[0].exercise == "Low Bar Squat")
        #expect(out[0].exercises[0].warmupSets == 1)
        #expect(out[0].exercises[0].workingSets == 4)
        #expect(out[0].exercises[0].notes == "heavy single then 3x4")
        #expect(out[0].exercises[1].notes == "paused")
    }

    @Test("Column order is not the contract; unknown columns are ignored")
    func columnOrderAndUnknownColumns() throws {
        let out = try RoutineCSV.parse("exercise,routine,load,working_sets\nBench Press,SBD,80,5\n")
        #expect(out[0].exercises[0].exercise == "Bench Press")
        #expect(out[0].exercises[0].workingSets == 5)
        #expect(out[0].exercises[0].warmupSets == 0)
    }

    @Test("A Windows CRLF file reads as separate records")
    func crlfAndTrailingBlankLines() throws {
        let out = try RoutineCSV.parse("routine,exercise\r\nSBD,Low Bar Squat\r\n\r\n")
        #expect(out.count == 1)
        #expect(out[0].exercises[0].exercise == "Low Bar Squat")
    }

    @Test("A missing required column names the column")
    func missingRequiredColumn() {
        #expect {
            try RoutineCSV.parse("routine,warmup_sets\nSBD,1\n")
        } throws: { error in
            error as? RoutineCSV.ImportError == .missingColumns(["exercise"])
        }
    }

    @Test("A bad number fails with its line and column")
    func badNumberNamesTheLine() {
        let csv = header + "SBD,1,Squat,weights,Legs,one,4,\n"
        #expect {
            try RoutineCSV.parse(csv)
        } throws: { error in
            error as? RoutineCSV.ImportError == .badValue(line: 2, column: "warmup_sets", value: "one")
        }
    }

    @Test("A type outside weights/cardio is rejected")
    func badTypeRejected() {
        let csv = header + "SBD,1,Squat,bodyweight,Legs,0,4,\n"
        #expect {
            try RoutineCSV.parse(csv)
        } throws: { error in
            error as? RoutineCSV.ImportError == .badValue(line: 2, column: "type", value: "bodyweight")
        }
    }

    @Test("A row with no exercise name is rejected")
    func emptyExerciseRejected() {
        let csv = header + "SBD,1,,weights,Legs,0,4,\n"
        #expect {
            try RoutineCSV.parse(csv)
        } throws: { error in
            error as? RoutineCSV.ImportError == .emptyExercise(line: 2)
        }
    }

    @Test("A quoted note may hold commas and newlines")
    func quotedCommaAndNewlineInNotes() throws {
        let csv = header + "SBD,1,Squat,weights,Legs,0,4,\"line one\nline two, with a comma\"\n"
        let out = try RoutineCSV.parse(csv)
        #expect(out[0].exercises[0].notes == "line one\nline two, with a comma")
        #expect(out[0].exercises.count == 1, "the quoted newline must not start a new row")
    }

    @Test("The formula escape is undone on read")
    func formulaEscapeIsUndone() throws {
        let csv = header + "SBD,1,Squat,weights,Legs,0,4, =1+1\n"
        let out = try RoutineCSV.parse(csv)
        #expect(out[0].exercises[0].notes == "=1+1")
    }

    @Test("Two routines keep their file order, and so do their rows")
    func twoRoutinesKeepFileOrder() throws {
        let csv = header + """
        A,1,Squat,weights,Legs,0,3,
        B,1,Bench,weights,Chest,0,3,
        A,2,Leg Press,weights,Legs,0,3,
        """
        let out = try RoutineCSV.parse(csv)
        #expect(out.map(\.name) == ["A", "B"])
        #expect(out[0].exercises.map(\.exercise) == ["Squat", "Leg Press"])
    }

    @Test("position overrides the file order")
    func positionsOverrideFileOrder() throws {
        let csv = header + """
        A,3,Third,weights,Legs,0,3,
        A,1,First,weights,Legs,0,3,
        A,2,Second,weights,Legs,0,3,
        """
        let out = try RoutineCSV.parse(csv)
        #expect(out[0].exercises.map(\.exercise) == ["First", "Second", "Third"])
    }

    @Test("Blank lines are skipped")
    func blankLinesSkipped() throws {
        let csv = header + "\nSBD,1,Squat,weights,Legs,0,4,\n\n"
        let out = try RoutineCSV.parse(csv)
        #expect(out[0].exercises.count == 1)
    }

    @Test("An empty file is an error, not an empty import")
    func emptyFileRejected() {
        #expect {
            try RoutineCSV.parse("")
        } throws: { error in
            error as? RoutineCSV.ImportError == .emptyFile
        }
    }
}
