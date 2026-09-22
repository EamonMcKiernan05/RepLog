import Foundation

/// CSV encode/decode for the frozen sync schema v1 (plan §4.4).
///
/// The header order and spelling are the contract. This codec mirrors the
/// Python service's store byte-for-byte (verified by the golden-file test):
/// - weight always kg
/// - rpe plain number, one decimal max, empty when not recorded
/// - text fields quoted when needed; leading `= + - @` escaped with a space
/// - UTF-8, LF, no BOM
enum CSVCodec {

    static let header: [String] = [
        "session_id", "date", "start_time", "end_time", "bodyweight_kg",
        "exercise", "category", "exercise_type", "superset_id", "set_number",
        "weight_kg", "reps", "rpe", "duration_s", "distance_m", "kcal",
        "set_type", "notes",
    ]

    // MARK: - Numbers

    /// Render a number the way the CSV wants it: no trailing .0, else "".
    static func num(_ value: Double?) -> String {
        guard let v = value else { return "" }
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int(v))
        }
        // One decimal max for rpe-style values; general otherwise.
        let s = String(v)
        return s
    }

    static func int(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    /// RPE: one decimal max, empty when nil. 8.0 -> "8", 8.5 -> "8.5".
    static func rpe(_ value: Double?) -> String {
        guard let v = value else { return "" }
        let tenths = (v * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(tenths / 10)
        }
        return String(format: "%.1f", v)
    }

    // MARK: - Dates

    static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ d: Date) -> String { dateFormat.string(from: d) }
    static func time(_ d: Date) -> String { timeFormat.string(from: d) }

    // MARK: - Field encoding

    /// One CSV cell: quote when needed; escape formula-shaped text.
    static func field(_ value: String) -> String {
        if value.isEmpty { return "" }
        var text = value
        if let first = text.first, "=+-@".contains(first) {
            text = " " + text
        }
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }

    // MARK: - Session encoding

    /// Encode a whole session into CSV text (header + rows, LF, trailing NL).
    static func encode(session: Session) -> String {
        var lines = [header.joined(separator: ",")]
        for entry in session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            for set in entry.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let row = row(session: session, entry: entry, set: set)
                lines.append(row.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func row(session: Session, entry: ExerciseEntry, set: SetEntry) -> [String] {
        [
            field(session.id),
            field(date(session.date)),
            field(session.startTime.map { time($0) } ?? ""),
            field(session.endTime.map { time($0) } ?? ""),
            field(num(session.bodyweightKg)),
            field(entry.exercise?.name ?? ""),
            field(entry.exercise?.category?.name ?? ""),
            field(entry.setType.rawValue),
            field(entry.supersetId ?? ""),
            int(set.setNumber),
            field(num(set.weightKg)),
            int(set.reps),
            rpe(set.rpe),
            field(num(set.durationS)),
            field(num(set.distanceM)),
            field(num(set.kcal)),
            field(set.setType.rawValue),
            field(set.notes),
        ]
    }

    /// Encode many sessions into one file (export path).
    static func encode(sessions: [Session]) -> String {
        var lines = [header.joined(separator: ",")]
        for session in sessions {
            for entry in session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                for set in entry.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    lines.append(row(session: session, entry: entry, set: set).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Parsing

    struct ParsedSet {
        let sessionID: String
        let date: String
        let startTime: String
        let endTime: String
        let bodyweightKg: Double?
        let exercise: String
        let category: String
        let exerciseType: String
        let supersetID: String
        let setNumber: Int
        let weightKg: Double?
        let reps: Int?
        let rpe: Double?
        let durationS: Double?
        let distanceM: Double?
        let kcal: Double?
        let setType: String
        let notes: String
    }

    /// Parse a sync-schema CSV file into sets (for in-app import).
    static func parse(_ text: String) throws -> [ParsedSet] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // Strip a trailing blank line.
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return [] }
        let headerLine = lines[0]
        let headerCols = splitLine(String(headerLine))
        guard headerCols == header else {
            throw CSVError.badHeader
        }
        var out: [ParsedSet] = []
        for (i, line) in lines.dropFirst().enumerated() {
            let cols = splitLine(String(line))
            guard cols.count == header.count else {
                throw CSVError.badRow(lineIndex: i + 2)
            }
            func str(_ idx: Int) -> String {
                var v = cols[idx]
                // Undo the formula escape: a leading space we added.
                if v.hasPrefix(" "), let c = v.dropFirst().first, "=+-@".contains(c) {
                    v = String(v.dropFirst())
                }
                return v
            }
            func dbl(_ idx: Int) -> Double? {
                let s = str(idx)
                return s.isEmpty ? nil : Double(s)
            }
            func intv(_ idx: Int) -> Int? {
                let s = str(idx)
                return s.isEmpty ? nil : Int(s)
            }
            out.append(ParsedSet(
                sessionID: str(0), date: str(1), startTime: str(2), endTime: str(3),
                bodyweightKg: dbl(4), exercise: str(5), category: str(6),
                exerciseType: str(7), supersetID: str(8), setNumber: intv(9) ?? 0,
                weightKg: dbl(10), reps: intv(11), rpe: dbl(12),
                durationS: dbl(13), distanceM: dbl(14), kcal: dbl(15),
                setType: str(16), notes: str(17)
            ))
        }
        return out
    }

    /// Split one CSV line respecting quotes.
    static func splitLine(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        cur.append("\"")
                        i = line.index(after: next)
                        continue
                    }
                    inQuotes = false
                    i = line.index(after: i)
                    continue
                }
                cur.append(ch)
                i = line.index(after: i)
                continue
            }
            switch ch {
            case "\"":
                inQuotes = true
                i = line.index(after: i)
            case ",":
                out.append(cur)
                cur = ""
                i = line.index(after: i)
            default:
                cur.append(ch)
                i = line.index(after: i)
            }
        }
        out.append(cur)
        return out
    }
}

enum CSVError: Error {
    case badHeader
    case badRow(lineIndex: Int)
}
