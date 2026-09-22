import SwiftUI
import SwiftData

/// Completed-session detail (plan §6.2, T2.2): read-only cards with set rows.
struct SessionDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(SyncEngine.self) private var sync
    let session: Session
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sessionCard
                ForEach(session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder })) { entry in
                    ExerciseCardView(
                        entry: entry,
                        unit: entry.displayUnit(global: settings.unit),
                        isEditing: false
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
            if let et = session.endTime {
                infoRow("End Time", et.formatted(date: .abbreviated, time: .shortened))
                Divider()
            }
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

    private func delete() {
        sync.sessionDeleted(session)
        store.context.delete(session)
        store.save()
    }
}
