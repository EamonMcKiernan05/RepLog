import WidgetKit
import SwiftUI
import ActivityKit

/// The lock-screen / Dynamic Island views for an in-progress workout.
/// Lives in the RepLogWidget extension (WidgetKit types are not available
/// in the app target).
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            WorkoutLiveActivityView(context: context)
                .widgetAccentable()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedHeader {
                    Text(context.attributes.workoutName.isEmpty ? "Workout" : context.attributes.workoutName)
                        .font(.headline)
                }
                DynamicIslandExpandedCenter {
                    VStack(spacing: 2) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.teal)
                        Text("\(context.content.state.exerciseCount) exercise\(context.content.state.exerciseCount == 1 ? "" : "s")")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedFooter {
                    Text(context.attributes.startDate, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.teal)
            } compactTrailing: {
                Text(Self.elapsed(context))
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
            }
        }
    }

    private static func elapsed(_ context: ActivityViewContext<WorkoutAttributes>) -> String {
        let s = max(0, context.content.state.elapsedSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The lock-screen layout for an in-progress workout.
struct WorkoutLiveActivityView: View {
    var context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.teal)
                Text(context.attributes.workoutName.isEmpty ? "Workout" : context.attributes.workoutName)
                    .font(.headline)
                Spacer()
                Text(Self.elapsed(context))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("\(context.content.state.exerciseCount) exercise\(context.content.state.exerciseCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private static func elapsed(_ context: ActivityViewContext<WorkoutAttributes>) -> String {
        let s = max(0, context.content.state.elapsedSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

@main
struct RepLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}
