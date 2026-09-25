import SwiftUI
import SwiftData

struct LogTabView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(SyncEngine.self) private var sync
    @State private var editMode: EditMode = .inactive
    @State private var showStartSheet = false
    @State private var showRepeatSheet = false
    /// The row waiting on the delete confirmation.
    @State private var pendingDelete: Session?
    @State private var confirmRowDelete = false

    private var sessions: [Session] { store.sessions() }

    private var months: [(title: String, sessions: [Session])] {
        let cal = Calendar.current
        var groups: [(key: (Int, Int), title: String, sessions: [Session])] = []
        for s in sessions {
            let c = cal.dateComponents([.year, .month], from: s.date)
            let key = (c.year ?? 0, c.month ?? 0)
            if let idx = groups.firstIndex(where: { $0.key == key }) {
                groups[idx].sessions.append(s)
            } else {
                let title = s.date.formatted(.dateTime.month(.wide).year())
                groups.append((key, title, [s]))
            }
        }
        return groups.map { ($0.title, $0.sessions) }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(months, id: \.title) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(month.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text("\(month.sessions.count) Workout\(month.sessions.count == 1 ? "" : "s")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .padding(.horizontal, 20)

                            VStack(spacing: 0) {
                                ForEach(Array(month.sessions.enumerated()), id: \.element.id) { idx, session in
                                    // Swipe left to delete this workout. Unlike
                                    // a set row, this asks first: a workout is
                                    // a whole session of work (owner,
                                    // 2026-09-25).
                                    Group {
                                    HStack(spacing: 0) {
                                        // Edit mode has something to do now: it
                                        // reveals a delete per row. It used to
                                        // flip editMode with nothing to act on
                                        // (this list is a ScrollView, not a
                                        // List), so tapping Edit appeared to do
                                        // nothing and the app looked as if it
                                        // could not delete a workout.
                                        if editMode == .active {
                                            Button {
                                                pendingDelete = session
                                                confirmRowDelete = true
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.body)
                                                    .foregroundStyle(Palette.destructive)
                                                    .frame(width: 48, height: 44)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("row-delete-\(session.id.prefix(8))")
                                            .accessibilityLabel("Delete workout")
                                        }
                                        // The AX identifier/label must sit on the
                                        // LINK, not inside its label: the row view
                                        // used to carry
                                        // .accessibilityElement(children: .combine),
                                        // which made the row swallow its own taps
                                        // (present in the AX tree, taps dead). The
                                        // combine modifier now lives nowhere.
                                        NavigationLink(value: session.id) {
                                            SessionRowView(session: session)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("session-row-\(session.id.prefix(8))")
                                        .accessibilityLabel(session.rowAccessibilityText)
                                    }
                                    }
                                    if idx < month.sessions.count - 1 {
                                        Divider().padding(.leading, editMode == .active ? 128 : 76)
                                    }
                                }
                            }
                            .replogCard()
                        }
                    }
                    if sessions.isEmpty {
                        ContentUnavailableView(
                            "No workouts yet",
                            systemImage: "book.closed",
                            description: Text("Tap + to start your first workout.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(.vertical, 8)
                // Value-based destination for the session rows below
                // (NavigationLink(value: session.id)). It must NOT share a
                // view with the item-based destination further down or SwiftUI
                // silently drops it and the row taps do nothing.
                //
                // EVERY session opens the same editor, finished or not (owner,
                // 2026-09-24: "update things so I can edit a finished workout
                // the same way I can an active one"). The editor knows which
                // state it is in: a finished record gets no finish control, no
                // Live Activity and no second Health write, and a correction
                // re-queues it for upload. The read-only detail screen is gone
                // with it — its one unique action (Delete Workout) moved into
                // the editor's menu.
                .navigationDestination(for: String.self) { id in
                    if let session = sessions.first(where: { $0.id == id }) {
                        ActiveWorkoutView(session: session)
                    }
                }
            }
            .background(Palette.bg)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // A .bordered/.capsule toolbar button gets clipped to a
                    // circle by the iOS 26 toolbar (it renders as a single
                    // "d") — an explicit capsule label lays out correctly and
                    // matches the reference screenshot.
                    Button {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    } label: {
                        Text(editMode == .active ? "Done" : "Edit")
                            .font(.body)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Palette.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-edit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        syncButton
                        Button {
                            showStartSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityIdentifier("plus")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            // The item-based destination (active workout) lives here; the
            // value-based one (session detail) is on the content VStack above.
            // Kept on separate views deliberately: one destination modifier per
            // view is the documented, unambiguous shape.
            .navigationDestination(item: $router.activeSession) { session in
                ActiveWorkoutView(session: session)
            }
            .sheet(isPresented: $showStartSheet) {
                StartWorkoutSheet()
            }
            .sheet(isPresented: $showRepeatSheet) {
                RepeatWorkoutSheet()
            }
            .confirmationDialog("Delete this workout?",
                                isPresented: $confirmRowDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePendingRow() }
                    .accessibilityIdentifier("row-delete-confirm")
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("It stays in the sync database if it has already been uploaded.")
            }
        }
    }

    /// The Log's sync control (manual sync, 2026-09-23). Shows real state, and
    /// keeps the "sync-now" identifier the offline drill taps.
    private var syncButton: some View {
        Button {
            sync.syncNow()
        } label: {
            HStack(spacing: 6) {
                if sync.isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(syncButtonTitle)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textPrimary)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(sync.isSyncing)
        .accessibilityIdentifier("sync-now")
        // No fixed accessibilityLabel: the button's label is its content, so
        // VoiceOver (and the offline drill's assertion) hear the real state —
        // "1 to sync", "Up to date · 2 minutes ago", "Auth failed — check your
        // token" — not a constant "Sync now".
    }

    private var syncButtonTitle: String {
        if sync.isSyncing { return "Syncing…" }
        if sync.outbox.queuedCount > 0 {
            let n = sync.outbox.queuedCount
            return "\(n) to sync"
        }
        // The engine's status text carries the rest: the auth-failure state,
        // "Sync off", and "Up to date · <relative time>" (or plain
        // "Up to date" before the first sync).
        return sync.statusText
    }

    /// Delete the pending row. Local only: `sessionDeleted` drops it from the
    /// upload queue and never calls the service, so a copy that already reached
    /// the sync database stays there.
    private func deletePendingRow() {
        guard let session = pendingDelete else { return }
        pendingDelete = nil
        if router.activeSession === session { router.activeSession = nil }
        sync.sessionDeleted(session)
        store.context.delete(session)
        store.save()
        if sessions.isEmpty { editMode = .inactive }
    }
}

/// Make Session usable as a navigation item (id: String).
