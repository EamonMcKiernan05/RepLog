import SwiftUI
import SwiftData

/// The core screen (plan §6.2): teal finish check, centred date, timer +
/// overflow capsule; session card; one card per exercise; rest timer dock.
struct ActiveWorkoutView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    let session: Session

    @State private var showTimer = false
    @State private var showAddExercise = false
    @State private var showSessionNotes = false
    @State private var confirmFinish = false
    @State private var timer = RestTimerController()
    @State private var health = HealthService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionCard
                ForEach(session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { entry in
                    ExerciseCardView(
                        entry: entry,
                        unit: entry.displayUnit(global: settings.unit),
                        isEditing: true
                    )
                }
                addExerciseButton
            }
            .padding(.vertical, 8)
        }
        .background(Palette.bg)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Live Activity for the in-progress workout (Dynamic Island + lock
            // screen). Best-effort; no-op if unsupported.
            WorkoutLiveActivityController.start(
                workoutName: session.routineName,
                startDate: session.startTime ?? session.date,
                exerciseCount: session.exerciseEntries.count
            )
            // Ask for Health permissions once, when a workout is active and
            // Health is enabled (so the prompt is contextual, not at launch).
            if settings.healthEnabled {
                Task { await health.requestAuthorization() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    finish()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.accent))
                }
                .accessibilityLabel("Finish workout")
            }
            ToolbarItem(placement: .principal) {
                Text(session.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        showTimer = true
                    } label: {
                        Image(systemName: "timer")
                    }
                    Menu {
                        Button { showAddExercise = true } label: {
                            Label("Add Exercise", systemImage: "plus")
                        }
                        Button { showSessionNotes = true } label: {
                            Label("Workout Notes", systemImage: "text.alignleft")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showTimer {
                RestTimerView(controller: timer) {
                    showTimer = false
                }
                .transition(.move(edge: .bottom))
            }
        }
        .sheet(isPresented: $showAddExercise) {
            SelectExerciseSheet(
                allowSuperset: true,
                onSelect: { exercise in
                    addExercise(exercise)
                },
                onSuperset: { exercises in
                    addSuperset(exercises)
                }
            )
        }
        .sheet(isPresented: $showSessionNotes) {
            SessionNotesSheet(session: session)
        }
        .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish", role: .none) { finish() }
        }
        .onAppear {
            if session.startTime == nil {
                session.startTime = .now
                store.save()
            }
        }
    }

    private var sessionCard: some View {
        VStack(spacing: 0) {
            Text(session.routineName.isEmpty ? "Workout" : session.routineName)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            infoRow("Start Time", session.startTime?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            Divider()
            infoRow("End Time", session.endTime?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            Divider()
            bodyweightRow
            Divider()
            Button {
                showSessionNotes = true
            } label: {
                HStack {
                    Text(session.notes.isEmpty ? "Notes" : session.notes)
                        .foregroundStyle(session.notes.isEmpty ? Palette.textSecondary : Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .replogCard()
    }

    private var bodyweightRow: some View {
        HStack {
            Text("Bodyweight (kg)")
            Spacer()
            TextField("kg", value: Binding(
                get: { session.bodyweightKg ?? 0 },
                set: { v in setBodyweight(v) }
            ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .font(Typography.mono(17))
                .accessibilityIdentifier("bodyweight-field")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func setBodyweight(_ v: Double) {
        session.bodyweightKg = v > 0 ? v : nil
        // Record in bodyweight history (deduped by date).
        if v > 0, let ctx = DataStore.mainContextRef {
            let cal = Calendar.current
            let today = cal.startOfDay(for: .now)
            var d = FetchDescriptor<BodyweightEntry>(
                predicate: #Predicate { $0.date == today }
            )
            if let existing = try? ctx.fetch(d).first {
                existing.weightKg = v
            } else {
                ctx.insert(BodyweightEntry(date: today, weightKg: v))
            }
            try? ctx.save()
        }
    }

    private var addExerciseButton: some View {
        Button {
            showAddExercise = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add Exercise")
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("add-exercise")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func addExercise(_ exercise: Exercise) {
        let next = (session.exerciseEntries.map { $0.sortOrder }.max() ?? -1) + 1
        let entry = ExerciseEntry(exercise: exercise, sortOrder: next)
        // Seed a first set row prefilled from the last time this exercise was
        // done (plan §3.1 line 3 / T2.4: "placeholders from your last
        // performance"). Without this the card shows no rows and the RPE /
        // notes columns can't be reached until the user taps "Add Set".
        let first = SetEntry(setNumber: 1)
        entry.setEntries.append(first)   // establishes first.exerciseEntry == entry
        applyPlaceholder(to: first)      // now the back-reference resolves the name
        session.exerciseEntries.append(entry)
        store.save()
    }

    /// Fill a fresh set's weight/reps from the last time this exercise was
    /// done (Targets, Latest mode) — same rule "Add Set" uses.
    private func applyPlaceholder(to set: SetEntry) {
        let name = set.exerciseEntry?.exercise?.name ?? ""
        let history = store.sessions()
            .filter { $0.id != session.id }
            .flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == name }
            .flatMap { e in
                e.setEntries.map { ($0.weightKg, $0.reps, $0.rpe, e.session?.routineName) }
            }
            .reversed()
        let ph = Targets.placeholder(
            mode: .latest,
            routineName: session.routineName,
            setIndex: set.setNumber - 1,
            history: history
        )
        if ph.weight != nil { set.weightKg = ph.weight }
        if ph.reps != nil { set.reps = ph.reps }
    }

    private func addSuperset(_ exercises: [Exercise]) {
        let supID = "s\(session.exerciseEntries.filter { $0.supersetId != nil }.count / 1 + 1)"
        var order = (session.exerciseEntries.map { $0.sortOrder }.max() ?? -1) + 1
        for ex in exercises {
            let entry = ExerciseEntry(exercise: ex, sortOrder: order, supersetId: supID)
            session.exerciseEntries.append(entry)
            order += 1
        }
        store.save()
    }

    private func finish() {
        session.endTime = .now
        store.save()
        timer.stop()
        sync.sessionFinished(session)
        // End the Live Activity for this workout.
        WorkoutLiveActivityController.end()
        // Write to Apple Health (workout + bodyweight) when enabled.
        if settings.healthEnabled {
            let h = health
            let s = session
            Task {
                await h.saveWorkout(session: s)
                if let bw = s.bodyweightKg, bw > 0 {
                    await h.saveBodyweight(kg: bw)
                }
            }
        }
        dismiss()
    }
}

/// Session-level notes sheet.
struct SessionNotesSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            TextField("Workout note", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding()
                .onAppear { text = session.notes }
                .navigationTitle("Workout Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            session.notes = text
                            store.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
