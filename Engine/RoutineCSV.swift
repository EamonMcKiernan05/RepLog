import Foundation

/// Routine import: a CSV of rows, one row per exercise (owner request,
/// 2026-10-23).
///
/// The header is the contract, the column ORDER is not: columns are matched by
/// name, unknown columns are ignored, so a file may carry extra columns for a
/// future program import without breaking this reader. Required columns are
/// `routine` and `exercise`.
///
///     routine,position,exercise,type,category,warmup_sets,working_sets,notes
///     SBD,1,Low Bar Squat,weights,Legs,1,4,heavy single then 3x4
///     SBD,2,Bench Press,weights,Chest,0,4,paused
///
/// - `routine` — the routine name; rows sharing it are one routine, in the
///   order they appear (or by `position` when given).
/// - `exercise` — matched to the library case-insensitively by the caller;
///   created if it does not exist.
/// - `type` — `weights` (default) or `cardio`; only used when the exercise is
///   created.
/// - `category` — only used when the exercise is created.
/// - `warmup_sets` / `working_sets` — integers, default 0 and 4.
/// - `notes` — the exercise's note in the routine, may contain newlines.
///
/// A bad row fails the WHOLE import with its line number: half-importing a
/// routine is worse than importing none of it.
///
/// Foundation only, so `swift test` covers it without Xcode (the Mac build
/// host can be down; this logic still gets proven).
enum RoutineCSV {

    struct ParsedExercise: Equatable {
        var position: Int
        var exercise: String
        var type: String        // "weights" | "cardio"
        var category: String
        var warmupSets: Int
        var workingSets: Int
        var notes: String
    }

    struct ParsedRoutine: Equatable {
        var name: String
        var exercises: [ParsedExercise]
    }

    enum ImportError: Error, Equatable {
        case emptyFile
        case missingColumns([String])
        case badValue(line: Int, column: String, value: String)
        case emptyExercise(line: Int)
        case noExercises(routine: String)
    }

    static let requiredColumns = ["routine", "exercise"]
    static let knownColumns = ["routine", "position", "exercise", "type", "category",
                               "warmup_sets", "working_sets", "notes"]
    static let exerciseTypes = ["weights", "cardio"]

    /// Parse the file. Throws on the first structural problem, naming the line.
    static func parse(_ text: String) throws -> [ParsedRoutine] {
        let records = CSVFields.splitRecords(text)
        guard let headerRecord = records.first, !headerRecord.isEmpty else {
            throw ImportError.emptyFile
        }
        let header = CSVFields.split(headerRecord).map { normalise($0) }
        let missing = requiredColumns.filter { !header.contains($0) }
        guard missing.isEmpty else { throw ImportError.missingColumns(missing) }

        // Column index by name; absent -> nil.
        func index(_ name: String) -> Int? { header.firstIndex(of: name) }

        var order: [String] = []                 // routine names, first seen first
        var byRoutine: [String: [ParsedExercise]] = [:]

        for (offset, record) in records.dropFirst().enumerated() {
            let line = offset + 2                // 1-based, header is line 1
            let raw = CSVFields.split(record)
            guard !raw.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                continue                          // blank line
            }
            func cell(_ name: String) -> String {
                guard let i = index(name), i < raw.count else { return "" }
                return CSVFields.unescape(raw[i]).trimmingCharacters(in: .whitespaces)
            }
            let routine = cell("routine")
            guard !routine.isEmpty else {
                throw ImportError.badValue(line: line, column: "routine", value: "")
            }
            let exercise = cell("exercise")
            guard !exercise.isEmpty else { throw ImportError.emptyExercise(line: line) }

            let type = cell("type").lowercased()
            guard type.isEmpty || exerciseTypes.contains(type) else {
                throw ImportError.badValue(line: line, column: "type", value: type)
            }

            let position = try intValue(cell("position"), line: line, column: "position") ?? 0
            let warmup = try intValue(cell("warmup_sets"), line: line, column: "warmup_sets") ?? 0
            let working = try intValue(cell("working_sets"), line: line, column: "working_sets") ?? 4
            guard warmup >= 0, working >= 0 else {
                throw ImportError.badValue(line: line, column: "warmup_sets", value: cell("warmup_sets"))
            }

            if byRoutine[routine] == nil {
                order.append(routine)
                byRoutine[routine] = []
            }
            byRoutine[routine]?.append(ParsedExercise(
                position: position,
                exercise: exercise,
                type: type.isEmpty ? "weights" : type,
                category: cell("category"),
                warmupSets: warmup,
                workingSets: working,
                notes: cell("notes")
            ))
        }

        return try order.map { name in
            let rows = byRoutine[name] ?? []
            guard !rows.isEmpty else { throw ImportError.noExercises(routine: name) }
            // A stable sort: rows with no position keep their file order, and
            // equal positions do too.
            let sorted = rows.enumerated()
                .sorted { a, b in
                    if a.element.position == b.element.position { return a.offset < b.offset }
                    return a.element.position < b.element.position
                }
                .map(\.element)
            return ParsedRoutine(name: name, exercises: sorted)
        }
    }

    private static func intValue(_ raw: String, line: Int, column: String) throws -> Int? {
        if raw.isEmpty { return nil }
        guard let v = Int(raw) else {
            throw ImportError.badValue(line: line, column: column, value: raw)
        }
        return v
    }

    /// Header cells are compared lower-cased with spaces/underscores folded so
    /// "Warmup Sets" and "warmup_sets" are the same column.
    private static func normalise(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}
