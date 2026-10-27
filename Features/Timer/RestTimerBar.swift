import SwiftUI

/// The rest timer as a bar pinned to the bottom of an OPEN workout (owner
/// request, 2026-10-23; reshaped 2026-10-27: "make the timer bar actually fill
/// the whole bottom part of the screen and not be a floating pill. its the same
/// colour as the background and really hard to see the end of it").
///
/// It is edge-to-edge and flush with the bottom of the display, sitting on a
/// surface one step lighter than the page, with a hairline along its top edge
/// and a progress line pinned to the very bottom. The line is the "end of it":
/// accent over a visible track, shrinking as the interval runs out, so the bar
/// reads as a timer even before you read the digits.
///
/// Collapsed it is one row: a clock, the countdown, play/pause, reset, and a
/// chevron. Expanded it adds the ring and −15s / +15s. The interval itself is
/// set in Settings → Timer (the preset circles are gone, owner request).
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
            progressLine
        }
        .background {
            // Full bleed: the bar's surface reaches the physical bottom edge of
            // the display instead of stopping above the home indicator.
            Palette.control.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.separator)
                .frame(height: 0.5)
        }
        .animation(.easeOut(duration: 0.18), value: expanded)
        // NOTE: no accessibilityIdentifier on this container. An identifier on a
        // container OVERWRITES every child's identifier — measured 2026-10-27:
        // with `timer-bar` here, `timer-display`, `timer-toggle`, `timer-reset`
        // and `timer-expand` all reported identifier 'timer-bar' and no query
        // for them could match. The pieces are identified individually.
    }

    // MARK: - Progress line (the visible "end of it")

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Palette.separator)
                Rectangle()
                    .fill(controller.isRunning || controller.remaining < controller.duration
                          ? Palette.accent
                          : Palette.textSecondary.opacity(0.35))
                    .frame(width: max(0, geo.size.width * controller.progress))
            }
        }
        .frame(height: 3)
        .accessibilityIdentifier("timer-progress")
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Expanded controls

    private var expandedBody: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Palette.separator, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: controller.progress)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(controller.display)
                    .font(Typography.mono(34, .bold))
                    .monospacedDigit()
            }
            .frame(width: 150, height: 150)
            .padding(.top, 16)

            HStack(spacing: 20) {
                Button {
                    controller.nudge(-15)
                } label: {
                    Text("−15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Palette.bg))
                }
                .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isRunning ? "Pause" : "Start")

                Button {
                    controller.nudge(15)
                } label: {
                    Text("+15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Palette.bg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plus 15 seconds")
            }
            .padding(.bottom, 12)

            Text("Rest length is set in Settings → Timer.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, 10)
        }
    }

    private func toggleExpanded() {
        expanded.toggle()
    }
}
