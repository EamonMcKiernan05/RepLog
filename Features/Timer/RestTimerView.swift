import SwiftUI

/// Rest timer sheet (plan §6.8): big ring, countdown, −15s / play / +15s,
/// preset chips (00:30, 00:45, 01:00, 01:30, +).
struct RestTimerView: View {
    @Bindable var controller: RestTimerController
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Close button
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white))
                }
                .accessibilityLabel("Close timer")
            }

            // Ring + time
            ZStack {
                Circle()
                    .stroke(Palette.control, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: controller.progress)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(controller.display)
                    .font(Typography.mono(52, .bold))
                    .monospacedDigit()
            }
            .frame(width: 240, height: 240)
            .padding(.top, 8)

            // Controls
            HStack(spacing: 24) {
                Button {
                    controller.nudge(-15)
                } label: {
                    Text("−15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Palette.control))
                }
                .accessibilityLabel("Minus 15 seconds")

                Button {
                    controller.toggle()
                } label: {
                    Image(systemName: controller.isRunning ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.black)
                        .frame(width: 88, height: 88)
                        .background(Circle().fill(Palette.accent))
                }
                .accessibilityLabel(controller.isRunning ? "Pause" : "Start")

                Button {
                    controller.nudge(15)
                } label: {
                    Text("+15s")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Palette.control))
                }
                .accessibilityLabel("Plus 15 seconds")
            }

            Divider().padding(.horizontal, 8)

            // Presets
            HStack {
                Text("Timers")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Add Preset…") { addPreset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(controller.presets, id: \.self) { p in
                        Button {
                            controller.setDuration(p)
                        } label: {
                            Text(Self.format(p))
                                .font(Typography.mono(16, .bold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 64, height: 64)
                                .background(
                                    Circle().fill(
                                        controller.duration == p
                                        ? AnyShapeStyle(Palette.accent.opacity(0.25))
                                        : AnyShapeStyle(Palette.control)
                                    )
                                )
                                .overlay(
                                    Circle().stroke(
                                        controller.duration == p ? Palette.accent : .clear,
                                        lineWidth: 2
                                    )
                                )
                        }
                    }
                    Button {
                        addPreset()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Palette.control))
                    }
                    .accessibilityLabel("Add preset")
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func addPreset() {
        // Add the current duration as a preset if not already present.
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
