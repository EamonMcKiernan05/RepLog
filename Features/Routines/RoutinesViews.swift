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
    @State private var showRename = false
    @State private var showNotes = false

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
                    HStack {
                        Text(routine.name)
                            .font(.body.weight(.semibold))
                        Spacer()
                        if showRename {
                            TextField("Name", text: Binding(
                                get: { routine.name },
                                set: { routine.name = $0; store.save() }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                    }
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
                    Divider()
                    HStack {
                        Text(routine.notes.isEmpty ? "Notes" : routine.notes)
                            .foregroundStyle(routine.notes.isEmpty ? Palette.textSecondary : Palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showNotes = true
                    }
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
                                    ForEach(re.schemeLines, id: \.self) { line in
                                        Text(line)
                                            .font(.caption)
                                            .foregroundStyle(Palette.textSecondary)
                                    }
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
        .background(Palette.bg)
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showRename.toggle() } label: { Label("Rename", systemImage: "pencil") }
                    Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) {
                        store.context.delete(routine)
                        store.save()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
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
        .sheet(isPresented: $showNotes) {
            RoutineNotesSheet(routine: routine)
        }
    }

    private func startWorkout() {
        let session = Session(date: .now, routineName: routine.name)
        var order = 0
        for re in routine.routineExercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let ex = re.exercise else { continue }
            let entry = ExerciseEntry(exercise: ex, sortOrder: order)
            let scheme = re.scheme
            let total = re.warmupSets + re.workingSets
            for i in 0..<max(total, scheme.count) {
                let set = SetEntry(setNumber: i + 1, setType: i < re.warmupSets ? .warmup : .working)
                if scheme.indices.contains(i) {
                    set.weightKg = scheme[i][0]
                    set.reps = Int(scheme[i][1])
                }
                entry.setEntries.append(set)
            }
            if !re.schemeLines.isEmpty {
                entry.plannedScheme = re.schemeLines.joined(separator: " / ")
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
        re.scheme = [[0, 4]]
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
                scheme: re.scheme, notes: re.notes
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Warm Up Sets") {
                        Stepper(value: Binding(
                            get: { routineExercise.warmupSets },
                            set: { routineExercise.warmupSets = $0; store.save() }
                        ), in: 0...10) {
                            Text("\(routineExercise.warmupSets)")
                                .monospacedDigit()
                        }
                    }
                    LabeledContent("Sets") {
                        Stepper(value: Binding(
                            get: { routineExercise.workingSets },
                            set: { routineExercise.workingSets = $0; store.save() }
                        ), in: 1...20) {
                            Text("\(routineExercise.workingSets)")
                                .monospacedDigit()
                        }
                    }
                }
                Section("Scheme") {
                    let scheme = routineExercise.scheme
                    ForEach(Array(scheme.enumerated()), id: \.offset) { idx, pair in
                        HStack {
                            Text("Set \(idx + 1)")
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text("\(Int(pair[0])) × \(Int(pair[1]))")
                                .monospacedDigit()
                        }
                    }
                }
                Section("Notes") {
                    TextField("Per-exercise notes", text: Binding(
                        get: { routineExercise.notes },
                        set: { routineExercise.notes = $0; store.save() }
                    ), axis: .vertical)
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
                    Button("Done") { dismiss() }
                }
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

/// Routine notes sheet (helper to present a text editor).
struct RoutineNotesSheet: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextField("Routine notes", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding()
                .onAppear { text = routine.notes }
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            routine.notes = text
                            store.save()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
