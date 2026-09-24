import Foundation

/// What the routine detail draws under each exercise.
///
/// Owner report (2026-09-24): "When editing a routine the exercise notes don't
/// reflect the actual exercise note set in the routine." The row drew the
/// routine's set scheme ("1x4") and never the exercise's own note, so a note
/// set in the editor was invisible in the routine. Three orders are compiled
/// in and picked with `-RoutineRow <1...3>` so one build captures all of them.
enum RoutineRowStyle: Int, CaseIterable {
    /// The note takes the slot; the scheme lines are not drawn (default).
    case noteOnly = 1
    /// The note first, then the scheme lines.
    case noteThenScheme = 2
    /// The scheme lines first, then the note.
    case schemeThenNote = 3

    static let `default`: RoutineRowStyle = .noteOnly

    static let current: RoutineRowStyle = {
        let raw = UserDefaults.standard.integer(forKey: "RoutineRow")
        return RoutineRowStyle(rawValue: raw) ?? `default`
    }()

    var showsScheme: Bool { self != .noteOnly }
    var noteFirst: Bool { self != .schemeThenNote }
}
