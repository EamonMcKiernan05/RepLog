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
struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var exerciseCount: Int
    }

    var workoutName: String
    var startDate: Date
}
