import SwiftUI
import SwiftData

/// Completed-session detail (plan §6.2, T2.2): read-only cards with set rows.
///
/// A session with no end time is an OPEN workout: `LogTabView` routes those to
/// `ActiveWorkoutView` instead, so this screen only ever shows finished
/// sessions. End Time still renders for an open one ("—") if it is reached with
/// one, so the row never disappears.
struct SessionDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var confirmDelete = false
    /// Read-only screen: no cell here is editable, but the cards still take a
    /// focus binding (see `CellFocus`).
    @FocusState private var focus: CellFocus?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionCard
                ForEach(session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { entry in
                    ExerciseCardView(
                        entry: entry,
                        unit: entry.displayUnit(global: settings.unit),
                        isEditing: false,
                        focus: $focus
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.bg)
        .navigationTitle(session.date.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                    .accessibilityIdentifier("delete-workout")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityIdentifier("session-detail-menu")
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
                .accessibilityIdentifier("delete-workout-confirm")
        }
    }

    private var sessionCard: some View {
        VStack(spacing: 0) {
            Text(session.routineName.isEmpty ? "Workout" : session.routineName)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Divider()
            if let st = session.startTime {
                infoRow("Start Time", st.formatted(date: .abbreviated, time: .shortened))
                Divider()
            }
            // Always present — "—" while the workout is open — so the section
            // cannot vanish on a session that has no end time yet.
            infoRow("End Time",
                    session.endTime?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            Divider()
            if let bw = session.bodyweightKg {
                infoRow("Bodyweight (kg)", String(format: "%.0f", bw))
                Divider()
            }
            infoRow("Notes", session.notes.isEmpty ? "Notes" : session.notes, isPlaceholder: session.notes.isEmpty)
        }
        .replogCard()
    }

    private func infoRow(_ label: String, _ value: String, isPlaceholder: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(isPlaceholder ? Palette.textSecondary : Palette.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Delete from the phone only. `SyncEngine.sessionDeleted` drops the session
    /// from the upload queue and never talks to the service, so a copy that has
    /// already reached the sync database stays there. The screen then leaves:
    /// leaving a deleted model on-screen is what made this look broken.
    private func delete() {
        sync.sessionDeleted(session)
        store.context.delete(session)
        store.save()
        dismiss()
    }
}
