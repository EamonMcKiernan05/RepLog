import Foundation

/// Minimal HTTP client for the lift-sync service (plan §4.2).
/// All networking lives in Sync/ (plan §4.1).
///
/// A plain final class (not an actor): URLSession is thread-safe, and this
/// keeps the [String: Any] payload out of the Sendable checker.
/// @unchecked Sendable: the only mutable state is the config (set on the
/// main thread) and URLSession, which is itself thread-safe.
final class LiftSyncClient: @unchecked Sendable {
    struct Config {
        var baseURL: URL
        var token: String
    }

    private let session: URLSession
    private var config: Config?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func configure(baseURL: URL, token: String) {
        config = Config(baseURL: baseURL, token: token)
    }

    func clear() {
        config = nil
    }

    enum Result {
        case ok(sets: Int)
        case authFailed
        case serverError(status: Int)
        case networkError
        case tombstoned
    }

    private func request(_ method: String, path: String) async -> (Int, Data)? {
        guard let config else { return nil }
        let url = config.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            return (http.statusCode, data)
        } catch {
            return nil
        }
    }

    /// POST /v1/sessions
    func upsert(_ payload: [String: Any]) async -> Result {
        guard let config else { return .networkError }
        let url = config.baseURL.appendingPathComponent("v1/sessions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .networkError }
            switch http.statusCode {
            case 200:
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let sets = body?["sets"] as? Int ?? 0
                return .ok(sets: sets)
            case 401:
                return .authFailed
            case 409:
                return .tombstoned
            default:
                return .serverError(status: http.statusCode)
            }
        } catch {
            return .networkError
        }
    }

    /// DELETE /v1/sessions/{id}
    func delete(_ sessionID: String) async -> Bool {
        let path = "v1/sessions/\(sessionID)"
        guard let (status, _) = await request("DELETE", path: path) else { return false }
        return status == 200
    }

    /// GET /v1/health
    func health() async -> Bool {
        guard let (status, _) = await request("GET", path: "v1/health") else { return false }
        return status == 200
    }
}
