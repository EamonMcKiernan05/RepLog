import AppIntents
import Foundation

/// A Shortcuts / App Intents action that exports the full history to a CSV
/// file (plan §3.1 line 24). The same bytes the in-app export and the sync
/// service produce (CSVCodec, frozen schema §4.4).
///
/// SDK notes (verified against the Xcode 26.5 SDK, 2026-09-22):
///  - A file-returning intent uses `IntentResult<...>` + `@Parameter` and
///    returns a `FileRepresentation` (the `ProvidesData` protocol does not
///    exist in App Intents).
///  - The static `title`/`description` are `nonisolated` so they are
///    concurrency-safe under Swift 6 strict concurrency.
struct ExportCSVIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Export RepLog CSV"
    nonisolated static let description = IntentDescription("Exports all logged workouts to a CSV file in the frozen RepLog schema.")
    nonisolated static let openAppWhenRun: Bool = false
    nonisolated static let isDiscoverable: Bool = true

    @Parameter(title: "File name", default: "RepLog-export")
    var fileName: String

    @MainActor
    func perform() async throws -> IntentResult<FileRepresentation> {
        // Open a container over the same store the app uses.
        let store = DataStore()
        let sessions = store.sessions()
        let csv = CSVCodec.encode(sessions: sessions)
        let base = fileName.isEmpty ? "RepLog-export" : fileName
        let name = base.hasSuffix(".csv") ? base : base + ".csv"
        let url = URL.temporaryDirectory.appendingPathComponent(name)
        try csv.data(using: .utf8)?.write(to: url)
        return .result(file: FileRepresentation(url: url))
    }
}
