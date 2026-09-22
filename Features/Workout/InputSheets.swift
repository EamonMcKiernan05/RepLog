import SwiftUI
import SwiftData

/// RPE input sheet (plan §3.2, §6.2): numeric pad with 0.5 steps and quick
/// chips (6, 7, 7.5, 8, 8.5, 9); displays `8`, not `8.0`; long-press clears.
struct RPEInputSheet: View {
    let set: SetEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text: String = ""

    private let chips: [Double] = [6, 7, 7.5, 8, 8.5, 9]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Current value
                Text(display)
                    .font(Typography.mono(56, .bold))
                    .foregroundStyle(set.rpe == nil ? Palette.textSecondary : Palette.textPrimary)
                    .contentTransition(.numericText())

                // Quick chips
                HStack(spacing: 10) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            text = rpeText(chip)
                        } label: {
                            Text(rpeText(chip))
                                .font(Typography.mono(17, .semibold))
                                .frame(minWidth: 48, minHeight: 44)
                                .background(
                                    Capsule().fill(
                                        set.rpe == chip
                                        ? AnyShapeStyle(Palette.accent)
                                        : AnyShapeStyle(Palette.control)
                                    )
                                )
                                .foregroundStyle(set.rpe == chip ? .black : Palette.textPrimary)
                        }
                    }
                }

                // Text field for arbitrary entry (0.5 steps enforced on save)
                TextField("RPE (1–10, half steps)", text: $text)
                    .keyboardType(.decimalPad)
                    .font(Typography.mono(20))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("rpe-field")

                Button("Clear") {
                    text = ""
                    set.rpe = nil
                    store.save()
                }
                .font(.body)
                .foregroundStyle(Palette.destructive)

                Spacer()
            }
            .padding()
            .navigationTitle("RPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                text = set.rpe.map { rpeText($0) } ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private var display: String {
        if let rpe = set.rpe {
            return rpeText(rpe)
        }
        return "—"
    }

    private func rpeText(_ v: Double) -> String {
        let tenths = (v * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(tenths / 10)
        }
        return String(format: "%.1f", v)
    }

    private func save() {
        guard let v = Double(text) else { return }
        // Snap to 0.5 steps, clamp to 1–10.
        let snapped = (v * 2).rounded() / 2
        set.rpe = min(max(snapped, 1.0), 10.0)
        store.save()
    }
}

/// Generic numeric input sheet for weight / reps / time / distance / kcal.
struct NumberInputSheet: View {
    let field: ExerciseCardView.NumberField
    let unit: WeightUnit
    let isDecimal: Bool
    let placeholder: String
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)

                TextField("0", text: $text)
                    .keyboardType(isDecimal ? .decimalPad : .numberPad)
                    .font(Typography.mono(32, .bold))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("number-field")

                if !isDecimal {
                    HStack(spacing: 10) {
                        ForEach([1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20], id: \.self) { n in
                            Button("\(n)") { text = "\(n)" }
                                .font(Typography.mono(15, .semibold))
                                .frame(minWidth: 40, minHeight: 40)
                                .background(Capsule().fill(Palette.control))
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { text = currentText }
        }
        .presentationDetents([.height(280)])
    }

    private var title: String {
        if !isDecimal { return "Reps" }
        switch field {
        case .weight: return unit == .kg ? "Weight (kg)" : "Weight (lb)"
        case .time: return "Time (seconds)"
        case .distance: return "Distance (metres)"
        case .kcal: return "Calories"
        case .reps: return "Reps"
        }
    }

    private var currentText: String {
        let set = field.set
        switch field {
        case .weight:
            guard let kg = set.weightKg else { return "" }
            let v = unit.convert(fromKg: kg)
            return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        case .reps:
            return set.reps.map(String.init) ?? ""
        case .time:
            return set.durationS.map { String(Int($0)) } ?? ""
        case .distance:
            return set.distanceM.map { String(Int($0)) } ?? ""
        case .kcal:
            return set.kcal.map { String(Int($0)) } ?? ""
        }
    }

    private func save() {
        let set = field.set
        guard let v = Double(text) else { return }
        switch field {
        case .weight:
            set.weightKg = unit.toKg(v)
        case .reps:
            set.reps = Int(v)
        case .time:
            set.durationS = v
        case .distance:
            set.distanceM = v
        case .kcal:
            set.kcal = v
        }
        store.save()
    }
}

/// Text sheet for a single set's note.
struct SetNoteSheet: View {
    let set: SetEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            TextField("Note for set \(set.setNumber)", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .onAppear { text = set.notes }
                .navigationTitle("Set Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            set.notes = text
                            store.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

/// Per-exercise notes sheet (the "Notes" icon in the card footer).
struct ExerciseNotesSheet: View {
    let entry: ExerciseEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            TextField("Exercise note", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .padding()
                .onAppear { text = entry.notes }
                .navigationTitle(entry.exercise?.name ?? "Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            entry.notes = text
                            store.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
