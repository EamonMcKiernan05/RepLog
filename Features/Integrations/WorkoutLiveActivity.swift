import ActivityKit
import Foundation

/// App-side controller for the workout Live Activity (plan §3.1 line 20).
///
/// Only `ActivityKit` lives here — the `ActivityConfiguration`, `DynamicIsland`
/// and `DynamicIslandExpanded*` types are WidgetKit types and only exist
/// inside the RepLogWidget extension target, so the views and Dynamic Island
/// layout live in `Widget/WorkoutLiveActivityWidget.swift`. The shared
/// `WorkoutAttributes` type is compiled into both targets.
///
/// The app declares the activity via `NSSupportsLiveActivities`; the system
/// renders it from the widget extension. Started when the workout begins,
/// ended on finish.
enum WorkoutLiveActivityController {
    /// Begin the Live Activity for a workout. No-op if unsupported or already running.
    @MainActor
    static func start(workoutName: String, startDate: Date, exerciseCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = WorkoutAttributes(workoutName: workoutName, startDate: startDate)
        let state = WorkoutAttributes.ContentState(elapsedSeconds: 0, exerciseCount: exerciseCount)
        Task {
            do {
                try await Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
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
                await a.end(nil, dismissalPolicy: .immediate, timestamp: .now)
            }
        }
    }
}
