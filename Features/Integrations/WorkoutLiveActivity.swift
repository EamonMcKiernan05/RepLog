import ActivityKit
import SwiftUI

/// Live Activity for the active workout (plan §3.1 line 20): Dynamic Island +
/// lock screen while a workout is in progress. Started when the workout
/// begins, ended on finish.
struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var exerciseCount: Int
    }

    var workoutName: String
    var startDate: Date
}

/// The lock-screen / Dynamic Island view for an in-progress workout.
struct WorkoutLiveActivity: View {
    var activity: Activity<WorkoutAttributes>

    private var elapsed: String {
        let s = max(0, activity.content.state.elapsedSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.teal)
                Text(activity.attributes.workoutName.isEmpty ? "Workout" : activity.attributes.workoutName)
                    .font(.headline)
                Spacer()
                Text(elapsed)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("\(activity.content.state.exerciseCount) exercise\(activity.content.state.exerciseCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

enum WorkoutLiveActivityController {
    /// Begin the Live Activity for a workout. No-op if unsupported or already running.
    @MainActor
    static func start(workoutName: String, startDate: Date, exerciseCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = WorkoutAttributes(workoutName: workoutName, startDate: startDate)
        let state = WorkoutAttributes.ContentState(elapsedSeconds: 0, exerciseCount: exerciseCount)
        let config = ActivityConfiguration(
            liveActivity: { activity in
                WorkoutLiveActivity(activity: activity)
            },
            dynamicIsland: { activity in
                DynamicIsland {
                    DynamicIslandExpandedHeader {
                        Text(activity.attributes.workoutName.isEmpty ? "Workout" : activity.attributes.workoutName)
                            .font(.headline)
                    }
                    DynamicIslandExpandedCenter {
                        Text("\(activity.content.state.exerciseCount) exercise\(activity.content.state.exerciseCount == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    DynamicIslandExpandedFooter {
                        Text(activity.attributes.startDate, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } compactLeading: {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.teal)
                } compactTrailing: {
                    Text(activity.content.state.exerciseCount)
                        .font(.caption.monospacedDigit())
                } minimal: {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
            }
        )
        Task {
            do {
                try await Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil), configuration: config)
            } catch {
                // Live Activities are best-effort; never block the workout on them.
            }
        }
    }

    /// End the current workout Live Activity.
    @MainActor
    static func end() {
        Task {
            for a in Activity<WorkoutAttributes>.activities {
                a.end(at: .now, dismissalPolicy: .immediate)
            }
        }
    }
}
