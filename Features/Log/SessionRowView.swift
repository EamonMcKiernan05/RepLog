import SwiftUI
import SwiftData

/// One session row in the Log (plan §6.1): date badge, routine name,
/// up to three "Nx Exercise" lines, duration trailing.
struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 14) {
            DateBadgeView(date: session.date)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.routineName.isEmpty ? "Workout" : session.routineName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                ForEach(session.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            Spacer()
            Text(session.durationText)
                .font(Typography.duration)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("session-row-\(session.id.prefix(8))")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let date = session.date.formatted(.dateTime.weekday(.wide).day().month())
        let name = session.routineName.isEmpty ? "Workout" : session.routineName
        let summary = session.summaryLines.joined(separator: ", ")
        return "\(date), \(name), \(summary), \(session.durationText)"
    }
}

/// Two-line date badge: weekday abbreviation over the day number.
struct DateBadgeView: View {
    let date: Date

    var body: some View {
        VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.textSecondary)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: 48, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Palette.control, Palette.card],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
    }
}
