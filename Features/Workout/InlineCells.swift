import SwiftUI

/// Which inline cell holds the keyboard, and on which object.
///
/// One `CellFocus?` per screen (shared down through the cards) so a single
/// keyboard "Done" clears whatever is being edited, and the exercise card can
/// reveal the RPE chips under the row that is actually being edited.
struct CellFocus: Hashable {
    enum Field: Hashable {
        case weight, reps, time, distance, kcal, rpe, notes
        case exerciseNote, workoutNote, routineName, warmup, working
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
    /// Fills the rest of the row (the Notes column).
    var wide = false
    var alignment: TextAlignment = .center
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

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
            // The empty state is drawn as a sibling, not as the field's
            // `prompt:` — with a custom prompt style, iOS renders the text
            // being typed in the prompt's grey while the keyboard is up, so a
            // value you are entering looks like a placeholder.
            ZStack(alignment: wide ? .leading : .center) {
                if isEmpty {
                    Text("—")
                        .font(Typography.mono(17))
                        .foregroundStyle(Palette.textSecondary.opacity(0.6))
                        .allowsHitTesting(false)
                }
                TextField(
                    "",
                    text: Binding(
                        get: { shown },
                        set: { newValue in
                            if typed == nil { draftBase = value }
                            typed = newValue
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(Typography.mono(17, .bold))
                .foregroundStyle(Palette.textPrimary)
                .keyboardType(keyboard)
                .multilineTextAlignment(alignment)
                .submitLabel(.done)
                .fixedSize(horizontal: !wide, vertical: false)
                // A minimum width keeps an EMPTY box focusable: a zero-width
                // field takes the keyboard but gives no caret to aim at.
                // Narrow cells centre their value under their label; only the
                // wide Notes column is leading. A leading frame here pushed a
                // short typed value to the left edge of the box while the label
                // above it stayed centred (owner report, 2026-09-23).
                .frame(minWidth: wide ? nil : 44,
                       maxWidth: wide ? .infinity : nil,
                       alignment: wide ? .leading : .center)
                .focused(focus, equals: focusValue)
                .accessibilityIdentifier(id)
                .onSubmit { finishEditing() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { finishEditing() }
                }
            }
        }
        .frame(minWidth: wide ? nil : 44, maxWidth: wide ? .infinity : nil)
        // The whole box is the tap target, not just the glyphs.
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = focusValue }
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
            .submitLabel(.done)
            .focused(focus, equals: focusValue)
            .accessibilityIdentifier(id)
            .onSubmit { finishEditing() }
            .onChange(of: isFocused) { _, focused in
                if !focused { finishEditing() }
            }
        }
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
