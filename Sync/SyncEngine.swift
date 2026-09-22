import Foundation
import SwiftData
import Network

/// Orchestrates the outbox + client (plan §4.3, §7.3 T7.3).
///
/// iOS gives no "the moment connectivity returns" trigger, so a queued
/// session is uploaded on: the next foreground run, a manual "Sync now",
/// or an opportunistic background refresh. Sessions are never lost.
@Observable
final class SyncEngine {
    let client = LiftSyncClient()
    private let store: DataStore
    private let settings: Settings
    private var pathMonitor: NWPathMonitor?

    private(set) var outbox = Outbox()
    private(set) var lastSync: Date?
    private(set) var authFailed = false
    private(set) var isSyncing = false

    var statusText: String {
        if authFailed { return "Auth failed — check your token" }
        if !settings.syncEnabled || settings.syncURL.isEmpty { return "Sync off" }
        switch outbox.queuedCount {
        case 0:
            if let last = lastSync {
                return "Up to date · \(last.formatted(.relative(presentation: .named)))"
            }
            return "Up to date"
        case let n:
            return "\(n) waiting to sync"
        }
    }

    init(store: DataStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        applyConfig()
        startMonitor()
    }

    func applyConfig() {
        let urlStr = settings.syncURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.syncEnabled, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            client.clear()
            return
        }
        client.configure(baseURL: url, token: settings.syncToken)
        authFailed = false
    }

    func startMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.syncNow()
            }
        }
        let q = DispatchQueue(label: "im.eamon.replog.network")
        monitor.start(queue: q)
        pathMonitor = monitor
    }

    // MARK: - Session lifecycle

    /// Call when a workout is finished.
    func sessionFinished(_ session: Session) {
        outbox.finish(session.id)
        persistState(session)
        syncNow()
    }

    /// Call when an already-uploaded session is edited.
    func sessionEdited(_ session: Session) {
        outbox.editAfterUpload(session.id)
        persistState(session)
        syncNow()
    }

    /// Call when a session is deleted on the phone.
    func sessionDeleted(_ session: Session) {
        Task {
            _ = client.delete(session.id)
            outbox.delete(session.id)
        }
    }

    // MARK: - Sync

    @MainActor
    func syncNow() {
        guard !isSyncing else { return }
        guard settings.syncEnabled, !settings.syncURL.isEmpty else { return }
        applyConfig()
        isSyncing = true
        Task {
            defer { isSyncing = false }
            let due = outbox.dueForUpload()
            guard !due.isEmpty else { return }
            for id in due {
                guard let session = findSession(id) else { continue }
                let payload = Self.payload(for: session)
                let result = client.upsert(payload)
                switch result {
                case .ok:
                    outbox.uploadSucceeded(id)
                    persistState(session)
                    lastSync = .now
                case .authFailed:
                    authFailed = true
                    outbox.uploadFailed(id)
                    persistState(session)
                    return   // pause retries; a banner is shown
                case .tombstoned:
                    // The server deleted this; accept it.
                    outbox.uploadSucceeded(id)
                    persistState(session)
                case .serverError, .networkError:
                    outbox.uploadFailed(id)
                    persistState(session)
                }
            }
        }
    }

    private func findSession(_ id: String) -> Session? {
        var d = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? store.context.fetch(d).first
    }

    private func persistState(_ session: Session) {
        session.syncState = outbox.state(of: session.id)
        store.save()
    }

    // MARK: - Payload

    /// Build the JSON payload for POST /v1/sessions (plan §4.2).
    static func payload(for session: Session) -> [String: Any] {
        var sets: [[String: Any]] = []
        for entry in session.exerciseEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            for set in entry.setEntries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                var s: [String: Any] = [
                    "exercise": entry.exercise?.name ?? "",
                    "category": entry.exercise?.category?.name ?? "",
                    "exercise_type": entry.setType.rawValue,
                    "set_number": set.setNumber,
                    "set_type": set.setType.rawValue,
                ]
                if let sup = entry.supersetId { s["superset_id"] = sup }
                if let w = set.weightKg { s["weight_kg"] = w }
                if let r = set.reps { s["reps"] = r }
                if let rpe = set.rpe { s["rpe"] = rpe }
                if let d = set.durationS { s["duration_s"] = d }
                if let dm = set.distanceM { s["distance_m"] = dm }
                if let k = set.kcal { s["kcal"] = k }
                if !set.notes.isEmpty { s["notes"] = set.notes }
                sets.append(s)
            }
        }
        var p: [String: Any] = [
            "session_id": session.id,
            "date": CSVCodec.date(session.date),
            "sets": sets,
        ]
        if let st = session.startTime { p["start_time"] = CSVCodec.time(st) }
        if let et = session.endTime { p["end_time"] = CSVCodec.time(et) }
        if let bw = session.bodyweightKg { p["bodyweight_kg"] = bw }
        return p
    }
}