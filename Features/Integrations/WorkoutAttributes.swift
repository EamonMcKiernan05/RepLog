import Foundation
import ActivityKit

/// Live Activity attributes for the active workout (plan §3.1 line 20).
///
/// This file is compiled into BOTH the app target and the RepLogWidget
/// extension target (see project.yml): `Activity.request` in the app needs
/// the attributes type, and the `ActivityConfiguration` in the widget
/// extension needs it too. A Live Activity's views and Dynamic Island
/// layout MUST live in a widget extension — the `ActivityConfiguration`,
/// `DynamicIsland` and `DynamicIslandExpanded*` types are WidgetKit types
/// that do not exist in the app target.
///
/// The two clocks the owner asked for (2026-10-27) are drawn WITHOUT pushes:
///   - the session timer counts up from `startDate` via `Text(_:style:.timer)`
///     — the system animates it, so no `Activity.update` is needed per second
///   - the rest countdown runs down to `restEndsAt` via
///     `Text(timerInterval:countsDown:)`, updated only when the timer itself
///     changes (start / pause / ±15s / reset / finish)
struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// How many exercises the open workout holds.
        var exerciseCount: Int
        /// Rest timer: running means the countdown is live to `restEndsAt`.
        var restIsRunning: Bool
        var restEndsAt: Date?
        /// Seconds left when paused (0 = never started / finished).
        var restRemaining: Int
        /// The interval the countdown started from, in seconds.
        var restTotal: Int
    }

    var workoutName: String
    var startDate: Date
}
