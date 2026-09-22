import SwiftUI
import SwiftData

struct LogTabView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var editMode: EditMode = .inactive
    @State private var showStartSheet = false
    @State private var showRepeatSheet = false
    @State private var detailSession: Session?

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
                                    Button {
                                        detailSession = session
                                    } label: {
                                        SessionRowView(session: session)
                                    }
                                    .buttonStyle(.plain)
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
            }
            .background(Palette.bg)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showStartSheet = true
                        } label: {
                            Label("New Workout", systemImage: "plus")
                        }
                        if !sessions.isEmpty {
                            Button {
                                showRepeatSheet = true
                            } label: {
                                Label("Repeat Last Workout", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationDestination(item: $detailSession) { session in
                SessionDetailView(session: session)
            }
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

/// Make Session usable as a navigation item.
extension Session: Identifiable {}
