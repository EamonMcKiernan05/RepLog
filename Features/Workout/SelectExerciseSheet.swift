import SwiftUI
import SwiftData

/// Select Exercise sheet (plan §6.4): Cancel / title / + / …; search field;
/// category list; drill into a category for variants; bottom segmented
/// Regular | Superset.
///
/// Generic: used both to add exercises to a workout (single or superset) and
/// to pick/replace one exercise in a routine.
struct SelectExerciseSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var title: String = "Select Exercise"
    var allowSuperset: Bool = false
    var onSelect: (Exercise) -> Void
    var onSuperset: (([Exercise]) -> Void)? = nil

    @State private var search = ""
    @State private var mode: Mode = .regular
    @State private var selectedCategory: Category?
    @State private var selectedExercises: Set<String> = []
    @State private var showAddExercise = false

    enum Mode: String, CaseIterable {
        case regular = "Regular"
        case superset = "Superset"
    }

    var body: some View {
        NavigationStack {
            categoryList
                .safeAreaInset(edge: .bottom) {
                if allowSuperset {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Palette.bg)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showAddExercise = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        if mode == .superset && !selectedExercises.isEmpty {
                            Button("Add (\(selectedExercises.count))") {
                                addSuperset()
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet { _ in }
            }
        }
    }

    // MARK: - Category list

    private var categoryList: some View {
        VStack(spacing: 0) {
            searchField
            List(filteredCategories) { cat in
                NavigationLink(value: cat) {
                    HStack {
                        Text(cat.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityIdentifier("category-\(cat.name)")
            }
            .listStyle(.plain)
            if search.isEmpty && filteredCategories.isEmpty {
                ContentUnavailableView("No categories", systemImage: "list.bullet")
            }
        }
        .navigationDestination(for: Category.self) { cat in
            categoryDetail(cat)
        }
        }

    /// Categories matching the search: by category name or by any contained
    /// exercise name, so "Squat" surfaces the "Squats" category.
    private var filteredCategories: [Category] {
        let cats = store.categories()
        guard !search.isEmpty else { return cats }
        return cats.filter { cat in
            cat.name.localizedCaseInsensitiveContains(search)
                || cat.exercises.contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
            TextField("Search Exercises", text: $search)
                .accessibilityIdentifier("exercise-search")
        }
        .padding(10)
        .background(Palette.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Category detail (variants)

    private func categoryDetail(_ cat: Category) -> some View {
        VStack(spacing: 0) {
            searchField
            List {
                let exercises = cat.exercises
                    .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    .sorted(by: { $0.name < $1.name })
                ForEach(exercises) { ex in
                    exerciseRow(ex)
                }
            }
            .listStyle(.plain)
        }
        .onAppear { selectedCategory = nil }
    }

    @ViewBuilder
    private func exerciseRow(_ ex: Exercise) -> some View {
        if allowSuperset && mode == .superset {
            HStack {
                Image(systemName: selectedExercises.contains(ex.name) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedExercises.contains(ex.name) ? Palette.accent : Palette.textSecondary)
                Text(ex.name)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedExercises.contains(ex.name) {
                    selectedExercises.remove(ex.name)
                } else {
                    selectedExercises.insert(ex.name)
                }
            }
        } else {
            Button {
                onSelect(ex)
                dismiss()
            } label: {
                HStack {
                    Text(ex.name)
                    Spacer()
                    if ex.builtin {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .accessibilityIdentifier("pick-\(ex.name)")
        }
    }

    // MARK: - Actions

    private func addSuperset() {
        let picked = selectedExercises.sorted().compactMap { store.exercise(named: $0) }
        onSuperset?(picked)
        selectedExercises.removeAll()
        dismiss()
    }
}
