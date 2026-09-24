import SwiftUI

/// How the Notes column is drawn (owner, 2026-09-24).
///
/// The complaint: the note appeared twice (in the box and again under the
/// row), its type was too large next to the column titles, the "Notes" title
/// sat lower than Kg/Reps/RPE, and the title and the note did not line up —
/// "move them both the same distance until the first letter in the note is
/// centered under the 'notes' column title".
///
/// Four candidate treatments, chosen with `-NotesStyle <1...4>` so one build
/// can be captured in all of them before the owner picks:
///
///   1. label centred over the note's first character · note in the caption
///      size (the same size as the labels)
///   2. same alignment · note one step up (footnote)
///   3. label and note flush left together · note in the caption size
///   4. label centred over the note's first character · note monospaced, to
///      match the number columns' typeface
struct NotesStyle: Equatable {
    /// Where the column label sits relative to the note under it.
    enum LabelPlacement {
        /// The label's centre over the note's first character — the label and
        /// the note pulled toward each other, as asked.
        case centredOverValue
        /// Flush with the note, both at the column's leading edge.
        case flushLeading
    }

    let labelPlacement: LabelPlacement
    /// The note's own type.
    let font: Font

    /// How far the NOTE is indented from the column's leading edge. With the
    /// label sitting flush, half the label's own width ("Notes" at the caption
    /// size) puts the label's centre over the note's first character — the
    /// note moves left from where centring put it, the label right from the
    /// edge, by very nearly the same distance. Zero for the flush treatment
    /// and for the numeric columns.
    func valueInset(wide: Bool) -> CGFloat {
        guard wide, labelPlacement == .centredOverValue else { return 0 }
        return 16
    }

    static let all: [NotesStyle] = [
        NotesStyle(labelPlacement: .centredOverValue, font: .caption),
        NotesStyle(labelPlacement: .centredOverValue, font: .footnote),
        NotesStyle(labelPlacement: .flushLeading, font: .caption),
        NotesStyle(labelPlacement: .centredOverValue, font: Typography.mono(12)),
    ]

    static let `default` = all[0]

    /// `-NotesStyle N`, 1-based. Anything else → the default.
    static let current: NotesStyle = {
        let n = UserDefaults.standard.integer(forKey: "NotesStyle")
        guard n >= 1, n <= all.count else { return `default` }
        return all[n - 1]
    }()
}
