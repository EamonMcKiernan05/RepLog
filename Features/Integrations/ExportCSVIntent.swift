import AppIntents
import Foundation

/// A Shortcuts / App Intents action that exports the full history to a CSV
/// file (plan §3.1 line 24). The same bytes the in-app export and the sync
/// service produce (CSVCodec, frozen schema §4.4).
struct ExportCSVIntent: AppIntent {
    static var title: LocalizedStringResource = "Export RepLog CSV"
    static var description = IntentDescription("Exports all logged workouts to a CSV file in the frozen RepLog schema.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "File name", default: "RepLog-export")
    var fileName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesData {
        // Open a container over the same store the app uses.
        let store = DataStore()
        let sessions = store.sessions()
        let csv = CSVCodec.encode(sessions: sessions)
        let name = (fileName.isEmpty ? "RepLog-export" : fileName) + ".csv"
        let url = URL.temporaryDirectory.appendingPathComponent(name)
        try csv.data(using: .utf8)!.write(to: url)
        return .result(data: url)
    }
}
