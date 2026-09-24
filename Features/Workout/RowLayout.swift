import CoreGraphics
import Foundation

/// Set-row geometry under review (owner, 2026-09-24).
///
/// The owner asked for the columns to be stretched closer to the set-number
/// circle with an even gap either side of Weight, Reps and RPE, room reserved
/// for a three-digit weight, and the values a size or two smaller (the Notes
/// value a size below those). Rather than guess, one build carries four
/// variants chosen with the `-RowLayout <1...4>` launch argument, so a single
/// capture run shoots them all; whichever he picks becomes the constant and
/// this hook comes out.
///
/// Variants (gutter / number size / notes size):
///   1. 12 / 16 / 14 — tightest gaps, gently smaller type
///   2. 16 / 16 / 14 — an even 16 pt rhythm, gently smaller type
///   3. 16 / 15 / 13 — an even 16 pt rhythm, a size smaller again
///   4. 20 / 15 / 13 — widest gaps, a size smaller again
struct RowLayout: Equatable {
    /// Every horizontal gap inside the row: the circle to the first column and
    /// between one column and the next.
    let gutter: CGFloat
    /// Weight / Reps / RPE value size.
    let numberSize: CGFloat
    /// Notes value size — a step below the numbers, as asked.
    let notesSize: CGFloat

    /// The card's standard edge inset, worn by the header row and the
    /// "Add Set" row. Variant 2's gutter equals it, so the whole row reads as
    /// one even rhythm.
    static let cardInset: CGFloat = 16

    /// Room for three digits of the monospaced face at `numberSize` (SF Mono
    /// advances 0.6 em per digit; 0.62 leaves a little slack). Reserving it
    /// keeps a column still whether it holds "5" or "140".
    var numberWidth: CGFloat { (numberSize * 0.62 * 3).rounded() }

    static let all: [RowLayout] = [
        RowLayout(gutter: 12, numberSize: 16, notesSize: 14),
        RowLayout(gutter: 16, numberSize: 16, notesSize: 14),
        RowLayout(gutter: 16, numberSize: 15, notesSize: 13),
        RowLayout(gutter: 20, numberSize: 15, notesSize: 13),
    ]

    /// The default when no launch argument is present — variant 2, the one
    /// that answers the request most literally.
    static let `default` = all[1]

    /// `-RowLayout N`, 1-based. Anything else → the default.
    static let current: RowLayout = {
        let n = UserDefaults.standard.integer(forKey: "RowLayout")
        guard n >= 1, n <= all.count else { return `default` }
        return all[n - 1]
    }()
}
