import SwiftUI
import SwiftData

struct LogTabView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var editMode: EditMode = .inactive
    @State private var showStartSheet = false
    @State private var showRepeatSheet = false

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
                                    if idx < month.sessions.count - 1 {
                                        Divider().padding(.leading, 76)
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
                .navigationDestination(for: String.self) { id in
                    if let session = sessions.first(where: { $0.id == id }) {
                        SessionDetailView(session: session)
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
                        Text("Edit")
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
        }
    }
}

/// Make Session usable as a navigation item (id: String).
