import SwiftUI
import SwiftData

/// One set row (plan §6.2, §3.2): circled set number, then type-appropriate
/// columns — Weight · Reps · **RPE** · Notes (weight_reps). RPE sits
/// immediately after Reps, before Notes, exactly as the spec requires.
struct SetRowView: View {
    let set: SetEntry
    let type: ExerciseType
    let unit: WeightUnit
    var isEditing: Bool
    var onRPE: (SetEntry) -> Void
    var onNumber: (ExerciseCardView.NumberField) -> Void
    var onNotes: (SetEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Circled index
                ZStack {
                    Circle().stroke(Palette.textSecondary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    Text("\(set.setNumber)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(set.isDrop ? Palette.accent : Palette.textPrimary)
                }
                .frame(width: 40)

                if set.isDrop {
                    Image(systemName: "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 16)
                }

                Spacer(minLength: 8)

                // Columns per type
                if type.hasWeight {
                    column(
                        label: unit == .kg ? "Kg" : "Lb",
                        value: weightDisplay,
                        isPlaceholder: weightDisplay.isEmpty,
                        id: "weight-cell",
                        action: { onNumber(.weight(set)) }
                    )
                }
                if type.hasReps {
                    column(
                        label: "Reps",
                        value: set.reps.map(String.init) ?? "",
                        isPlaceholder: set.reps == nil,
                        id: "reps-cell",
                        action: { onNumber(.reps(set)) }
                    )
                }
                if type.hasTime {
                    column(
                        label: "Time",
                        value: timeDisplay,
                        isPlaceholder: set.durationS == nil,
                        action: { onNumber(.time(set)) }
                    )
                }
                if type.hasCardioExtras {
                    column(
                        label: "Dist",
                        value: set.distanceM.map { String(Int($0)) } ?? "",
                        isPlaceholder: set.distanceM == nil,
                        action: { onNumber(.distance(set)) }
                    )
                    column(
                        label: "kcal",
                        value: set.kcal.map { String(Int($0)) } ?? "",
                        isPlaceholder: set.kcal == nil,
                        action: { onNumber(.kcal(set)) }
                    )
                }
                // RPE column — after Reps/Time, before Notes.
                if type.hasRPE {
                    column(
                        label: "RPE",
                        value: rpeDisplay,
                        isPlaceholder: set.rpe == nil,
                        id: "rpe-cell",
                        action: { if isEditing { onRPE(set) } }
                    )
                }
                // Notes column
                column(
                    label: "Notes",
                    value: set.notes.isEmpty ? "" : set.notes,
                    isPlaceholder: set.notes.isEmpty,
                    id: "notes-cell",
                    action: { if isEditing { onNotes(set) } }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)

            // A non-empty note also renders as a second line under the row.
            if !set.notes.isEmpty {
                Text(set.notes)
                    .font(.footnote)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var weightDisplay: String {
        guard let kg = set.weightKg else { return "" }
        let v = unit.convert(fromKg: kg)
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var timeDisplay: String {
        guard let s = set.durationS else { return "" }
        if s >= 60 {
            let m = Int(s) / 60
            let sec = Int(s) % 60
            return String(format: "%d:%02d", m, sec)
        }
        return String(Int(s)) + "s"
    }

    private var rpeDisplay: String {
        guard let rpe = set.rpe else { return "" }
        let tenths = Int((rpe * 10).rounded())
        if tenths % 10 == 0 {
            return String(tenths / 10)
        }
        return String(format: "%.1f", rpe)
    }

    @ViewBuilder
    private func column(label: String, value: String, isPlaceholder: Bool,
                        id: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(Palette.textSecondary)
                Text(value.isEmpty ? "—" : value)
                    .font(Typography.mono(17, value.isEmpty ? .regular : .bold))
                    .foregroundStyle(isPlaceholder ? Palette.textSecondary.opacity(0.6) : Palette.textPrimary)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEditing)
        .modifier(ColumnID(id: id))
    }

    /// Applies an accessibility identifier when present (keeps the call sites
    /// clean).
    private struct ColumnID: ViewModifier {
        let id: String?
        func body(content: Content) -> some View {
            if let id {
                content.accessibilityIdentifier(id)
            } else {
                content
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["Set \(set.setNumber)"]
        if let w = set.weightKg { parts.append("\(Int(w)) \(unit.display)") }
        if let r = set.reps { parts.append("\(r) reps") }
        if let rpe = set.rpe { parts.append("RPE \(rpe)") }
        if !set.notes.isEmpty { parts.append(set.notes) }
        return parts.joined(separator: ", ")
    }
}
