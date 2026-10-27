import SwiftUI

/// Which inline cell holds the keyboard, and on which object.
///
/// One `CellFocus?` per screen (shared down through the cards) so a single
/// keyboard "Done" clears whatever is being edited, and the exercise card can
/// reveal the RPE chips under the row that is actually being edited.
struct CellFocus: Hashable {
    enum Field: Hashable {
        case weight, reps, time, distance, kcal, rpe, notes
        case exerciseNote, workoutNote, bodyweight, routineName, warmup, working
    }

    let owner: ObjectIdentifier
    let field: Field
}

/// A set-row cell that **is** the input: tap the box, the keyboard opens in
/// place, type, and it commits on submit or when it loses focus. No sheet, no
/// pop-up.
///
/// Unfocused it renders exactly like the old label column (a small label over
/// a monospaced value), so the row's look is unchanged — only the editing
/// moved into the box.
struct InlineCell: View {
    let label: String
    let id: String
    /// Canonical text, straight from the model.
    let value: String
    var keyboard: UIKeyboardType = .numberPad
    /// What the empty box shows behind it: the last time this set was done
    /// (owner, 2026-09-25). Decoration only — it is never the field's value and
    /// it takes no taps. Empty falls back to the old "—".
    var hint: String = ""
    /// Fills the rest of the row (the Notes column).
    var wide = false
    var alignment: TextAlignment = .center
    /// Value font size. The numbers shrank and the Notes value sits a step
    /// below them (owner, 2026-09-24).
    var valueSize: CGFloat = 17
    /// Fixed cell width — three digits of the number font, so a column holds
    /// its place whether it reads "5" or "140". nil keeps the old 44 pt
    /// minimum, and the wide Notes column fills what is left.
    var fixedWidth: CGFloat? = nil
    /// Type for the value. nil = the monospaced number face at `valueSize`;
    /// the Notes column passes the app's own text font (see `NotesStyle`).
    var valueFont: Font? = nil
    /// Multi-line notes (owner request, 2026-10-23): the Return key inserts a
    /// newline instead of closing the box, the box starts at two lines and
    /// grows with the text, and the row grows with it.
    var multiline: Bool = false
    let focus: FocusState<CellFocus?>.Binding
    let focusValue: CellFocus
    /// Parse-and-write. Called on submit and on focus loss — never per
    /// keystroke: a half-typed "1." must not be parsed and written back, or
    /// the field would rewrite itself and eat the decimal point.
    let commit: (String) -> Void

    /// The draft, kept only while the user is typing. nil = show the model's
    /// value.
    @State private var typed: String?
    /// The model's value when the draft started. If the model changes
    /// underneath (a quick-chip tap writes the RPE directly) the draft is
    /// stale and must not overwrite it.
    @State private var draftBase: String?

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var shown: String { typed ?? value }
    private var isEmpty: Bool { shown.isEmpty }
    /// The fixed numeric width, or nil for the flexible Notes column.
    private var cellWidth: CGFloat? { wide ? nil : fixedWidth }

    var body: some View {
        VStack(alignment: wide ? .leading : .center, spacing: 4) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                // Column titles are ONE line: a wrapped "Reps" put the s on its
                // own line beside a two-line Notes box (owner report, seen on
                // the Mac, 2026-10-23). Only the notes VALUE spans rows.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
            // The empty state is drawn as a sibling, not as the field's
            // `prompt:` — with a custom prompt style, iOS renders the text
            // being typed in the prompt's grey while the keyboard is up, so a
            // value you are entering looks like a placeholder.
            ZStack(alignment: wide ? (multiline ? .topLeading : .leading) : .center) {
                // Shown only while the box is empty, and gone the moment there
                // is a draft or a value. Delete the text and it comes back
                // (owner, 2026-09-25).
                if isEmpty {
                    Text(hint.isEmpty ? "—" : hint)
                        .font(valueFont ?? Typography.mono(valueSize))
                        .foregroundStyle(Palette.textSecondary.opacity(0.6))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        // Addressable by test: the hint is a separate Text, so
                        // this is the only way to assert what it says.
                        .accessibilityIdentifier(hint.isEmpty ? "blank-\(id)" : "hint-\(id)")
                }
                TextField(
                    "",
                    text: Binding(
                        get: { shown },
                        set: { newValue in
                            if typed == nil { draftBase = value }
                            typed = newValue
                        }
                    ),
                    axis: multiline ? .vertical : .horizontal
                )
                .textFieldStyle(.plain)
                .font(valueFont ?? Typography.mono(valueSize, .bold))
                .foregroundStyle(Palette.textPrimary)
                .keyboardType(keyboard)
                .multilineTextAlignment(alignment)
                .submitLabel(multiline ? .return : .done)
                .modifier(NotesLineLimit(multiline: multiline))
                // A multi-line box must be allowed to grow TALLER than its
                // frame; a one-line box keeps its fixed width so a short value
                // does not stretch the column.
                .fixedSize(horizontal: !wide, vertical: multiline)
                // A minimum width keeps an EMPTY box focusable: a zero-width
                // field takes the keyboard but gives no caret to aim at.
                // Narrow cells centre their value under their label; only the
                // wide Notes column is leading. A leading frame here pushed a
                // short typed value to the left edge of the box while the label
                // above it stayed centred (owner report, 2026-09-23).
                .frame(minWidth: cellWidth ?? 44,
                       maxWidth: wide ? .infinity : cellWidth,
                       alignment: wide ? .leading : .center)
                .focused(focus, equals: focusValue)
                .accessibilityIdentifier(id)
                // A vertical-axis field inserts a newline on Return; committing
                // there would close the box instead (owner request, 2026-10-23).
                .onSubmit { if !multiline { finishEditing() } }
                .onChange(of: isFocused) { _, focused in
                    if !focused { finishEditing() }
                }
            }
            // The Notes column indents its value by half the label's width so
            // the first character lands under the label's centre (owner,
            // 2026-09-24).
            .padding(.leading, wide ? NotesStyle.current.valueInset(wide: true) : 0)
        }
        .frame(minWidth: cellWidth ?? 44, maxWidth: wide ? .infinity : cellWidth,
               alignment: wide ? .leading : .center)
        // The whole box is the tap target, not just the glyphs.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = focusValue }
        // A row that leaves the screen (or a screen dismissed with the draft
        // still in @State) used to drop what was typed. Commit it on the way
        // out — same rule as losing focus (owner report, 2026-09-24).
        .onDisappear { finishEditing() }
        // The cell's own address: a screen that wants to scroll the focused
        // box above the keyboard does it by this value (ScrollViewReader,
        // 2026-10-13).
        .id(focusValue)
    }

    /// Commit the draft and go back to showing the model's value. The guard on
    /// `typed` keeps a focus/blur with no typing from writing (and saving) for
    /// nothing.
    private func finishEditing() {
        guard let draft = typed else { return }
        typed = nil
        let base = draftBase
        draftBase = nil
        guard value == base else { return }   // the model moved on: it wins
        commit(draft)
    }
}

/// A one-line inline text field for a labelled row — exercise note, workout
/// note, routine name/notes, routine set counts. Same rule as `InlineCell`:
/// the row is the input.
struct InlineTextField: View {
    let placeholder: String
    let id: String
    /// Canonical text, straight from the model.
    let text: String
    var keyboard: UIKeyboardType = .default
    var alignment: TextAlignment = .leading
    var font: Font = .body
    /// Set for notes that should grow over several lines; nil = one line.
    var axis: Axis? = nil
    var lineLimit: ClosedRange<Int> = 1...4
    let focus: FocusState<CellFocus?>.Binding
    let focusValue: CellFocus
    let commit: (String) -> Void

    @State private var typed: String?
    @State private var draftBase: String?

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var shown: String { typed ?? text }

    /// Where the placeholder sits, matching the field's own alignment.
    private var zAlignment: Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: axis == nil ? .leading : .topLeading
        }
    }

    var body: some View {
        // The placeholder is a sibling Text, not the field's `prompt:` — with a
        // custom prompt style, iOS renders text being typed in the prompt's
        // grey while the keyboard is up (see `InlineCell`).
        ZStack(alignment: zAlignment) {
            if shown.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Palette.textSecondary)
                    .allowsHitTesting(false)
            }
            TextField(
                "",
                text: Binding(
                    get: { shown },
                    set: { newValue in
                        if typed == nil { draftBase = text }
                        typed = newValue
                    }
                ),
                axis: axis ?? .horizontal
            )
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Palette.textPrimary)
            .keyboardType(keyboard)
            .multilineTextAlignment(alignment)
            .modifier(LineLimitIf(range: axis == nil ? nil : lineLimit))
            .labelsHidden()
            // Multi-line: Return inserts a newline and the box grows; the note
            // is committed on focus loss (owner request, 2026-10-23).
            .submitLabel(axis == nil ? .done : .return)
            .fixedSize(horizontal: false, vertical: axis != nil)
            .focused(focus, equals: focusValue)
            .accessibilityIdentifier(id)
            .onSubmit { if axis == nil { finishEditing() } }
            .onChange(of: isFocused) { _, focused in
                if !focused { finishEditing() }
            }
        }
        // THE bug behind the owner report of 2026-09-24 ("a note set in the
        // routine never appears"): the sheet's own Done button dismisses the
        // editor while the draft is still in @State, so `onChange(of:
        // isFocused)` never ran and the typed note was thrown away. Commit on
        // the way out.
        .onDisappear { finishEditing() }
        // Same address as `InlineCell`: the focused field can be scrolled
        // into view by its `CellFocus` (2026-10-13).
        .id(focusValue)
    }

    private func finishEditing() {
        guard let draft = typed else { return }
        typed = nil
        let base = draftBase
        draftBase = nil
        guard text == base else { return }
        commit(draft)
    }
}

/// Two lines minimum, twelve maximum, for a multi-line notes box: two lines is
/// the owner's default height, and the cap stops a pasted essay from pushing
/// the rest of the card off the screen.
private struct NotesLineLimit: ViewModifier {
    let multiline: Bool

    func body(content: Content) -> some View {
        if multiline {
            content.lineLimit(2...12)
        } else {
            content.lineLimit(1)
        }
    }
}

/// Applies a line limit only when the field is multi-line, so a one-line field
/// can grow with its content.
private struct LineLimitIf: ViewModifier {
    let range: ClosedRange<Int>?

    func body(content: Content) -> some View {
        if let range {
            content.lineLimit(range)
        } else {
            content
        }
    }
}

/// The keyboard's Done button, for the numeric pads (which have no return
/// key). One per screen; it clears whatever cell is focused.
struct KeyboardDoneButton: ToolbarContent {
    let focus: FocusState<CellFocus?>.Binding

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus.wrappedValue = nil }
                .accessibilityIdentifier("keyboard-done")
        }
    }
}

/// The keyboard's accessory bar for a screen whose boxes can be walked in
/// order (owner request, 2026-10-13 — the reference app's arrows): a chevron
/// each way to step to the previous / next box, then a check to close the
/// keyboard. One per screen.
///
/// The chevrons are disabled at the ends of the order, and when the focused
/// box is not part of it.
struct KeyboardCellBar: ToolbarContent {
    let focus: FocusState<CellFocus?>.Binding
    /// Every inline box on the screen, in the order they appear. The screen
    /// owns this list (`ActiveWorkoutView.focusOrder`); the bar only walks it.
    let order: [CellFocus]

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canStep(-1))
            .accessibilityLabel("Previous box")
            .accessibilityIdentifier("keyboard-prev")

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canStep(1))
            .accessibilityLabel("Next box")
            .accessibilityIdentifier("keyboard-next")

            Spacer()

            Button {
                focus.wrappedValue = nil
            } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")
            .accessibilityIdentifier("keyboard-done")
        }
    }

    /// Where the focused box sits in the order — nil when the focus is on a
    /// box this bar was not given.
    private var index: Int? {
        guard let current = focus.wrappedValue else { return nil }
        return order.firstIndex(of: current)
    }

    /// The buttons stay disabled at the ends of the order, so a dead press
    /// cannot be mistaken for a broken arrow.
    private func canStep(_ delta: Int) -> Bool {
        guard let i = index else { return false }
        return order.indices.contains(i + delta)
    }

    private func step(_ delta: Int) {
        guard let i = index, order.indices.contains(i + delta) else { return }
        focus.wrappedValue = order[i + delta]
    }
}
