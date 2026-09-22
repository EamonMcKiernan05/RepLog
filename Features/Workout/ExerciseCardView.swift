import SwiftUI
import SwiftData

/// One exercise card in the workout (plan §6.2): name + "…" menu, planned
/// scheme lines, the type-appropriate set rows, "Add Set", and the
/// per-exercise icon row (notes / history / PR).
struct ExerciseCardView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    let entry: ExerciseEntry
    var unit: WeightUnit
    var isEditing: Bool

    @State private var rpeSet: SetEntry?
    @State private var numberField: NumberField?
    @State private var notesSet: SetEntry?
    @State private var showNotes = false
    @State private var showHistory = false
    @State private var showPR = false
    @State private var confirmRemove = false

    enum NumberField: Identifiable {
        case weight(SetEntry), reps(SetEntry), time(SetEntry),
             distance(SetEntry), kcal(SetEntry)
        var id: ObjectIdentifier {
            switch self {
            case .weight(let s), .reps(let s), .time(let s),
                 .distance(let s), .kcal(let s): return ObjectIdentifier(s)
            }
        }
        var set: SetEntry {
            switch self {
            case .weight(let s), .reps(let s), .time(let s),
                 .distance(let s), .kcal(let s): return s
            }
        }
        var placeholder: String {
            switch self {
            case .weight: "Weight"
            case .reps: "Reps"
            case .time: "Time (s)"
            case .distance: "Distance (m)"
            case .kcal: "Calories"
            }
        }
        var isDecimal: Bool {
            switch self {
            case .weight, .time, .distance, .kcal: true
            case .reps: false
            }
        }
    }

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
                    onRPE: { rpeSet = set },
                    onNumber: { numberField = $0 },
                    onNotes: { notesSet = set }
                )
                Divider()
            }
            if isEditing {
                addSetRow
                Divider()
                iconRow
            }
        }
        .replogCard()
        .sheet(item: $rpeSet) { set in
            RPEInputSheet(set: set)
        }
        .sheet(item: $numberField) { field in
            NumberInputSheet(
                field: field,
                unit: unit,
                isDecimal: field.isDecimal,
                placeholder: field.placeholder
            )
        }
        .sheet(item: $notesSet) { set in
            SetNoteSheet(set: set)
        }
        .sheet(isPresented: $showNotes) {
            ExerciseNotesSheet(entry: entry)
        }
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
                    Button { showNotes = true } label: { Label("Notes", systemImage: "text.alignleft") }
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
    }

    private var iconRow: some View {
        HStack(spacing: 20) {
            Button { showNotes = true } label: {
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
            history: history
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
