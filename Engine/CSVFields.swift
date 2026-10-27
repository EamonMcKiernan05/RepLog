import Foundation

/// The CSV quoting rules in one place.
///
/// Two schemas now read and write CSV — the session export (`CSVCodec`) and
/// the routine import (`RoutineCSV`) — and they must agree on quoting or a
/// note that survives one will not survive the other. Foundation only, so the
/// rules can be exercised by a plain `swift test` without a simulator.
///
/// Both splitters work on UNICODE SCALARS, not Characters: Swift treats a CRLF
/// pair as ONE Character (a single grapheme cluster), so a Character-wise scan
/// never matches `"\r"` or `"\n"` in a Windows-exported file and the whole file
/// reads as one record (found by the Linux test run, 2026-10-23).
enum CSVFields {

    /// One cell: quote when needed; escape formula-shaped text with a leading
    /// space so a spreadsheet does not run `=HYPERLINK(...)` from a workout
    /// note.
    static func escape(_ value: String) -> String {
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

    /// The inverse of the formula escape. Ordinary cell text is left alone.
    static func unescape(_ value: String) -> String {
        if value.hasPrefix(" "), let c = value.dropFirst().first, "=+-@".contains(c) {
            return String(value.dropFirst())
        }
        return value
    }

    /// Split a whole file into records, so a quoted field may contain the
    /// newlines a multi-line note now holds. CRLF and a trailing blank line are
    /// tolerated; the terminator is not part of the record.
    static func splitRecords(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var out: [String] = []
        var cur: [Unicode.Scalar] = []
        var inQuotes = false
        var i = 0

        func flush() {
            out.append(String(String.UnicodeScalarView(cur)))
            cur.removeAll(keepingCapacity: true)
        }

        while i < scalars.count {
            let ch = scalars[i]
            if ch == "\"" {
                if inQuotes, i + 1 < scalars.count, scalars[i + 1] == "\"" {
                    cur.append("\"")            // a doubled quote is an escaped quote
                    i += 2
                    continue
                }
                inQuotes.toggle()
                cur.append(ch)
                i += 1
                continue
            }
            if ch == "\n" || ch == "\r" {
                if inQuotes {
                    cur.append(ch)
                    i += 1
                    continue
                }
                if ch == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    i += 2                       // collapse CRLF
                } else {
                    i += 1
                }
                flush()
                continue
            }
            cur.append(ch)
            i += 1
        }
        flush()
        while let last = out.last, last.isEmpty { out.removeLast() }
        return out
    }

    /// Split one CSV line respecting quotes. Use `splitRecords` for a file:
    /// a quoted field may hold newlines.
    static func split(_ line: String) -> [String] {
        let scalars = Array(line.unicodeScalars)
        var out: [String] = []
        var cur: [Unicode.Scalar] = []
        var inQuotes = false
        var i = 0

        func flush() {
            out.append(String(String.UnicodeScalarView(cur)))
            cur.removeAll(keepingCapacity: true)
        }

        while i < scalars.count {
            let ch = scalars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        cur.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                cur.append(ch)
                i += 1
                continue
            }
            if ch == "\"" {
                inQuotes = true
                i += 1
                continue
            }
            if ch == "," {
                flush()
                i += 1
                continue
            }
            cur.append(ch)
            i += 1
        }
        flush()
        return out
    }
}
