import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// In-app import (plan §4.5.4, T8.3): a fresh phone rebuilds its history
/// from a new-schema CSV via the Files app.
struct ImportCSVButton: View {
    @Environment(DataStore.self) private var store
    @State private var showImporter = false
    @State private var result: Importer.Result?

    var body: some View {
        Button {
            showImporter = true
        } label: {
            Label("Import CSV", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { outcome in
            Task { @MainActor in
                switch outcome {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        let r = Importer.importCSV(text, into: store.context)
                        result = r
                    } catch {
                        result = Importer.Result(sessions: 0, sets: 0,
                                                 errors: [error.localizedDescription])
                    }
                case .failure(let error):
                    result = Importer.Result(sessions: 0, sets: 0,
                                             errors: [error.localizedDescription])
                }
            }
        }
        .alert("Import complete", isPresented: Binding(
            get: { result != nil },
            set: { if !$0 { result = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let r = result {
                Text("Imported \(r.sessions) sessions, \(r.sets) sets.\n\(r.errors.joined(separator: "\n"))")
            }
        }
    }
}
