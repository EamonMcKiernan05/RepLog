import Foundation
import SwiftUI
import UIKit
import AudioToolbox
import UserNotifications

/// What the workout Live Activity needs to draw the rest countdown.
struct RestTimerSnapshot: Equatable {
    var isRunning: Bool
    var endsAt: Date?
    var remaining: Int
    var total: Int
}

/// Rest timer (plan §6.8, T6.1). Background-safe: stores a deadline, never a
/// tick counter, so a 90 s timer survives backgrounding.
///
/// The interval comes from Settings → Timer → Default Rest Timer; −15/+15 nudge
/// it for the set in hand. When it finishes with the app on screen it vibrates
/// three times (and plays the ring); with the app away a local notification,
/// scheduled at start, does the job instead.
///
/// @unchecked Sendable: @Observable state is mutated on the main thread; the
/// tick task only reads/writes the deadline/remaining pair.
@Observable
final class RestTimerController: @unchecked Sendable {
    private(set) var duration: TimeInterval
    private(set) var remaining: TimeInterval
    private(set) var isRunning = false
    var deadline: Date?

    /// Pushed to the Live Activity on every state change — start, pause, nudge,
    /// reset, set-duration and the natural finish. Set by the workout screen.
    @ObservationIgnored var onChange: ((RestTimerSnapshot) -> Void)?

    static let settingKey = "timer.defaultRest"
    static let defaultDuration: TimeInterval = 90

    /// The choices Settings offers, in seconds.
    static let choices: [Int] = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    init(duration: TimeInterval? = nil) {
        // `double(forKey:)` reads both a Double written by Settings and the
        // string a `-timer.defaultRest 30` launch argument lands as.
        let stored = UserDefaults.standard.double(forKey: Self.settingKey)
        let d = max(5, duration ?? (stored > 0 ? stored : Self.defaultDuration))
        self.duration = d
        self.remaining = d
    }

    private var tickTask: Task<Void, Never>?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining / duration))
    }

    var display: String {
        let s = Int(remaining.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var snapshot: RestTimerSnapshot {
        RestTimerSnapshot(
            isRunning: isRunning && remaining > 0,
            endsAt: isRunning ? deadline : nil,
            remaining: Int(max(0, remaining.rounded())),
            total: Int(duration.rounded())
        )
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
            // The scheduled alert has to move with the deadline, or a −15s
            // nudge buzzes 15 seconds late.
            scheduleNotification(after: remaining)
        } else {
            duration = max(0, duration + delta)
            remaining = duration
        }
        notifyChange()
    }

    func toggle() {
        // At 00:00 the play button RESTARTS the interval rather than doing
        // nothing: a timer that has just finished is exactly when you press play
        // for the next set (found reading the bar back, 2026-10-23).
        if !isRunning && remaining <= 0 { remaining = duration }
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
        notifyChange()
    }

    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        cancelNotification()
        notifyChange()
    }

    /// The interval ran out. With the app on screen the cue is a haptic (the
    /// notification it also scheduled is withdrawn so the alert does not fire
    /// on top of it); away from the app the notification arrives instead.
    func finish() {
        let wasRunning = isRunning || remaining > 0
        isRunning = false
        remaining = 0
        deadline = nil
        tickTask?.cancel()
        tickTask = nil
        cancelNotification()
        if wasRunning { alertFinished() }
        notifyChange()
    }

    func stop() {
        finish()
        remaining = duration
        notifyChange()
    }

    private func notifyChange() {
        onChange?(snapshot)
    }

    /// Pick up a changed Settings interval when the timer has not been used yet
    /// (a workout already open when the default is changed should show the new
    /// number rather than yesterday's).
    func reloadDefaultIfIdle() {
        guard !isRunning, remaining == duration else { return }
        let stored = UserDefaults.standard.double(forKey: Self.settingKey)
        let d = max(5, stored > 0 ? stored : Self.defaultDuration)
        if d != duration {
            duration = d
            remaining = d
            notifyChange()
        }
    }

    // MARK: - Finish cue

    /// Three buzzes and an impact, only when the app is actually on screen —
    /// backgrounded, the scheduled notification is the cue and this does
    /// nothing (iOS would swallow a haptic from a background app anyway).
    private func alertFinished() {
        guard UIApplication.shared.applicationState == .active else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        Task { @MainActor in
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(450))
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    // MARK: - Notification (fires when the app is not on screen)

    private let notificationID = "replog.resttimer"

    private func scheduleNotification(after interval: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        // The bundle ships no .caf files, so every named sound resolved to a
        // file that does not exist: use the system default.
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(req) { error in
            if let error {
                print("[RepLog] rest-timer notification not scheduled: \(error)")
            }
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Ask for notification permission the first time a timer is started, so
    /// the alert that tells you rest is over arrives when the app is closed
    /// (owner request, 2026-10-23). Asked once: iOS remembers the answer, and a
    /// denied permission is not re-prompted — a silent no-op from then on.
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}
