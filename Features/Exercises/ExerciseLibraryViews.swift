import SwiftUI
import SwiftData

/// Exercise library (plan §6.5): Edit Exercises (alphabetical, search, +)
/// and Edit Categories.
struct EditExercisesView: View {
    @Environment(DataStore.self) private var store
    @State private var search = ""
    @State private var showAdd = false
    @State private var editExercise: Exercise?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.textSecondary)
                    TextField("Search", text: $search)
                        .accessibilityIdentifier("library-search")
                }
                .padding(10)
                .background(Palette.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    let exercises = store.allExercises()
                        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    ForEach(exercises) { ex in
                        Button {
                            editExercise = ex
                        } label: {
                            HStack {
                                Text(ex.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("exercise-\(ex.name)")
                    }
                }
                .listStyle(.plain)
            }
            .background(Palette.bg)
            .navigationTitle("Edit Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddExerciseSheet { _ in }
            }
            .sheet(item: $editExercise) { ex in
                ExerciseEditorSheet(exercise: ex)
            }
        }
    }
}

/// Edit Categories (plan §6.5).
struct EditCategoriesView: View {
    @Environment(DataStore.self) private var store
    @State private var showAdd = false
    @State private var newCategory = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.categories()) { cat in
                    HStack {
                        Text(cat.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityIdentifier("category-\(cat.name)")
                }
                .onDelete { offsets in
                    let cats = store.categories()
                    for i in offsets { store.context.delete(cats[i]) }
                    store.save()
                }
            }
            .listStyle(.plain)
            .background(Palette.bg)
            .navigationTitle("Edit Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    TextField("Category name", text: $newCategory)
                        .padding()
                        .navigationTitle("New Category")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showAdd = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    let next = (store.categories().map { $0.sortOrder }.max() ?? -1) + 1
                                    let cat = Category(name: newCategory, sortOrder: next)
                                    store.context.insert(cat)
                                    store.save()
                                    newCategory = ""
                                    showAdd = false
                                }
                                .disabled(newCategory.isEmpty)
                            }
                        }
                }
                .presentationDetents([.height(200)])
            }
        }
    }
}

/// Add Exercise (plan §6.5): Name, Category, Exercise Type (the eight),
/// Single Leg/Single Arm, Transfer Data, Delete.
struct AddExerciseSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onDone: (Exercise) -> Void

    @State private var name = ""
    @State private var category: Category?
    @State private var type: ExerciseType = .weightReps
    @State private var singleLimb: SingleLimb = .defaultNo
    @State private var showCategoryPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("exercise-name")
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Category")
                            Spacer()
                            Text(category?.name ?? "Choose…")
                                .foregroundStyle(Palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .sheet(isPresented: $showCategoryPicker) {
                        NavigationStack {
                            List(store.categories()) { cat in
                                Button(cat.name) {
                                    category = cat
                                    showCategoryPicker = false
                                }
                            }
                            .navigationTitle("Category")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
                Section("Exercise Type") {
                    Picker("Type", selection: $type) {
                        ForEach(ExerciseType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Picker("Single Leg / Single Arm", selection: $singleLimb) {
                        ForEach([SingleLimb.defaultNo, .yes, .no], id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                    }
                    .disabled(name.isEmpty)
                    .tint(Palette.accent)
                }
            }
        }
    }

    private func save() {
        let ex = Exercise(
            name: name,
            type: type,
            singleLimb: singleLimb,
            builtin: false,
            sortOrder: (store.allExercises().count),
            category: category
        )
        store.context.insert(ex)
        store.save()
        onDone(ex)
        dismiss()
    }
}

/// Edit Exercise (plan §6.5): same fields + Transfer Exercise Data + Delete.
struct ExerciseEditorSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    @State private var name: String = ""
    @State private var type: ExerciseType = .weightReps
    @State private var singleLimb: SingleLimb = .defaultNo
    @State private var showCategoryPicker = false
    @State private var showTransfer = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("exercise-name")
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("Category")
                            Spacer()
                            Text(exercise.category?.name ?? "None")
                                .foregroundStyle(Palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .sheet(isPresented: $showCategoryPicker) {
                        NavigationStack {
                            List(store.categories()) { cat in
                                Button(cat.name) {
                                    exercise.category = cat
                                    store.save()
                                    showCategoryPicker = false
                                }
                            }
                            .navigationTitle("Category")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }
                Section("Exercise Type") {
                    Picker("Type", selection: $type) {
                        ForEach(ExerciseType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Picker("Single Leg / Single Arm", selection: $singleLimb) {
                        ForEach([SingleLimb.defaultNo, .yes, .no], id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Button("Transfer Exercise Data") {
                        showTransfer = true
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                    }
                    .tint(Palette.accent)
                }
            }
            .onAppear {
                name = exercise.name
                type = exercise.type
                singleLimb = exercise.singleLimb
            }
            .sheet(isPresented: $showTransfer) {
                TransferDataSheet(exercise: exercise)
            }
            .confirmationDialog("Delete this exercise? Its history stays in old sessions.", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    store.context.delete(exercise)
                    store.save()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        exercise.name = name
        exercise.type = type
        exercise.singleLimb = singleLimb
        store.save()
        dismiss()
    }
}

/// Move an exercise's history to another exercise (plan §6.5).
struct TransferDataSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        NavigationStack {
            List(store.allExercises().filter { $0.persistentModelID != exercise.persistentModelID }) { ex in
                Button(ex.name) {
                    transfer(to: ex)
                }
            }
            .navigationTitle("Transfer To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func transfer(to target: Exercise) {
        // Re-point every exercise entry that references this exercise.
        let sessions = store.sessions()
        for session in sessions {
            for entry in session.exerciseEntries where entry.exercise?.persistentModelID == exercise.persistentModelID {
                entry.exercise = target
            }
        }
        store.context.delete(exercise)
        store.save()
        dismiss()
    }
}
