import SwiftUI
import SwiftData

/// Create a new routine (plan §6.3).
struct RoutineEditorSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var routine: Routine?   // nil = create new
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Routine name", text: $name)
                    .accessibilityIdentifier("routine-name")
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func save() {
        let next = (store.routines().map { $0.sortOrder }.max() ?? -1) + 1
        let r = Routine(name: name, sortOrder: next)
        store.context.insert(r)
        store.save()
        dismiss()
    }
}
