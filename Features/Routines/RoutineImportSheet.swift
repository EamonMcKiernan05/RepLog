import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import routines from a CSV file (owner request, 2026-10-23).
///
/// Two steps, because a routine import can REPLACE one that already exists:
/// pick the file, see what it will do (which routines are new, which are
/// replaced, which exercises get created), then Import. Nothing is written
/// until Import is pressed.
struct RoutineImportSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var parsed: [RoutineCSV.ParsedRoutine] = []
    @State private var errorText: String?
    @State private var summary: DataStore.RoutineImportSummary?

    var body: some View {
        NavigationStack {
            List {
                if let summary {
                    Section("Imported") {
                        Label("\(summary.imported.count) routine(s): \(summary.imported.joined(separator: ", "))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.textPrimary)
                        if !summary.replaced.isEmpty {
                            Text("Replaced: \(summary.replaced.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        if !summary.createdExercises.isEmpty {
                            Text("New exercises: \(summary.createdExercises.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        if !summary.createdCategories.isEmpty {
                            Text("New categories: \(summary.createdCategories.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                } else if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.destructive)
                    }
                } else if parsed.isEmpty {
                    Section {
                        Text("Pick a CSV with one row per exercise: routine, position, exercise, type, category, warmup_sets, working_sets, notes.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        Button {
                            showPicker = true
                        } label: {
                            Label("Choose File…", systemImage: "doc.badge.plus")
                        }
                        .accessibilityIdentifier("routine-import-choose")
                    }
                } else {
                    Section("Ready to import") {
                        ForEach(parsed, id: \.name) { routine in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(routine.name).font(.headline)
                                Text("\(routine.exercises.count) exercise(s)" + (replaces(routine.name) ? " · replaces the existing routine" : ""))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .accessibilityIdentifier("routine-import-row-\(routine.name)")
                        }
                        Button {
                            summary = store.importRoutines(parsed)
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("routine-import-confirm")
                    }
                }
            }
            .navigationTitle("Import Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(summary == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("routine-import-done")
                }
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { outcome in
                switch outcome {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    load(url)
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func load(_ url: URL) {
        // Files picked outside the app's container need the security scope.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            parsed = try RoutineCSV.parse(text)
            errorText = nil
        } catch let error as RoutineCSV.ImportError {
            parsed = []
            errorText = Self.describe(error)
        } catch {
            parsed = []
            errorText = error.localizedDescription
        }
    }

    private func replaces(_ name: String) -> Bool {
        store.routines().contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The parser's errors in the owner's language, with the line that failed.
    private static func describe(_ error: RoutineCSV.ImportError) -> String {
        switch error {
        case .emptyFile:
            return "That file is empty."
        case .missingColumns(let columns):
            return "The header is missing: \(columns.joined(separator: ", "))."
        case .badValue(let line, let column, let value):
            return "Line \(line): \(column) can't be \"\(value)\"."
        case .emptyExercise(let line):
            return "Line \(line): no exercise name."
        case .noExercises(let routine):
            return "Routine \(routine) has no exercises."
        }
    }
}
