import SwiftUI
import SwiftData

/// Reorder the exercises in an open workout (the card menu's "Move").
///
/// Reordering is a drag on a list with edit mode forced on, so there is no
/// "Edit"/"Done" toggle inside the sheet: the rows are draggable the moment it
/// opens, and everything is written back on Done.
struct MoveExercisesSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: Session?

    @State private var order: [ExerciseEntry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Palette.textSecondary)
                        Text(entry.exercise?.name ?? "Exercise")
                    }
                    .accessibilityIdentifier("move-row-\(entry.exercise?.name ?? "")")
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("move-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .accessibilityIdentifier("move-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            order = (session?.exerciseEntries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private func save() {
        for (index, entry) in order.enumerated() {
            entry.sortOrder = index
        }
        store.save()
        dismiss()
    }
}

/// The per-exercise charts, presented from the workout card's menu. The
/// statistics screen PUSHES `ExerciseDetailView`, which has no title-bar button
/// of its own; from a sheet it needs a way out that is not a swipe.
struct ExerciseChartsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exerciseName: exerciseName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("charts-done")
                    }
                }
        }
    }
}

/// Pick the end time for an open workout. Confirming it sets the time AND
/// finishes the session (owner request, 2026-09-24: tapping End Time should
/// "automatically mark the session as finished"), so the wording says so
/// rather than leaving the user to wonder what Done did.
struct EndTimePickerSheet: View {
    let initial: Date
    let onConfirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Starts at the current time (or the time already recorded).
    @State private var picked: Date = .now

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("End time", selection: $picked, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityIdentifier("end-time-picker")
                Text("Done finishes the workout and saves it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("End Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("end-time-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onConfirm(picked) }
                        .accessibilityIdentifier("end-time-done")
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { picked = initial }
    }
}
