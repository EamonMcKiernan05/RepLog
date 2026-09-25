import SwiftUI
import SwiftData

/// Routines tab (plan §6.3): list with name + chevron, + to add, Edit to
/// reorder/duplicate/delete.
struct RoutinesTabView: View {
    @Environment(DataStore.self) private var store
    @State private var editMode: EditMode = .inactive
    @State private var showAdd = false

    var body: some View {
        @Bindable var store = store
        // Read so this list re-renders when routines are inserted or removed
        // elsewhere — Duplicate on the detail view inserts a routine and only
        // `revision` changes (see DataStore.save).
        let _ = store.revision
        NavigationStack {
            List {
                ForEach(store.routines()) { routine in
                    NavigationLink {
                        RoutineDetailView(routine: routine)
                    } label: {
                        HStack {
                            Text(routine.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("routine-\(routine.name)")
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .background(Palette.bg)
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Same iOS 26 toolbar clipping as the Log's Edit button:
                    // an explicit capsule label, not .bordered + .capsule.
                    Button {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    } label: {
                        Text("Edit")
                            .font(.body)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Palette.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showAdd) {
                RoutineEditorSheet(routine: nil)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let routines = store.routines()
        for i in offsets {
            store.context.delete(routines[i])
        }
        store.save()
    }
}

/// Routine detail (plan §6.3): "Start this Workout", routine card (name,
/// target mode, notes), exercises card (name, N Sets, scheme lines).
struct RoutineDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    let routine: Routine
    @State private var showAddExercise = false
    @State private var editExercise: RoutineExercise?
    /// Which inline cell (the name, the notes) has the keyboard — the fields
    /// are typed in place, no sheets (see `CellFocus`).
    @FocusState private var focus: CellFocus?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Start this Workout
                Button {
                    startWorkout()
                } label: {
                    Text("Start this Workout")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.card, in: Capsule())
                }
                .padding(.horizontal, 16)

                // Routine card
                VStack(spacing: 0) {
                    InlineTextField(
                        placeholder: "Name",
                        id: "routine-name-field",
                        text: routine.name,
                        font: .body.weight(.semibold),
                        focus: $focus,
                        focusValue: CellFocus(owner: ObjectIdentifier(routine), field: .routineName),
                        // An empty name would leave the routines list and the
                        // navigation title blank, so a cleared box reverts.
                        commit: { text in
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            routine.name = trimmed
                            store.save()
                        }
                    )
                    .padding()
                    Divider()
                    HStack {
                        Text("Weight and Reps")
                        Spacer()
                        Text(routine.targetMode.rawValue)
                            .foregroundStyle(Palette.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        routine.targetMode = routine.targetMode == .latest ? .byRoutine : .latest
                        store.save()
                    }
                    .accessibilityIdentifier("routine-target-mode")
                    Divider()
                    InlineTextField(
                        placeholder: "Notes",
                        id: "routine-notes-field",
                        text: routine.notes,
                        focus: $focus,
                        focusValue: CellFocus(owner: ObjectIdentifier(routine), field: .notes),
                        commit: { text in
                            routine.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.save()
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .replogCard()

                // Exercises card
                VStack(spacing: 0) {
                    let exercises = routine.routineExercises.sorted(by: { $0.sortOrder < $1.sortOrder })
                    ForEach(Array(exercises.enumerated()), id: \.element.persistentModelID) { idx, re in
                        Button {
                            editExercise = re
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(re.exercise?.name ?? "Exercise")
                                        .font(.body.weight(.bold))
                                    Text("\(re.warmupSets + re.workingSets) Sets")
                                        .font(.subheadline)
                                    // The exercise's own note for this routine.
                                    // There is no scheme line any more: an
                                    // exercise here is a set count and a note
                                    // (owner, 2026-09-24).
                                    noteLine(re)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < exercises.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                    Button {
                        showAddExercise = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add Exercise")
                        }
                        .font(.body)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .replogCard()
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg)
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        focus = CellFocus(owner: ObjectIdentifier(routine), field: .routineName)
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) {
                        store.context.delete(routine)
                        store.save()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                // Named so the UI tests can reach Rename / Duplicate / Delete.
                .accessibilityIdentifier("routine-menu")
            }
            KeyboardDoneButton(focus: $focus)
        }
        .sheet(isPresented: $showAddExercise) {
            SelectExerciseSheet(
                title: "Add Exercise",
                onSelect: { exercise in
                    addExercise(exercise)
                }
            )
        }
        .sheet(item: $editExercise) { re in
            RoutineExerciseEditorSheet(routineExercise: re)
        }
    }

    /// The exercise's note for this routine, or nothing when it has none.
    /// Same type as the read-only note line on the workout card.
    @ViewBuilder
    private func noteLine(_ re: RoutineExercise) -> some View {
        if !re.notes.isEmpty {
            Text(re.notes)
                .font(.footnote)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }

    private func startWorkout() {
        let session = Session(date: .now, routineName: routine.name)
        var order = 0
        for re in routine.routineExercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let ex = re.exercise else { continue }
            let entry = ExerciseEntry(exercise: ex, sortOrder: order)
            // The routine's note for this exercise travels into the workout,
            // where the card shows it under the name (owner report,
            // 2026-09-24: the note set in the routine was dropped here).
            entry.notes = re.notes
            // Rows come from the set counts and nothing else: a routine
            // exercise is a set count and a note (owner, 2026-09-24), so a new
            // session starts with the right number of EMPTY rows and no
            // invented weight or reps.
            let total = re.warmupSets + re.workingSets
            for i in 0..<total {
                let set = SetEntry(setNumber: i + 1, setType: i < re.warmupSets ? .warmup : .working)
                entry.setEntries.append(set)
            }
            session.exerciseEntries.append(entry)
            order += 1
        }
        store.context.insert(session)
        store.save()
        router.startWorkout(session: session)
    }

    private func addExercise(_ exercise: Exercise) {
        let next = (routine.routineExercises.map { $0.sortOrder }.max() ?? -1) + 1
        let re = RoutineExercise(exercise: exercise, sortOrder: next, workingSets: 4)
        routine.routineExercises.append(re)
        store.save()
    }

    private func duplicate() {
        let copy = Routine(name: routine.name + " Copy",
                           sortOrder: (store.routines().map { $0.sortOrder }.max() ?? 0) + 1)
        copy.targetMode = routine.targetMode
        copy.notes = routine.notes
        var order = 0
        for re in routine.routineExercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let cre = RoutineExercise(
                exercise: re.exercise, sortOrder: order,
                warmupSets: re.warmupSets, workingSets: re.workingSets,
                notes: re.notes
            )
            copy.routineExercises.append(cre)
            order += 1
        }
        store.context.insert(copy)
        store.save()
    }
}

/// Routine exercise editor (plan §6.3, T3.3): warm-up sets, working sets,
/// scheme, per-exercise notes, replace, delete.
struct RoutineExerciseEditorSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let routineExercise: RoutineExercise
    @State private var showReplace = false
    /// The set counts are typed straight into their boxes (see `CellFocus`).
    @FocusState private var focus: CellFocus?

    private var owner: ObjectIdentifier { ObjectIdentifier(routineExercise) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Warm Up Sets") {
                        InlineTextField(
                            placeholder: "0",
                            id: "warmup-sets-field",
                            text: "\(routineExercise.warmupSets)",
                            keyboard: .numberPad,
                            alignment: .trailing,
                            font: Typography.mono(17),
                            focus: $focus,
                            focusValue: CellFocus(owner: owner, field: .warmup),
                            // Out-of-range or unparseable input is refused and
                            // the box snaps back to the stored count.
                            commit: { text in
                                guard let v = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
                                routineExercise.warmupSets = min(max(v, 0), 10)
                                store.save()
                            }
                        )
                        .frame(width: 64)
                    }
                    LabeledContent("Sets") {
                        InlineTextField(
                            placeholder: "0",
                            id: "working-sets-field",
                            text: "\(routineExercise.workingSets)",
                            keyboard: .numberPad,
                            alignment: .trailing,
                            font: Typography.mono(17),
                            focus: $focus,
                            focusValue: CellFocus(owner: owner, field: .working),
                            commit: { text in
                                guard let v = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
                                routineExercise.workingSets = min(max(v, 1), 20)
                                store.save()
                            }
                        )
                        .frame(width: 64)
                    }
                }
                // The read-only "Scheme" section was removed at the owner's
                // request (2026-09-23): it listed "Set 1  100 × 5" with no
                // controls, and nothing in the app could edit those pairs. The
                // `scheme` model field and the set prefill it drives in
                // StartWorkoutSheet are untouched.
                Section("Notes") {
                    InlineTextField(
                        placeholder: "Per-exercise notes",
                        id: "routine-exercise-notes-field",
                        text: routineExercise.notes,
                        axis: .vertical,
                        lineLimit: 1...4,
                        focus: $focus,
                        focusValue: CellFocus(owner: owner, field: .exerciseNote),
                        commit: { text in
                            routineExercise.notes = text
                            store.save()
                        }
                    )
                }
                Section {
                    Button("Replace Exercise") {
                        showReplace = true
                    }
                    Button(role: .destructive) {
                        routineExercise.routine?.routineExercises.removeAll { $0 === routineExercise }
                        store.context.delete(routineExercise)
                        store.save()
                        dismiss()
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .navigationTitle(routineExercise.exercise?.name ?? "Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Clearing focus first commits a note that is still being
                    // typed: Done used to dismiss the sheet and drop the draft
                    // (owner report, 2026-09-24).
                    Button("Done") {
                        focus = nil
                        dismiss()
                    }
                }
                KeyboardDoneButton(focus: $focus)
            }
            .sheet(isPresented: $showReplace) {
                SelectExerciseSheet(
                    title: "Replace Exercise",
                    onSelect: { exercise in
                        routineExercise.exercise = exercise
                        store.save()
                        dismiss()
                    }
                )
            }
        }
    }
}
