import SwiftUI
import SwiftData

/// One set row (plan §6.2, §3.2): circled set number, then type-appropriate
/// columns — Weight · Reps · **RPE** · Notes (weight_reps). RPE sits
/// immediately after Reps, before Notes, exactly as the spec requires.
///
/// Every cell is edited in place: tap the box and type (no sheet). In a
/// finished session (`isEditing == false`) the same boxes render as plain
/// text.
struct SetRowView: View {
    @Environment(DataStore.self) private var store
    let set: SetEntry
    let type: ExerciseType
    let unit: WeightUnit
    var isEditing: Bool
    /// Shared with the whole screen so one keyboard "Done" clears whatever is
    /// being typed, and the card can reveal the RPE chips under the row being
    /// edited.
    let focus: FocusState<CellFocus?>.Binding

    private var owner: ObjectIdentifier { ObjectIdentifier(set) }

    /// Row geometry — see `RowLayout` (four variants under owner review).
    private var layout: RowLayout { RowLayout.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Uniform gap between every column, no spacer, and TOP aligned:
            // with the row centred, the Notes cell's smaller value made its
            // label sit lower than Kg/Reps/RPE (owner report, 2026-09-24).
            HStack(alignment: .top, spacing: layout.gutter) {
                // Circled index, with an empty label line above it so the
                // circle sits level with the values.
                VStack(spacing: 4) {
                    Text(" ").font(Typography.label).hidden()
                    ZStack {
                        Circle().stroke(Palette.textSecondary.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 23, height: 23)
                        Text("\(set.setNumber)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(set.isDrop ? Palette.accent : Palette.textPrimary)
                    }
                    .frame(width: 23)
                }

                if set.isDrop {
                    VStack(spacing: 4) {
                        Text(" ").font(Typography.label).hidden()
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 16)
                    }
                }

                // Columns per type
                if type.hasWeight {
                    cell(
                        label: unit == .kg ? "Kg" : "Lb",
                        value: weightDisplay,
                        id: "weight-cell",
                        field: .weight,
                        keyboard: .decimalPad,
                        commit: commitWeight
                    )
                }
                if type.hasReps {
                    cell(
                        label: "Reps",
                        value: set.reps.map(String.init) ?? "",
                        id: "reps-cell",
                        field: .reps,
                        keyboard: .numberPad,
                        commit: commitReps
                    )
                }
                if type.hasTime {
                    cell(
                        label: "Time",
                        value: timeDisplay,
                        id: "time-cell",
                        field: .time,
                        keyboard: .decimalPad,
                        commit: commitTime
                    )
                }
                if type.hasCardioExtras {
                    cell(
                        label: "Dist",
                        value: set.distanceM.map { String(Int($0)) } ?? "",
                        id: "distance-cell",
                        field: .distance,
                        keyboard: .decimalPad,
                        commit: commitDistance
                    )
                    cell(
                        label: "kcal",
                        value: set.kcal.map { String(Int($0)) } ?? "",
                        id: "kcal-cell",
                        field: .kcal,
                        keyboard: .decimalPad,
                        commit: commitKcal
                    )
                }
                // RPE column — after Reps/Time, before Notes.
                if type.hasRPE {
                    cell(
                        label: "RPE",
                        value: rpeDisplay,
                        id: "rpe-cell",
                        field: .rpe,
                        keyboard: .decimalPad,
                        commit: commitRPE
                    )
                }
                // Notes column
                cell(
                    label: "Notes",
                    value: set.notes,
                    id: "notes-cell",
                    field: .notes,
                    keyboard: .default,
                    wide: true,
                    commit: commitNotes
                )
            }
            .padding(.vertical, 11)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Columns

    /// Editing: the box is the input. Finished: plain text, exactly as before.
    @ViewBuilder
    private func cell(label: String, value: String, id: String,
                      field: CellFocus.Field, keyboard: UIKeyboardType,
                      wide: Bool = false,
                      commit: @escaping (String) -> Void) -> some View {
        if isEditing {
            InlineCell(
                label: label,
                id: id,
                value: value,
                keyboard: keyboard,
                wide: wide,
                valueSize: layout.numberSize,
                fixedWidth: wide ? nil : layout.numberWidth,
                valueFont: wide ? NotesStyle.current.font : nil,
                focus: focus,
                focusValue: CellFocus(owner: owner, field: field),
                commit: commit
            )
        } else {
            column(label: label, value: value, isPlaceholder: value.isEmpty,
                   id: id, wide: wide)
        }
    }

    @ViewBuilder
    private func column(label: String, value: String, isPlaceholder: Bool,
                        id: String?, wide: Bool) -> some View {
        VStack(alignment: wide ? .leading : .center, spacing: 4) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
                .alignmentGuide(.leading) { d in
                    wide && NotesStyle.current.labelPlacement == .centredOverValue
                        ? d.width / 2
                        : d[.leading]
                }
            Text(value.isEmpty ? "—" : value)
                .font(wide ? NotesStyle.current.font
                           : Typography.mono(layout.numberSize, value.isEmpty ? .regular : .bold))
                .foregroundStyle(isPlaceholder ? Palette.textSecondary.opacity(0.6) : Palette.textPrimary)
                .lineLimit(1)
        }
        // A wide cell's label rides above its own value — centred in a cell
        // that fills the row, it drifted ~100 pt away from the value under it.
        .frame(minWidth: wide ? nil : layout.numberWidth,
               maxWidth: wide ? .infinity : layout.numberWidth,
               alignment: wide ? .leading : .center)
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

    // MARK: - Display

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
        return SetRowView.rpeText(rpe)
    }

    /// RPE reads as `8`, never `8.0` (plan §3.2).
    static func rpeText(_ v: Double) -> String {
        let tenths = Int((v * 10).rounded())
        if tenths % 10 == 0 {
            return String(tenths / 10)
        }
        return String(format: "%.1f", v)
    }

    // MARK: - Commits
    //
    // Each one parses the typed text and writes the model. An empty box clears
    // the value; text that does not parse is ignored (the box snaps back to the
    // stored value). Values are written on submit / focus loss, never per
    // keystroke.

    private func commitWeight(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.weightKg = nil
        } else if let v = Double(t), v >= 0 {
            set.weightKg = unit.toKg(v)
        }
        store.save()
    }

    private func commitReps(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.reps = nil
        } else if let v = Int(t), v >= 0 {
            set.reps = v
        }
        store.save()
    }

    private func commitTime(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.durationS = nil
        } else if let v = Double(t), v >= 0 {
            set.durationS = v
        }
        store.save()
    }

    private func commitDistance(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.distanceM = nil
        } else if let v = Double(t), v >= 0 {
            set.distanceM = v
        }
        store.save()
    }

    private func commitKcal(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.kcal = nil
        } else if let v = Double(t), v >= 0 {
            set.kcal = v
        }
        store.save()
    }

    /// RPE snaps to half steps inside 1–10 (the old sheet's rule, now applied
    /// to what is typed straight into the cell).
    private func commitRPE(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            set.rpe = nil
        } else if let v = Double(t) {
            set.rpe = min(max((v * 2).rounded() / 2, 1.0), 10.0)
        }
        store.save()
    }

    private func commitNotes(_ text: String) {
        set.notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save()
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
