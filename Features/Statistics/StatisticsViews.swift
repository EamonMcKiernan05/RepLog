import SwiftUI
import SwiftData
import Charts

/// Statistics hub (plan §6.7): Exercises, Categories, Overall Statistics,
/// then Export. Ours ships unlocked.
struct StatisticsTabView: View {
    @Environment(DataStore.self) private var store
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Exercises") {
                        ExerciseStatsList()
                    }
                    NavigationLink("Categories") {
                        CategoryStatsList()
                    }
                }
                Section("Overall Statistics") {
                    ForEach(OverallMetric.allCases, id: \.self) { metric in
                        NavigationLink(metric.title) {
                            OverallMetricView(metric: metric)
                        }
                    }
                }
                Section {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .background(Palette.bg)
            .navigationTitle("Statistics")
            // Registered at the stack root so the pushed ExerciseStatsList's
            // value links resolve.
            .navigationDestination(for: String.self) { name in
                ExerciseDetailView(exerciseName: name)
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
        }
    }
}

enum OverallMetric: String, CaseIterable, Identifiable {
    case workoutDuration, volume, totalSets, totalReps, repsPerSet, bodyweight, workouts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .workoutDuration: "Workout Duration"
        case .volume: "Volume"
        case .totalSets: "Total Sets"
        case .totalReps: "Total Reps"
        case .repsPerSet: "Reps per Set"
        case .bodyweight: "Bodyweight"
        case .workouts: "Number of Workouts"
        }
    }

    var unit: String {
        switch self {
        case .workoutDuration: "min"
        case .volume: "kg"
        case .totalSets: "sets"
        case .totalReps: "reps"
        case .repsPerSet: "reps"
        case .bodyweight: "kg"
        case .workouts: ""
        }
    }
}

/// One overall-metric screen: chart + range picker + grouping picker +
/// actual/trend toggles (plan §6.7, T5.1/T5.2).
struct OverallMetricView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    let metric: OverallMetric

    @State private var range: ChartRange = .year
    @State private var grouping: Grouping = .week
    @State private var showActual: Bool = true
    @State private var showTrend: Bool = true
    @State private var selectedDate: Date?

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "1M", quarter = "3M", half = "6M", year = "1Y", all = "All"
        var id: String { rawValue }
    }
    enum Grouping: String, CaseIterable, Identifiable {
        case session = "Session", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }
    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var points: [ChartPoint] {
        let sessions = store.sessions()
        let cal = Calendar.current
        let now = Date()
        let filtered: [Session]
        switch range {
        case .month: filtered = sessions.filter { cal.date(byAdding: .month, value: -1, to: now)! <= $0.date }
        case .quarter: filtered = sessions.filter { cal.date(byAdding: .month, value: -3, to: now)! <= $0.date }
        case .half: filtered = sessions.filter { cal.date(byAdding: .month, value: -6, to: now)! <= $0.date }
        case .year: filtered = sessions.filter { cal.date(byAdding: .year, value: -1, to: now)! <= $0.date }
        case .all: filtered = sessions
        }
        // Bucket by grouping.
        var buckets: [Date: [Session]] = [:]
        for s in filtered {
            let key: Date
            switch grouping {
            case .session: key = s.date
            case .week: key = cal.dateInterval(of: .weekOfYear, for: s.date)?.start ?? s.date
            case .month: key = cal.date(from: cal.dateComponents([.year, .month], from: s.date)) ?? s.date
            case .year: key = cal.date(from: cal.dateComponents([.year], from: s.date)) ?? s.date
            }
            buckets[key, default: []].append(s)
        }
        return buckets.map { key, ss in
            ChartPoint(date: key, value: value(for: ss))
        }
        .sorted { $0.date < $1.date }
    }

    private func value(for sessions: [Session]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        switch metric {
        case .workoutDuration:
            return sessions.reduce(0) { $0 + $1.duration / 60 }
        case .volume:
            return sessions.reduce(0) { acc, s in
                acc + s.exerciseEntries.flatMap { $0.setEntries }.reduce(0) { a, set in
                    a + Metrics.setVolume(
                        type: set.exerciseEntry?.setType ?? .weightReps,
                        weightKg: set.weightKg, reps: set.reps, durationS: set.durationS,
                        bodyweightKg: s.bodyweightKg
                    )
                }
            }
        case .totalSets:
            return Double(sessions.flatMap { $0.exerciseEntries }.reduce(0) { $0 + $1.setEntries.count })
        case .totalReps:
            return Double(sessions.flatMap { $0.exerciseEntries }.flatMap { $0.setEntries }
                .compactMap { $0.reps }.reduce(0, +))
        case .repsPerSet:
            let sets = sessions.flatMap { $0.exerciseEntries }.flatMap { $0.setEntries }
            let reps = sets.compactMap { $0.reps }.reduce(0, +)
            let n = sets.compactMap { $0.reps }.count
            return n > 0 ? Double(reps) / Double(n) : 0
        case .bodyweight:
            return sessions.compactMap { $0.bodyweightKg }.last ?? 0
        case .workouts:
            return Double(sessions.count)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Pickers
            HStack {
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Group", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)

            // Toggles
            HStack {
                Toggle("Actual", isOn: $showActual)
                Toggle("Trend", isOn: $showTrend)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)

            // Chart
            if points.isEmpty {
                ContentUnavailableView("No data yet", systemImage: "chart.bar")
            } else {
                Chart {
                    if showActual {
                        ForEach(points) { p in
                            LineMark(x: .value("Date", p.date), y: .value(metric.title, p.value))
                                .foregroundStyle(Palette.accent)
                            PointMark(x: .value("Date", p.date), y: .value(metric.title, p.value))
                                .foregroundStyle(Palette.accent)
                                .symbolSize(selected?.id == p.id ? 120 : 40)
                        }
                    }
                    if showTrend, points.count >= 2 {
                        ForEach(trendPoints) { p in
                            LineMark(x: .value("Date", p.date), y: .value("Trend", p.value))
                                .foregroundStyle(Palette.accent.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5]))
                        }
                    }
                    if let sel = selected {
                        RuleMark(x: .value("Date", sel.date))
                            .foregroundStyle(Palette.textSecondary.opacity(0.4))
                            .annotation(position: .top) {
                                VStack(spacing: 2) {
                                    Text(sel.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                        .font(.caption2)
                                    Text(String(format: "%.0f %@", sel.value, metric.unit))
                                        .font(.caption.weight(.bold))
                                }
                                .padding(6)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 260)
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .background(Palette.bg)
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            showActual = settings.showActualData
            showTrend = settings.showTrend
        }
        .onChange(of: showActual) { _, v in settings.showActualData = v }
        .onChange(of: showTrend) { _, v in settings.showTrend = v }
    }

    private var selected: ChartPoint? {
        guard let d = selectedDate else { return nil }
        return points.min(by: {
            abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
        })
    }

    /// Simple linear-regression trend line.
    private var trendPoints: [ChartPoint] {
        guard points.count >= 2 else { return [] }
        let n = Double(points.count)
        let xs = points.enumerated().map { Double($0.offset) }
        let ys = points.map { $0.value }
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else { return [] }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return points.map { p in
            let i = Double(points.firstIndex(where: { $0.id == p.id }) ?? 0)
            return ChartPoint(date: p.date, value: intercept + slope * i)
        }
    }
}

/// Per-exercise stats list (plan §6.7).
struct ExerciseStatsList: View {
    @Environment(DataStore.self) private var store

    private var names: [String] {
        var seen = Set<String>()
        let out: [String] = store.sessions()
            .flatMap { $0.exerciseEntries }
            .compactMap { $0.exercise?.name }
            .filter { seen.insert($0).inserted }
            .sorted()
        return out
    }

    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                NavigationLink(value: name) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        Text("\(setCount(name)) sets · \(String(format: "%.0f", volume(name))) kg")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        // The destination is registered on the TAB ROOT (StatisticsTabView),
        // not here: a .navigationDestination declared inside a pushed view is
        // not picked up (the row then highlights and nothing pushes — same
        // class of bug as the Log rows).
    }

    private func setCount(_ name: String) -> Int {
        store.sessions().flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == name }
            .reduce(0) { $0 + $1.setEntries.count }
    }

    private func volume(_ name: String) -> Double {
        store.sessions().reduce(0) { acc, s in
            acc + s.exerciseEntries
                .filter { $0.exercise?.name == name }
                .flatMap { $0.setEntries }
                .reduce(0) { a, set in
                    a + Metrics.setVolume(
                        type: set.exerciseEntry?.setType ?? .weightReps,
                        weightKg: set.weightKg, reps: set.reps, durationS: set.durationS,
                        bodyweightKg: s.bodyweightKg
                    )
                }
        }
    }
}

/// Per-category stats list.
struct CategoryStatsList: View {
    @Environment(DataStore.self) private var store

    private var names: [String] {
        var seen = Set<String>()
        return store.sessions()
            .flatMap { $0.exerciseEntries }
            .compactMap { $0.exercise?.category?.name }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Text("\(setCount(name)) sets")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setCount(_ name: String) -> Int {
        store.sessions().flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.category?.name == name }
            .reduce(0) { $0 + $1.setEntries.count }
    }
}

/// One exercise's history + charts (plan §6.7, T2.9, T5.3).
struct ExerciseDetailView: View {
    @Environment(DataStore.self) private var store
    let exerciseName: String
    @State private var showPR = false

    private var sessions: [Session] {
        store.sessions().filter {
            $0.exerciseEntries.contains { $0.exercise?.name == exerciseName }
        }
    }

    private var sets: [SetEntry] {
        sessions.flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == exerciseName }
            .flatMap { $0.setEntries }
    }

    private var volumePoints: [(date: Date, value: Double)] {
        sessions.map { s in
            (s.date, s.exerciseEntries
                .filter { $0.exercise?.name == exerciseName }
                .flatMap { $0.setEntries }
                .reduce(0) { a, set in
                    a + Metrics.setVolume(
                        type: set.exerciseEntry?.setType ?? .weightReps,
                        weightKg: set.weightKg, reps: set.reps, durationS: set.durationS,
                        bodyweightKg: s.bodyweightKg
                    )
                })
        }
    }

    private var e1rmPoints: [(date: Date, value: Double)] {
        sessions.compactMap { s -> (Date, Double)? in
            let best = s.exerciseEntries
                .filter { $0.exercise?.name == exerciseName }
                .flatMap { $0.setEntries }
                .compactMap { Metrics.e1RM(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }
                .max()
            return best.map { (s.date, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Volume chart
                GroupBox("Volume") {
                    if volumePoints.isEmpty {
                        Text("No data").foregroundStyle(Palette.textSecondary)
                    } else {
                        Chart(Array(volumePoints), id: \.date) { p in
                            BarMark(x: .value("Date", p.date, unit: .day),
                                    y: .value("Volume", p.value))
                                .foregroundStyle(Palette.accent)
                        }
                        .frame(height: 180)
                    }
                }
                // e1RM chart
                GroupBox("e1RM (Brzycki)") {
                    if e1rmPoints.isEmpty {
                        Text("No data").foregroundStyle(Palette.textSecondary)
                    } else {
                        Chart(Array(e1rmPoints), id: \.date) { p in
                            LineMark(x: .value("Date", p.date, unit: .day),
                                     y: .value("e1RM", p.value))
                                .foregroundStyle(Palette.accent)
                            PointMark(x: .value("Date", p.date, unit: .day),
                                      y: .value("e1RM", p.value))
                                .foregroundStyle(Palette.accent)
                        }
                        .frame(height: 180)
                    }
                }
                Button("Personal Records") {
                    showPR = true
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent)
            }
            .padding()
        }
        .background(Palette.bg)
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPR) {
            PRView(exerciseName: exerciseName)
        }
    }
}

/// Personal records (plan §6.7, T5.3): best per rep range, seasonal bests,
/// session records.
struct PRView: View {
    @Environment(DataStore.self) private var store
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss

    private var sessions: [Session] {
        store.sessions().filter {
            $0.exerciseEntries.contains { $0.exercise?.name == exerciseName }
        }
    }

    private var sets: [SetEntry] {
        sessions.flatMap { $0.exerciseEntries }
            .filter { $0.exercise?.name == exerciseName }
            .flatMap { $0.setEntries }
    }

    private var years: [Int] {
        var seen = Set<Int>()
        return sessions
            .map { Calendar.current.component(.year, from: $0.date) }
            .filter { seen.insert($0).inserted }
            .sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Best per rep range") {
                    ForEach(Metrics.repRanges, id: \.self) { range in
                        if let best = Metrics.bestE1RM(sets: sets, inRange: range) {
                            HStack {
                                Text("\(Metrics.rangeLabel(range)) reps")
                                Spacer()
                                Text(String(format: "%.1f kg", best))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
                Section("Seasonal bests") {
                    ForEach(years, id: \.self) { year in
                        if let best = Metrics.seasonalBest(
                            sessions: sessions, year: year,
                            exerciseName: exerciseName
                        ) {
                            HStack {
                                Text(String(year))
                                Spacer()
                                Text(String(format: "%.1f kg", best))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
                if let records = Metrics.sessionRecords(sessions: sessions, exerciseName: exerciseName) {
                    Section("Session records") {
                        HStack {
                            Text("Max reps")
                            Spacer()
                            Text("\(records.maxReps.value) reps · \(records.maxReps.session.date.formatted(.dateTime.month().day()))")
                                .font(.caption)
                        }
                        HStack {
                            Text("Max sets")
                            Spacer()
                            Text("\(records.maxSets.value) sets · \(records.maxSets.session.date.formatted(.dateTime.month().day()))")
                                .font(.caption)
                        }
                        HStack {
                            Text("Max volume")
                            Spacer()
                            Text(String(format: "%.0f kg · %@", records.maxVolume.value,
                                        records.maxVolume.session.date.formatted(.dateTime.month().day())))
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Exercise history from the workout screen (plan §6.7, T2.9).
struct ExerciseHistoryView: View {
    @Environment(DataStore.self) private var store
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss

    private var sessions: [Session] {
        store.sessions().filter {
            $0.exerciseEntries.contains { $0.exercise?.name == exerciseName }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { s in
                    let entry = s.exerciseEntries.first { $0.exercise?.name == exerciseName }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.date.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                            .font(.subheadline.weight(.semibold))
                        ForEach(entry?.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) ?? []) { set in
                            HStack {
                                Text("Set \(set.setNumber)")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text(setText(set))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func setText(_ set: SetEntry) -> String {
        var parts: [String] = []
        if let w = set.weightKg { parts.append("\(Int(w))kg") }
        if let r = set.reps { parts.append("\(r) reps") }
        if let rpe = set.rpe { parts.append("RPE \(rpe)") }
        return parts.joined(separator: " · ")
    }
}

/// CSV export (plan §6.7, T5.4): produces the same bytes the sync engine sends.
struct ExportSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Exports all sessions in the frozen sync schema — the same bytes lift-sync stores.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Share CSV", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .padding(.horizontal, 24)
                } else {
                    Button {
                        export()
                    } label: {
                        Text("Export")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .padding(.horizontal, 24)
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func export() {
        let sessions = store.sessions()
        let csv = CSVCodec.encode(sessions: sessions)
        let url = URL.temporaryDirectory
            .appendingPathComponent("RepLog-\(CSVCodec.date(.now)).csv")
        do {
            try csv.data(using: .utf8)!.write(to: url)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
