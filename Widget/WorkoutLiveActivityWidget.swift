import WidgetKit
import SwiftUI
import ActivityKit

/// The lock-screen / Dynamic Island views for an in-progress workout.
/// Lives in the RepLogWidget extension (WidgetKit types are not available
/// in the app target).
///
/// Two clocks, owner request 2026-10-27 — "a timer counting up from the start
/// of the session showing how long it's been going for, and the normal timer if
/// there is one running":
///   - session: `Text(startDate, style: .timer)` — the system animates it from
///     the start date, so it stays right with no update pushes at all
///   - rest: `Text(timerInterval:countsDown:)` — an animated countdown to
///     `restEndsAt`; falls back to the static remaining when paused, and to
///     "Rest" when the timer has never been started
///
/// SDK notes (verified against the Xcode 26.5 SDK, 2026-09-22):
///  - The expanded Dynamic Island content is built from
///    `DynamicIslandExpandedRegion(.center)` / `.bottom` (there are no
///    `DynamicIslandExpandedHeader/Center/Footer` types).
///  - `ActivityViewContext` exposes `state` (not `content.state`) and
///    `attributes`.
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            WorkoutLiveActivityView(context: context)
                .widgetAccentable()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutName.isEmpty ? "Workout" : context.attributes.workoutName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        SessionClock(startDate: context.attributes.startDate)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestClock(state: context.state, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.teal)
                        Text("\(context.state.exerciseCount) exercise\(context.state.exerciseCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.state.restIsRunning {
                            Text("Rest")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.teal)
            } compactTrailing: {
                SessionClock(startDate: context.attributes.startDate)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.teal)
            }
        }
    }
}

/// The session clock: counts UP from the workout's start time.
struct SessionClock: View {
    var startDate: Date

    var body: some View {
        Text(startDate, style: .timer)
            .monospacedDigit()
    }
}

/// The rest clock: counts DOWN while the rest timer runs, shows what is left
/// when it is paused, and shows a dash when it has never started.
struct RestClock: View {
    var state: WorkoutAttributes.ContentState
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("REST")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            content
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(state.restIsRunning ? Color.teal : .secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.restIsRunning, let end = state.restEndsAt, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else if state.restRemaining > 0 {
            Text(Self.mmss(state.restRemaining))
                .monospacedDigit()
        } else {
            Text("—")
                .monospacedDigit()
        }
    }

    static func mmss(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The lock-screen layout for an in-progress workout.
struct WorkoutLiveActivityView: View {
    var context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.teal)
                    Text(context.attributes.workoutName.isEmpty ? "Workout" : context.attributes.workoutName)
                        .font(.headline)
                        .lineLimit(1)
                }
                SessionClock(startDate: context.attributes.startDate)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                Text("\(context.state.exerciseCount) exercise\(context.state.exerciseCount == 1 ? "" : "s") · since \(context.attributes.startDate, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            RestClock(state: context.state, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }
}

@main
struct RepLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}
