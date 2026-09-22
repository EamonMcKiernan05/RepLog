import Foundation
import SwiftUI
import UserNotifications

/// Rest timer (plan §6.8, T6.1). Background-safe: stores a deadline, never a
/// tick counter, so a 90 s timer survives backgrounding.
/// @unchecked Sendable: @Observable state is mutated on the main thread; the
/// tick task only reads/writes the deadline/remaining pair.
@Observable
final class RestTimerController: @unchecked Sendable {
    private(set) var duration: TimeInterval = 90
    private(set) var remaining: TimeInterval = 90
    private(set) var isRunning = false
    var deadline: Date?

    /// Preset chips (plan §6.8).
    var presets: [TimeInterval] = [30, 45, 60, 90, 120]

    private var tickTask: Task<Void, Never>?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining / duration))
    }

    var display: String {
        let s = Int(remaining.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func setDuration(_ t: TimeInterval) {
        duration = max(0, t)
        remaining = duration
        stop()
    }

    func nudge(_ delta: TimeInterval) {
        if isRunning {
            remaining = max(0, remaining + delta)
            deadline = Date().addingTimeInterval(remaining)
        } else {
            duration = max(0, duration + delta)
            remaining = duration
        }
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard remaining > 0 else { return }
        isRunning = true
        deadline = Date().addingTimeInterval(remaining)
        scheduleNotification(after: remaining)
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning, let dl = self.deadline else { return }
                self.remaining = max(0, dl.timeIntervalSinceNow)
                if self.remaining <= 0 {
                    self.finish()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        cancelNotification()
    }

    func finish() {
        isRunning = false
        remaining = 0
        deadline = nil
        tickTask?.cancel()
        tickTask = nil
    }

    func stop() {
        finish()
        remaining = duration
    }

    // MARK: - Notification-based sound (article 53: follows ringer volume)

    private let notificationID = "replog.resttimer"

    private func scheduleNotification(after interval: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(req)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removeAllPendingNotificationRequests()
    }

    /// Map the settings sound choice to a system sound file name.
    private var soundName: String {
        switch UserDefaults.standard.string(forKey: "timer.sound") ?? "default" {
        case "bell": return "bell.caf"
        case "horn": return "horn.caf"
        case "alarm": return "alarm.caf"
        default: return "default.caf"
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
