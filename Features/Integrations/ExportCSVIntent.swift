import AppIntents
import Foundation
import UniformTypeIdentifiers

/// A Shortcuts / App Intents action that exports the full history to a CSV
/// file (plan §3.1 line 24). The same bytes the in-app export and the sync
/// service produce (CSVCodec, frozen schema §4.4).
///
/// SDK notes (verified against the Xcode 26.5 SDK, 2026-09-22):
///  - A file-returning intent returns `some IntentResult & ReturnsValue<IntentFile>`
///    via `.result(value:)`. (`ProvidesData` and the `.result(data:)` spelling
///    do not exist in App Intents; `IntentFile` is the App Intents file type.)
///  - The static `title`/`description`/`openAppWhenRun` are plain stored
///    statics (no `nonisolated` needed — they are Sendable let constants).
struct ExportCSVIntent: AppIntent {
    static let title: LocalizedStringResource = "Export RepLog CSV"
    static let description = IntentDescription("Exports all logged workouts to a CSV file in the frozen RepLog schema.")
    static let openAppWhenRun: Bool = false
    static let isDiscoverable: Bool = true

    @Parameter(title: "File name", default: "RepLog-export")
    var fileName: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        // Open a container over the same store the app uses.
        let store = DataStore()
        let sessions = store.sessions()
        let csv = CSVCodec.encode(sessions: sessions)
        let base = fileName.isEmpty ? "RepLog-export" : fileName
        let name = base.hasSuffix(".csv") ? base : base + ".csv"
        let url = URL.temporaryDirectory.appendingPathComponent(name)
        try csv.data(using: .utf8)?.write(to: url)
        return .result(value: IntentFile(fileURL: url, filename: name, type: .commaSeparatedText))
    }
}
