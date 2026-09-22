import Foundation
import SwiftData
import Network

/// Orchestrates the outbox + client (plan §4.3, §7.3 T7.3).
///
/// iOS gives no "the moment connectivity returns" trigger, so a queued
/// session is uploaded on: the next foreground run, a manual "Sync now",
/// or an opportunistic background refresh. Sessions are never lost.
///
/// @MainActor: it is UI-facing (status text) and touches the main context.
@MainActor
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
    private var lastAttempt: [String: Date] = [:]

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
        rehydrateOutbox()
        applyConfig()
        startMonitor()
    }

    /// Rebuild the in-memory outbox from the persisted per-session state.
    /// The outbox itself is not persisted (it is a pure state machine), so a
    /// process restart would otherwise drop every queued/failed session and
    /// the offline queue would never flush (plan §4.3: "the queue grows,
    /// nothing is lost"). `syncStateRaw` on the model is the source of truth.
    func rehydrateOutbox() {
        for s in store.sessions() {
            switch s.syncState {
            case .queued: outbox.finish(s.id)
            case .dirty:
                outbox.finish(s.id)
                outbox.editAfterUpload(s.id)
            case .failed: outbox.uploadFailed(s.id)
            case .uploaded: outbox.uploadSucceeded(s.id)
            case .local: break
            }
        }
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

    private func startMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                Task { @MainActor in
                    self?.syncNow()
                }
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
        let id = session.id
        Task {
            _ = await client.delete(id)
            outbox.delete(id)
        }
    }

    // MARK: - Sync

    func syncNow() {
        guard !isSyncing else { return }
        guard settings.syncEnabled, !settings.syncURL.isEmpty else { return }
        applyConfig()
        isSyncing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSyncing = false }
            let due = self.outbox.dueForUpload(now: .now, lastAttempt: self.lastAttempt)
            guard !due.isEmpty else { return }
            for id in due {
                guard let session = self.findSession(id) else { continue }
                // Encode on the main actor; pass Sendable Data across the
                // async boundary.
                let payload = Self.payloadData(for: session)
                let result = await self.client.upsert(data: payload)
                switch result {
                case .ok:
                    self.outbox.uploadSucceeded(id)
                    self.lastAttempt[id] = .now
                    self.persistState(session)
                    self.lastSync = .now
                case .authFailed:
                    self.authFailed = true
                    self.outbox.uploadFailed(id)
                    self.lastAttempt[id] = .now
                    self.persistState(session)
                    return   // pause retries; a banner is shown
                case .tombstoned:
                    // The server deleted this; accept it.
                    self.outbox.uploadSucceeded(id)
                    self.persistState(session)
                case .serverError, .networkError:
                    self.outbox.uploadFailed(id)
                    self.lastAttempt[id] = .now
                    self.persistState(session)
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
        session.syncState = Self.syncState(from: outbox.state(of: session.id))
        store.save()
    }

    /// Map the outbox state machine onto the model's SyncState.
    static func syncState(from state: Outbox.State) -> SyncState {
        switch state {
        case .local: .local
        case .queued: .queued
        case .uploaded: .uploaded
        case .dirty: .dirty
        case .failed: .failed
        }
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

    /// Pre-encoded JSON body (Sendable) for the client.
    static func payloadData(for session: Session) -> Data {
        (try? JSONSerialization.data(withJSONObject: payload(for: session)))
            ?? Data("{}".utf8)
    }
}
