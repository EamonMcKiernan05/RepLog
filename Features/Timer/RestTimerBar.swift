import SwiftUI

/// The rest timer as a bar pinned to the bottom of an OPEN workout (owner
/// request, 2026-10-23: "a collapsible bar at the bottom of the screen, only
/// showing inside the active session. The bar should be there permanently and
/// has all the timer controls").
///
/// Collapsed it is one row: a clock, the countdown, play/pause, reset, and a
/// chevron. Expanded it adds the ring, −15s / +15s and the preset chips.
/// Nothing here starts or stops the workout; it is the stopwatch you glance at
/// between sets.
struct RestTimerBar: View {
    @Bindable var controller: RestTimerController

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            collapsedRow
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: expanded)
        .accessibilityIdentifier("timer-bar")
    }

    // MARK: - Collapsed row (always visible)

    private var collapsedRow: some View {
        HStack(spacing: 12) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: "timer")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(controller.isRunning ? Palette.accent : Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide timer controls" : "Show timer controls")

            Text(controller.display)
                .font(Typography.mono(22, .bold))
                .monospacedDigit()
                .foregroundStyle(controller.remaining == 0 ? Palette.textSecondary : Palette.textPrimary)
                .accessibilityIdentifier("timer-display")
                .onTapGesture { toggleExpanded() }

            Spacer(minLength: 0)

            Button {
                RestTimerController.requestAuthorizationIfNeeded()
                controller.toggle()
            } label: {
                Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isRunning ? "Pause timer" : "Start timer")
            .accessibilityIdentifier("timer-toggle")

            Button {
                controller.stop()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset timer")
            .accessibilityIdentifier("timer-reset")

            Button {
                toggleExpanded()
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse timer" : "Expand timer")
            .accessibilityIdentifier("timer-expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded controls

    private var expandedBody: some View {
        VStack(spacing: 16) {
            Divider()
            ZStack {
                Circle()
                    .stroke(Palette.control, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: controller.progress)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(controller.display)
                    .font(Typography.mono(34, .bold))
                    .monospacedDigit()
            }
            .frame(width: 150, height: 150)
            .padding(.top, 12)

            HStack(spacing: 20) {
                Button {
                    controller.nudge(-15)
                } label: {
                    Text("−15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Palette.control))
                }
                .accessibilityLabel("Minus 15 seconds")

                Button {
                    RestTimerController.requestAuthorizationIfNeeded()
                    controller.toggle()
                } label: {
                    Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.black)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Palette.accent))
                }
                .accessibilityLabel(controller.isRunning ? "Pause" : "Start")

                Button {
                    controller.nudge(15)
                } label: {
                    Text("+15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Palette.control))
                }
                .accessibilityLabel("Plus 15 seconds")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(controller.presets, id: \.self) { preset in
                        Button {
                            controller.setDuration(preset)
                        } label: {
                            Text(Self.format(preset))
                                .font(Typography.mono(15, .bold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle().fill(
                                        controller.duration == preset
                                        ? AnyShapeStyle(Palette.accent.opacity(0.25))
                                        : AnyShapeStyle(Palette.control)
                                    )
                                )
                                .overlay(
                                    Circle().stroke(
                                        controller.duration == preset ? Palette.accent : .clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                        .accessibilityIdentifier("timer-preset-\(Int(preset))")
                    }
                    Button {
                        addPreset()
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Palette.control))
                    }
                    .accessibilityLabel("Add preset")
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 8)
        }
    }

    private func toggleExpanded() {
        expanded.toggle()
    }

    private func addPreset() {
        if !controller.presets.contains(controller.duration) {
            controller.presets.append(controller.duration)
            controller.presets.sort()
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
