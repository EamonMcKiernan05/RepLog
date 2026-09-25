import SwiftUI
import SwiftData

/// "+" → new workout for today, optionally from a saved routine (plan §6.1, T2.3).
struct StartWorkoutSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var showRepeatSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        start(fresh: true)
                    } label: {
                        Label("New Workout (Today)", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("new-workout-today")
                    if !store.sessions().isEmpty {
                        Button {
                            showRepeatSheet = true
                        } label: {
                            Label("Repeat Last Workout", systemImage: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("repeat-last")
                    }
                }
                if !store.routines().isEmpty {
                    Section("From a Routine") {
                        ForEach(store.routines()) { routine in
                            Button {
                                start(from: routine)
                            } label: {
                                Label(routine.name, systemImage: "rectangle.stack")
                            }
                            .accessibilityIdentifier("routine-start-\(routine.name)")
                        }
                    }
                }
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showRepeatSheet) {
            RepeatWorkoutSheet()
        }
    }

    private func start(fresh: Bool) {
        let session = Session(date: .now, routineName: "")
        store.context.insert(session)
        store.save()
        dismiss()
        router.startWorkout(session: session)
    }

    private func start(from routine: Routine) {
        let session = Session(date: .now, routineName: routine.name)
        var order = 0
        for re in routine.routineExercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let ex = re.exercise else { continue }
            let entry = ExerciseEntry(exercise: ex, sortOrder: order)
            // The routine's note for this exercise travels into the workout
            // (owner report, 2026-09-24).
            entry.notes = re.notes
            // Rows come from the set counts and nothing else: a routine
            // exercise is a set count and a note, so a session starts with the
            // right number of EMPTY rows and no invented weight or reps.
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
        dismiss()
        router.startWorkout(session: session)
    }
}

/// Repeat the last workout (article 22): last performance vs exact weights.
struct RepeatWorkoutSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RepeatMode = .lastPerformance

    private var lastSession: Session? {
        store.sessions().first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let last = lastSession {
                    Text("Repeat \(last.date.formatted(.dateTime.month().day())) — \(last.routineName.isEmpty ? "Workout" : last.routineName)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                }
                Picker("Mode", selection: $mode) {
                    ForEach([RepeatMode.lastPerformance, .exactWeights], id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Button {
                    repeatWorkout()
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Repeat Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func repeatWorkout() {
        guard let last = lastSession else { return }
        let session = Session(date: .now, routineName: last.routineName)
        var order = 0
        for entry in last.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let ex = entry.exercise else { continue }
            let newEntry = ExerciseEntry(exercise: ex, sortOrder: order, supersetId: entry.supersetId)
            for set in entry.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let ns = SetEntry(setNumber: set.setNumber, setType: set.setType)
                switch mode {
                case .exactWeights:
                    ns.weightKg = set.weightKg
                    ns.reps = set.reps
                    ns.rpe = nil
                case .lastPerformance:
                    // Same weights/reps as last time (that is the performance).
                    ns.weightKg = set.weightKg
                    ns.reps = set.reps
                }
                newEntry.setEntries.append(ns)
            }
            session.exerciseEntries.append(newEntry)
            order += 1
        }
        store.context.insert(session)
        store.save()
        dismiss()
        router.startWorkout(session: session)
    }
}
