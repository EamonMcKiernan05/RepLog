import SwiftUI
import SwiftData

/// One exercise card in the workout (plan §6.2): name + "…" menu, planned
/// scheme lines, the type-appropriate set rows, "Add Set", the exercise note
/// and the per-exercise icon row (notes / history / PR).
///
/// Every value is typed straight into its box — the note line and the set
/// cells are all inputs, so nothing opens a sheet. The RPE quick chips (6,
/// 7, 7.5, 8, 8.5, 9) appear under the row whose RPE cell is being edited.
struct ExerciseCardView: View {
    @Environment(DataStore.self) private var store
    let entry: ExerciseEntry
    var unit: WeightUnit
    var isEditing: Bool
    /// Shared with the whole screen (see `CellFocus`).
    let focus: FocusState<CellFocus?>.Binding

    @State private var showHistory = false
    @State private var showPR = false
    @State private var confirmRemove = false

    private var owner: ObjectIdentifier { ObjectIdentifier(entry) }

    private static let rpeChips: [Double] = [6, 7, 7.5, 8, 8.5, 9]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ForEach(entry.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { set in
                SetRowView(
                    set: set,
                    type: entry.setType,
                    unit: unit,
                    isEditing: isEditing,
                    focus: focus
                )
                if isEditing, focus.wrappedValue == CellFocus(owner: ObjectIdentifier(set), field: .rpe) {
                    rpeChipRow(set)
                }
                Divider()
            }
            if isEditing {
                addSetRow
                Divider()
                noteRow
                Divider()
                iconRow
            } else if !entry.notes.isEmpty {
                // Read-only: the note still shows, just not as an input.
                HStack {
                    Text(entry.notes)
                        .font(.footnote)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                Divider()
            }
        }
        .replogCard()
        .sheet(isPresented: $showHistory) {
            ExerciseHistoryView(exerciseName: entry.exercise?.name ?? "")
        }
        .sheet(isPresented: $showPR) {
            PRView(exerciseName: entry.exercise?.name ?? "")
        }
        .confirmationDialog("Remove this exercise?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { remove() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise?.name ?? "Exercise")
                    .font(.body.weight(.bold))
                if let scheme = entry.plannedScheme, !scheme.isEmpty {
                    Text(scheme)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if isEditing {
                Menu {
                    Button { focusExerciseNote() } label: { Label("Notes", systemImage: "text.alignleft") }
                    Button { showHistory = true } label: { Label("History", systemImage: "chart.line.uptrend.xyaxis") }
                    Button { showPR = true } label: { Label("Personal Records", systemImage: "star") }
                    Button(role: .destructive) { confirmRemove = true } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var addSetRow: some View {
        Button {
            addSet()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add Set")
            }
            .font(.body)
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilityIdentifier("add-set")
    }

    /// The exercise note, typed in place (it used to be a sheet).
    private var noteRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.footnote)
                .foregroundStyle(Palette.accent)
            InlineTextField(
                placeholder: "Add Note",
                id: "exercise-note-field",
                text: entry.notes,
                font: .subheadline,
                focus: focus,
                focusValue: CellFocus(owner: owner, field: .exerciseNote),
                commit: { text in
                    entry.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save()
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Quick RPE chips, shown under the row being edited (the sheet's chips,
    /// now inline).
    private func rpeChipRow(_ set: SetEntry) -> some View {
        HStack(spacing: 8) {
            ForEach(ExerciseCardView.rpeChips, id: \.self) { chip in
                let label = SetRowView.rpeText(chip)
                Button {
                    set.rpe = chip
                    store.save()
                    // Drop the keyboard; any half-typed draft in the cell is
                    // discarded rather than overwriting the chip.
                    focus.wrappedValue = nil
                } label: {
                    Text(label)
                        .font(Typography.mono(15, .semibold))
                        .frame(minWidth: 44, minHeight: 34)
                        .background(
                            Capsule().fill(
                                set.rpe == chip
                                ? AnyShapeStyle(Palette.accent)
                                : AnyShapeStyle(Palette.control)
                            )
                        )
                        .foregroundStyle(set.rpe == chip ? .black : Palette.textPrimary)
                }
                .accessibilityIdentifier("rpe-chip-\(label)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var iconRow: some View {
        HStack(spacing: 20) {
            Button { focusExerciseNote() } label: {
                Image(systemName: "text.alignleft").foregroundStyle(Palette.accent)
            }
            Button { showHistory = true } label: {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Palette.accent)
            }
            Button { showPR = true } label: {
                Image(systemName: "star").foregroundStyle(Palette.accent)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// The notes buttons now put the caret in the inline note instead of
    /// opening a sheet.
    private func focusExerciseNote() {
        focus.wrappedValue = CellFocus(owner: owner, field: .exerciseNote)
    }

    private func addSet() {
        let next = (entry.setEntries.map { $0.setNumber }.max() ?? 0) + 1
        let set = SetEntry(setNumber: next)
        // Placeholder from targets (Latest mode by default).
        applyPlaceholder(to: set)
        entry.setEntries.append(set)
        store.save()
    }

    /// Fill a new set's weight/reps from the last time this exercise was
    /// done (Targets, Latest mode).
    private func applyPlaceholder(to set: SetEntry) {
        let history = historyForExercise()
        let ph = Targets.placeholder(
            mode: .latest,
            routineName: entry.session?.routineName ?? "",
            setIndex: set.setNumber - 1,
            history: Array(history)
        )
        if ph.weight != nil { set.weightKg = ph.weight }
        if ph.reps != nil { set.reps = ph.reps }
    }

    private func historyForExercise() -> [(weight: Double?, reps: Int?, rpe: Double?, routineName: String?)] {
        let name = entry.exercise?.name ?? ""
        return store.sessions()
            .filter { $0.id != entry.session?.id }
            .flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == name }
            .flatMap { entry in
                entry.setEntries.map {
                    ($0.weightKg, $0.reps, $0.rpe, entry.session?.routineName)
                }
            }
            .reversed()
    }

    private func remove() {
        entry.session?.exerciseEntries.removeAll { $0 === entry }
        store.context.delete(entry)
        store.save()
    }
}
