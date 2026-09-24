import CoreGraphics
import Foundation

/// Set-row geometry (owner, 2026-09-24).
///
/// The owner asked for the columns to be stretched closer to the set-number
/// circle with an even gap either side of Weight, Reps and RPE, room reserved
/// for a three-digit weight, and the values a size or two smaller. One build
/// carries four variants chosen with the `-RowLayout <1...4>` launch argument
/// so a capture run can shoot them all; the chosen one is the default below.
///
/// Variants (gutter / number size):
///   1. 12 / 16 — tightest gaps, gently smaller type
///   2. 16 / 16 — an even 16 pt rhythm, gently smaller type
///   3. 16 / 15 — an even 16 pt rhythm, a size smaller again
///   4. 20 / 15 — widest gaps, a size smaller again  ← the owner's choice
struct RowLayout: Equatable {
    /// Every horizontal gap inside the row: the circle to the first column and
    /// between one column and the next.
    let gutter: CGFloat
    /// Weight / Reps / RPE value size.
    let numberSize: CGFloat

    /// The card's standard edge inset, worn by the header row and the
    /// "Add Set" row. Variant 2's gutter equals it, so the whole row reads as
    /// one even rhythm.
    static let cardInset: CGFloat = 16

    /// Room for three digits of the monospaced face at `numberSize` (SF Mono
    /// advances 0.6 em per digit; 0.62 leaves a little slack). Reserving it
    /// keeps a column still whether it holds "5" or "140".
    var numberWidth: CGFloat { (numberSize * 0.62 * 3).rounded() }

    static let all: [RowLayout] = [
        RowLayout(gutter: 12, numberSize: 16),
        RowLayout(gutter: 16, numberSize: 16),
        RowLayout(gutter: 16, numberSize: 15),
        RowLayout(gutter: 20, numberSize: 15),
    ]

    /// Variant 4 — chosen by the owner on 2026-09-24. The launch-argument hook
    /// stays for now so the alternatives can still be re-shot; it comes out
    /// once he has signed the choice off on the phone.
    static let `default` = all[3]

    /// `-RowLayout N`, 1-based. Anything else → the default.
    static let current: RowLayout = {
        let n = UserDefaults.standard.integer(forKey: "RowLayout")
        guard n >= 1, n <= all.count else { return `default` }
        return all[n - 1]
    }()
}
