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
    @Environment(Settings.self) private var settings
    let entry: ExerciseEntry
    var unit: WeightUnit
    var isEditing: Bool
    /// Shared with the whole screen (see `CellFocus`).
    let focus: FocusState<CellFocus?>.Binding

    @State private var showHistory = false
    @State private var showPR = false
    @State private var showCharts = false
    @State private var showMove = false
    @State private var showReplace = false
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
        .sheet(isPresented: $showCharts) {
            NavigationStack {
                ExerciseDetailView(exerciseName: entry.exercise?.name ?? "")
            }
        }
        .sheet(isPresented: $showMove) {
            MoveExercisesSheet(session: entry.session)
        }
        .sheet(isPresented: $showReplace) {
            SelectExerciseSheet(title: "Replace Exercise", onSelect: { exercise in
                replace(with: exercise)
            })
        }
        .confirmationDialog("Remove this exercise?", isPresented: $confirmRemove) {
            Button("Delete", role: .destructive) { remove() }
                .accessibilityIdentifier("exercise-delete-confirm")
            Button("Cancel", role: .cancel) { }
        }
    }

    /// Swap the movement and keep the work already logged: sets, notes and the
    /// unit override belong to the entry, not to the exercise (same rule as the
    /// routine editor's Replace).
    private func replace(with exercise: Exercise) {
        entry.exercise = exercise
        store.save()
    }

    /// Per-exercise unit override; nil = follow the global setting. Storage
    /// stays kg either way (the CSV is frozen in kg).
    private func setUnit(_ unit: WeightUnit?) {
        entry.unitOverride = unit
        store.save()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.exercise?.name ?? "Exercise")
                    .font(.body.weight(.bold))
                // The line under the name is the exercise NOTE, shown and typed
                // in place — the position RepCount uses (owner request,
                // 2026-09-24). It replaced the routine's "1x4" scheme line,
                // which read as a set he had not entered.
                InlineTextField(
                    placeholder: "Add Note",
                    id: "exercise-note-field",
                    text: entry.notes,
                    font: .caption,
                    focus: focus,
                    focusValue: CellFocus(owner: owner, field: .exerciseNote),
                    commit: { text in
                        entry.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save()
                    }
                )
            }
            Spacer(minLength: 0)
            if isEditing { exerciseMenu }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// The card's "…" — the reference app's exercise panel (owner screenshot,
    /// 2026-09-24). It used to be a bare `Image` with no frame or content
    /// shape, so its hit area was the glyph itself and it read as a dead
    /// button; it now has a 44pt target and the full set of actions.
    private var exerciseMenu: some View {
        Menu {
            Button { showMove = true } label: { Label("Move", systemImage: "line.3.horizontal") }
            Button { showReplace = true } label: { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) { confirmRemove = true } label: { Label("Delete", systemImage: "xmark") }
            Divider()
            Button { focusExerciseNote() } label: { Label("Edit Note", systemImage: "square.and.pencil") }
            Divider()
            Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
            Button { showCharts = true } label: { Label("Charts", systemImage: "chart.xyaxis.line") }
            Button { showPR = true } label: { Label("Personal Records", systemImage: "star") }
            Divider()
            // Per-exercise kg/lb override (plan T5.5). Storage stays kg; only
            // the display and entry unit change.
            Menu {
                Button { setUnit(nil) } label: { Label("Default (\(settings.unit.rawValue))", systemImage: "arrow.uturn.backward") }
                Button { setUnit(.kg) } label: { Label("Kilograms", systemImage: "scalemass") }
                Button { setUnit(.lb) } label: { Label("Pounds", systemImage: "scalemass") }
            } label: {
                Label("Weight Unit", systemImage: "scalemass")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("exercise-menu")
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
