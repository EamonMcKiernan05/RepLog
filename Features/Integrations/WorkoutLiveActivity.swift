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
/// renders it from the widget extension. Started when a workout opens, updated
/// whenever the rest timer changes, ended on finish.
enum WorkoutLiveActivityController {
    /// Begin the Live Activity for a workout. Any activity left behind by an
    /// earlier session is ended first: one open workout, one activity.
    @MainActor
    static func start(workoutName: String, startDate: Date, exerciseCount: Int,
                      rest: RestTimerSnapshot? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = WorkoutAttributes(workoutName: workoutName, startDate: startDate)
        let state = WorkoutAttributes.ContentState(
            exerciseCount: exerciseCount,
            restIsRunning: rest?.isRunning ?? false,
            restEndsAt: rest?.endsAt,
            restRemaining: rest?.remaining ?? 0,
            restTotal: rest?.total ?? 0
        )
        Task {
            for old in Activity<WorkoutAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate, timestamp: .now)
            }
            do {
                _ = try Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // Live Activities are best-effort; never block the workout on
                // them — but a silent failure is why this "showed nothing" for
                // weeks, so it is printed.
                print("[RepLog] Live Activity request failed: \(error)")
            }
        }
    }

    /// Push the rest timer's state into the running activity. The session clock
    /// needs nothing from here: it counts up from the start date on its own.
    @MainActor
    static func update(rest: RestTimerSnapshot) {
        Task {
            for activity in Activity<WorkoutAttributes>.activities {
                var state = activity.content.state
                state.restIsRunning = rest.isRunning
                state.restEndsAt = rest.isRunning ? rest.endsAt : nil
                state.restRemaining = rest.remaining
                state.restTotal = rest.total
                await activity.update(.init(state: state, staleDate: nil))
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
