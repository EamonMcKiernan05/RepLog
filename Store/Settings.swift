import Foundation
import SwiftUI

/// App settings backed by UserDefaults (plan §3.1 #22, §6.4).
@Observable
final class Settings {
    private let d = UserDefaults.standard

    private enum Key {
        static let unit = "unit"
        static let showActualData = "charts.showActual"
        static let showTrend = "charts.showTrend"
        static let includeWarmup = "charts.includeWarmup"
        static let countSingleLimbTwice = "charts.countSingleLimbTwice"
        static let dbLanguage = "dbLanguage"
        static let healthEnabled = "health.enabled"
        static let autofillWeight = "log.autofillWeight"
        static let autocorrectNotes = "log.autocorrectNotes"
        static let timerSound = "timer.sound"
        static let autoStartTimer = "timer.autoStart"
        static let keepScreenOn = "timer.keepScreenOn"
        static let perSecondBuzz = "timer.perSecondBuzz"
        static let finishReminder = "log.finishReminder"
        static let analytics = "privacy.analytics"
        static let syncEnabled = "sync.enabled"
        static let syncURL = "sync.url"
        static let onboarded = "onboarded"
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: d.string(forKey: Key.unit) ?? "") ?? .kg }
        set { d.set(newValue.rawValue, forKey: Key.unit) }
    }

    var showActualData: Bool {
        get { d.object(forKey: Key.showActualData) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showActualData) }
    }

    var showTrend: Bool {
        get { d.object(forKey: Key.showTrend) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.showTrend) }
    }

    var includeWarmup: Bool {
        get { d.object(forKey: Key.includeWarmup) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.includeWarmup) }
    }

    var countSingleLimbTwice: Bool {
        get { d.object(forKey: Key.countSingleLimbTwice) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.countSingleLimbTwice) }
    }

    var dbLanguage: String {
        get { d.string(forKey: Key.dbLanguage) ?? "English" }
        set { d.set(newValue, forKey: Key.dbLanguage) }
    }

    var healthEnabled: Bool {
        get { d.object(forKey: Key.healthEnabled) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.healthEnabled) }
    }

    var autofillWeight: Bool {
        get { d.object(forKey: Key.autofillWeight) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.autofillWeight) }
    }

    var autocorrectNotes: Bool {
        get { d.object(forKey: Key.autocorrectNotes) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.autocorrectNotes) }
    }

    var timerSound: String {
        get { d.string(forKey: Key.timerSound) ?? "default" }
        set { d.set(newValue, forKey: Key.timerSound) }
    }

    var autoStartTimer: Bool {
        get { d.object(forKey: Key.autoStartTimer) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.autoStartTimer) }
    }

    var keepScreenOn: Bool {
        get { d.object(forKey: Key.keepScreenOn) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.keepScreenOn) }
    }

    var perSecondBuzz: Bool {
        get { d.object(forKey: Key.perSecondBuzz) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.perSecondBuzz) }
    }

    var finishReminder: String {
        get { d.string(forKey: Key.finishReminder) ?? "off" }
        set { d.set(newValue, forKey: Key.finishReminder) }
    }

    /// Toggle stays (plan: wired to nothing — nothing is sent).
    var analytics: Bool {
        get { d.object(forKey: Key.analytics) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.analytics) }
    }

    var syncEnabled: Bool {
        get { d.object(forKey: Key.syncEnabled) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.syncEnabled) }
    }

    var syncURL: String {
        get { d.string(forKey: Key.syncURL) ?? "" }
        set { d.set(newValue, forKey: Key.syncURL) }
    }

    var onboarded: Bool {
        get { d.bool(forKey: Key.onboarded) }
        set { d.set(newValue, forKey: Key.onboarded) }
    }

    /// The sync token lives in the Keychain, never UserDefaults.
    var syncToken: String {
        get { Keychain.get("syncToken") ?? "" }
        set { Keychain.set(newValue, "syncToken") }
    }

    /// Global single-arm/leg default (article 46).
    var singleLimbDefault: Bool {
        get { d.object(forKey: "singleLimbDefault") as? Bool ?? false }
        set { d.set(newValue, forKey: "singleLimbDefault") }
    }
}

/// Minimal Keychain wrapper for the sync token.
enum Keychain {
    static func set(_ value: String, _ key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
