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

    private var sessions: [Session] {
        // Read the store's change signal, or the List has nothing to observe:
        // a delete performed while this view was covered by the pushed editor
        // left the row it should have removed (owner report, 2026-09-25 —
        // "deleting a workout from its own menu leaves it in the Log"). The
        // ScrollView this replaced happened to re-evaluate; the List does not.
        _ = store.revision
        return store.sessions()
    }

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
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "book.closed",
                        description: Text("Tap + to start your first workout.")
                    )
                } else {
                    // A real List, not a hand-built ScrollView: that is what
                    // makes the swipe to delete the system's own (owner,
                    // 2026-09-25: "i want to be able to swipe right to left on
                    // the set row to delete it … same with deleting an entire
                    // session in the log view, however that should come with a
                    // confirmation box"). Every hand-rolled gesture lost to the
                    // row's own tap: a row has to be tappable to open the
                    // workout, and in a ScrollView the two claims to the touch
                    // fight — the row slid aside, or navigated instead, never
                    // both.
                    List {
                        ForEach(months, id: \.title) { month in
                            Section {
                                ForEach(month.sessions) { session in
                                    sessionRow(session)
                                }
                            } header: {
                                HStack {
                                    Text(month.title)
                                    Spacer()
                                    Text("\(month.sessions.count) Workout\(month.sessions.count == 1 ? "" : "s")")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                                // A List uppercases its headers by default;
                                // the reference screenshot does not.
                                .textCase(nil)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .listRowSpacing(0)
                    // The rows carry their own padding (SessionRowView): a
                    // default minimum height would add a second helping.
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
            // Value-based destination for the session rows
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
                    // A single +, as asked (owner, 2026-09-25: "remove the 'n
                    // to sync' button on the top of the log page. Just make it
                    // a single + button"). The sync control moved to Profile:
                    // sync is manual, so it needs a home somewhere.
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
            // The item-based destination (active workout) lives here; the
            // value-based one (session detail) is on the content above.
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

    /// One session row.
    ///
    /// The trash button is a SIBLING of the link, not inside its label: inside
    /// a button's label it never receives the tap (see the
    /// row-swallows-its-own-taps note in SessionRowView). Edit mode keeps this
    /// control rather than the List's own, so the identifier the offline drill
    /// taps stays put.
    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 0) {
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
            // The AX identifier/label must sit on the LINK, not inside its
            // label: the row view used to carry
            // .accessibilityElement(children: .combine), which made the row
            // swallow its own taps (present in the AX tree, taps dead).
            NavigationLink(value: session.id) {
                SessionRowView(session: session)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session-row-\(session.id.prefix(8))")
            .accessibilityLabel(session.rowAccessibilityText)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Palette.card)
        // Swipe left to delete, and it ASKS first: a workout is a whole
        // session of work, unlike a set row (owner, 2026-09-25). No full-swipe
        // delete either — the confirmation is the point, so the press is
        // required.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = session
                confirmRowDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("swipe-delete-\(session.id.prefix(8))")
        }
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
