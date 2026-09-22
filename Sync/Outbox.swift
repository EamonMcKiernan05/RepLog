import Foundation

/// The outbox state machine (plan §4.3, §7.3 T7.3).
///
///   local ──finish──► queued ──upload ok──► uploaded
///   uploaded ──edit──► dirty ──re-post ok──► uploaded
///   queued/dirty/failed ──upload fail──► failed ──retry──► queued
///   delete ──► tombstone (DELETE posted)
///
/// Pure and synchronous so every transition is unit-testable.
struct Outbox {
    enum State: Equatable {
        case local, queued, uploaded, dirty, failed
    }

    private(set) var states: [String: State] = [:]   // sessionID -> state
    private(set) var attempts: [String: Int] = [:]

    mutating func finish(_ id: String) {
        states[id] = .queued
        attempts[id] = 0
    }

    mutating func markLocal(_ id: String) {
        states[id] = .local
    }

    mutating func uploadSucceeded(_ id: String) {
        states[id] = .uploaded
        attempts[id] = 0
    }

    mutating func uploadFailed(_ id: String) {
        states[id] = .failed
        attempts[id] = (attempts[id] ?? 0) + 1
    }

    mutating func editAfterUpload(_ id: String) {
        // Editing an uploaded session makes it dirty (re-post needed).
        if states[id] == .uploaded || states[id] == .failed {
            states[id] = .dirty
        } else if states[id] == .local || states[id] == nil {
            states[id] = .queued
        }
    }

    mutating func delete(_ id: String) {
        states[id] = .uploaded   // tombstone posted; treat as resolved
    }

    /// Sessions that need an upload now (queued, dirty, or failed-with-backoff-elapsed).
    mutating func dueForUpload(now: Date = .now, lastAttempt: [String: Date], backoff: (Int) -> TimeInterval = { Foundation.pow(2.0, Double(min($0, 6))) }) -> [String] {
        states.compactMap { id, state in
            switch state {
            case .queued, .dirty:
                return id
            case .failed:
                let last = lastAttempt[id]
                if let last, now.timeIntervalSince(last) < backoff(attempts[id] ?? 0) {
                    return nil
                }
                return id
            case .local, .uploaded:
                return nil
            }
        }
        .sorted()
    }

    func state(of id: String) -> State {
        states[id] ?? .local
    }

    var queuedCount: Int {
        states.values.filter { $0 == .queued || $0 == .dirty || $0 == .failed }.count
    }
}
