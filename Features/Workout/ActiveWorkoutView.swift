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
    @State private var confirmFinish = false
    /// The End Time row opens a clock picker; confirming it finishes the
    /// workout (owner request, 2026-09-24).
    @State private var showEndTime = false
    @State private var endTimeDraft: Date = .now
    @State private var confirmDelete = false
    /// True when this screen opened on an already-finished workout: every edit
    /// is then a correction to an existing record, not a live workout.
    @State private var editingExistingRecord = false
    /// Set on the way out when the workout is being DELETED.
    ///
    /// The re-queue in `.onDisappear` must not run then: it would queue an edit
    /// for a session that no longer exists, and touching a model after
    /// `context.delete` is a hard failure in SwiftData. Owner report,
    /// 2026-09-25: "deleting a workout from its own menu leaves it in the Log".
    @State private var deleting = false
    /// Which inline cell (a set cell, an exercise note, the workout note) has
    /// the keyboard. One value for the screen: every card shares it and the
    /// keyboard's Done button clears it.
    @FocusState private var focus: CellFocus?
    @State private var timer = RestTimerController()
    @State private var health = HealthService()

    /// A session with no end time is being worked on; one with an end time is a
    /// record being corrected. Same editor for both (owner, 2026-09-24).
    private var isFinished: Bool { session.endTime != nil }

    var body: some View {
        // One pass over history for the whole screen: every card's hint line is
        // built here, so a card does not fetch its own history on each render.
        let hints = hintsByEntry
        return ScrollView {
            VStack(spacing: 16) {
                sessionCard
                ForEach(session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { entry in
                    ExerciseCardView(
                        entry: entry,
                        unit: entry.displayUnit(global: settings.unit),
                        isEditing: true,
                        hints: hints[ObjectIdentifier(entry)] ?? [],
                        focus: $focus
                    )
                }
                addExerciseButton
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editingExistingRecord = isFinished
            // Reviewing an old workout must not look like training is happening:
            // no Live Activity, and no Health permission prompt.
            guard !isFinished else { return }
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
            // Only an OPEN workout can be finished. On a finished record the
            // back button is the way out: every edit is saved as it is made.
            if !isFinished {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // Ask first: the checkmark used to call finish() straight
                        // away and end the workout on a misplaced tap.
                        confirmFinish = true
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Palette.accent))
                    }
                    .accessibilityLabel("Finish workout")
                    .accessibilityIdentifier("finish-workout")
                }
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
                    .accessibilityLabel("Rest timer")
                    .accessibilityIdentifier("timer-button")
                    Menu {
                        Button { showAddExercise = true } label: {
                            Label("Add Exercise", systemImage: "plus")
                        }
                        Button {
                            focus = CellFocus(owner: ObjectIdentifier(session), field: .workoutNote)
                        } label: {
                            Label("Workout Notes", systemImage: "text.alignleft")
                        }
                        // Moved here from the read-only detail screen, which
                        // this editor replaced.
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete Workout", systemImage: "trash")
                        }
                        .accessibilityIdentifier("delete-workout")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("workout-menu")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            // The number pads have no return key: this is how the keyboard
            // closes.
            KeyboardDoneButton(focus: $focus)
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
        .sheet(isPresented: $showEndTime) {
            EndTimePickerSheet(initial: endTimeDraft) { picked in
                finish(at: endDate(from: picked))
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteWorkout() }
                .accessibilityIdentifier("delete-workout-confirm")
        }
        .onDisappear {
            // A correction to an existing record has to be re-queued for upload;
            // sync is manual, so nothing leaves the phone by itself. Never for a
            // delete: the session is gone (see `deleting`).
            if editingExistingRecord, !deleting { sync.sessionEdited(session) }
        }
        .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish", role: .destructive) { finish() }
                .accessibilityIdentifier("finish-confirm")
            Button("Cancel", role: .cancel) { }
                .accessibilityIdentifier("finish-cancel")
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
            endTimeRow
            Divider()
            bodyweightRow
            Divider()
            InlineTextField(
                placeholder: "Notes",
                id: "session-notes-field",
                text: session.notes,
                focus: $focus,
                focusValue: CellFocus(owner: ObjectIdentifier(session), field: .workoutNote),
                commit: { text in
                    session.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save()
                }
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .replogCard()
    }

    /// Tappable: opens the clock picker at the current time, and confirming it
    /// sets the end time AND finishes the session — the owner's flow for
    /// "I forgot to hit the checkmark, the workout ended at 14:05"
    /// (2026-09-24). The chevron is what makes it look tappable.
    private var endTimeRow: some View {
        Button {
            endTimeDraft = session.endTime ?? .now
            showEndTime = true
        } label: {
            HStack {
                Text("End Time")
                Spacer()
                Text(session.endTime?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .foregroundStyle(Palette.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("end-time-row")
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
        // One set row to start with, so the card is not empty and the RPE and
        // notes columns are reachable without tapping Add Set. It starts EMPTY:
        // the last time's numbers show behind the boxes as a hint, and only
        // what the owner types is recorded.
        entry.setEntries.append(SetEntry(setNumber: 1))
        session.exerciseEntries.append(entry)
        store.save()
    }

    /// Which past sessions the hints come from: the routine's own "weight and
    /// reps" setting (owner, 2026-09-25). A workout not started from a routine
    /// has no routine to ask, so it follows the last time the exercise was done.
    private var targetMode: TargetMode {
        guard !session.routineName.isEmpty else { return .latest }
        return store.routines().first { $0.name == session.routineName }?.targetMode ?? .latest
    }

    /// The hint line for every exercise in this workout.
    ///
    /// Empty on a FINISHED session: this is a record being corrected, not a
    /// workout being planned, and "last time" behind a box in a record you are
    /// fixing only invites mistakes.
    private var hintsByEntry: [ObjectIdentifier: [Targets.Hints]] {
        guard !isFinished else { return [:] }
        let past = store.sessions()
            .filter { $0.id != session.id }
            .flatMap { s in
                s.exerciseEntries.flatMap { e in
                    e.setEntries.map { st in
                        Targets.PastSet(exerciseName: e.exercise?.name ?? "",
                                        sessionDate: s.date,
                                        routineName: s.routineName,
                                        setNumber: st.setNumber,
                                        weightKg: st.weightKg,
                                        reps: st.reps,
                                        rpe: st.rpe,
                                        notes: st.notes)
                    }
                }
            }
        var out: [ObjectIdentifier: [Targets.Hints]] = [:]
        for entry in session.exerciseEntries {
            let name = entry.exercise?.name ?? ""
            out[ObjectIdentifier(entry)] = Targets.hints(
                mode: targetMode,
                routineName: session.routineName,
                exerciseName: name,
                history: past,
                unit: entry.displayUnit(global: settings.unit),
                setCount: entry.setEntries.count
            )
        }
        return out
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

    /// The session's day at the picked clock time. A workout that ran past
    /// midnight rolls to the next day rather than ending before it started.
    private func endDate(from picked: Date) -> Date {
        let cal = Calendar.current
        let day = session.startTime ?? session.date
        let hm = cal.dateComponents([.hour, .minute], from: picked)
        var d = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day) ?? picked
        if let start = session.startTime, d < start {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    /// Delete from the phone only: `SyncEngine.sessionDeleted` drops it from the
    /// upload queue and never talks to the service, so a copy that already
    /// reached the sync database stays there (owner rule, 2026-09-23).
    private func deleteWorkout() {
        deleting = true
        sync.sessionDeleted(session)
        store.context.delete(session)
        store.save()
        dismiss()
    }

    private func finish(at endTime: Date = .now) {
        // Correcting a finished record is not a finish: the end time is simply
        // changed, nothing goes to Health a second time, and there is no Live
        // Activity to end.
        let wasOpen = !isFinished
        session.endTime = endTime
        store.save()
        timer.stop()
        guard wasOpen else {
            sync.sessionEdited(session)
            dismiss()
            return
        }
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
