import Foundation
import SwiftUI

/// App settings backed by UserDefaults (plan §3.1 #22, §6.4).
///
/// Every setting is a *stored* property (so `@Observable` tracks it and views
/// re-render when it changes) exposed through a computed accessor that also
/// persists to UserDefaults. The previous version used computed properties
/// that read UserDefaults directly; `@Observable` does not track those, so a
/// toggle or picker updated the store but never re-rendered the UI (e.g. the
/// Sync URL field never appeared after enabling sync).
@Observable
final class Settings {
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
        static let singleLimbDefault = "singleLimbDefault"
    }

    // MARK: Backing stored properties (observed), initialised from UserDefaults.

    private var _unit: WeightUnit =
        WeightUnit(rawValue: UserDefaults.standard.string(forKey: Key.unit) ?? "") ?? .kg
    private var _showActualData: Bool =
        UserDefaults.standard.object(forKey: Key.showActualData) as? Bool ?? true
    private var _showTrend: Bool =
        UserDefaults.standard.object(forKey: Key.showTrend) as? Bool ?? true
    private var _includeWarmup: Bool =
        UserDefaults.standard.object(forKey: Key.includeWarmup) as? Bool ?? false
    private var _countSingleLimbTwice: Bool =
        UserDefaults.standard.object(forKey: Key.countSingleLimbTwice) as? Bool ?? false
    private var _dbLanguage: String =
        UserDefaults.standard.string(forKey: Key.dbLanguage) ?? "English"
    private var _healthEnabled: Bool =
        UserDefaults.standard.object(forKey: Key.healthEnabled) as? Bool ?? false
    private var _autofillWeight: Bool =
        UserDefaults.standard.object(forKey: Key.autofillWeight) as? Bool ?? true
    private var _autocorrectNotes: Bool =
        UserDefaults.standard.object(forKey: Key.autocorrectNotes) as? Bool ?? true
    private var _timerSound: String =
        UserDefaults.standard.string(forKey: Key.timerSound) ?? "default"
    private var _autoStartTimer: Bool =
        UserDefaults.standard.object(forKey: Key.autoStartTimer) as? Bool ?? false
    private var _keepScreenOn: Bool =
        UserDefaults.standard.object(forKey: Key.keepScreenOn) as? Bool ?? true
    private var _perSecondBuzz: Bool =
        UserDefaults.standard.object(forKey: Key.perSecondBuzz) as? Bool ?? false
    private var _finishReminder: String =
        UserDefaults.standard.string(forKey: Key.finishReminder) ?? "off"
    private var _analytics: Bool =
        UserDefaults.standard.object(forKey: Key.analytics) as? Bool ?? true
    private var _syncEnabled: Bool =
        UserDefaults.standard.object(forKey: Key.syncEnabled) as? Bool ?? false
    private var _syncURL: String =
        UserDefaults.standard.string(forKey: Key.syncURL) ?? ""
    private var _onboarded: Bool =
        UserDefaults.standard.object(forKey: Key.onboarded) as? Bool ?? false
    private var _singleLimbDefault: Bool =
        UserDefaults.standard.object(forKey: Key.singleLimbDefault) as? Bool ?? false

    // MARK: Persisting accessors

    var unit: WeightUnit {
        get { _unit }
        set { _unit = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: Key.unit) }
    }
    var showActualData: Bool {
        get { _showActualData }
        set { _showActualData = newValue; UserDefaults.standard.set(newValue, forKey: Key.showActualData) }
    }
    var showTrend: Bool {
        get { _showTrend }
        set { _showTrend = newValue; UserDefaults.standard.set(newValue, forKey: Key.showTrend) }
    }
    var includeWarmup: Bool {
        get { _includeWarmup }
        set { _includeWarmup = newValue; UserDefaults.standard.set(newValue, forKey: Key.includeWarmup) }
    }
    var countSingleLimbTwice: Bool {
        get { _countSingleLimbTwice }
        set { _countSingleLimbTwice = newValue; UserDefaults.standard.set(newValue, forKey: Key.countSingleLimbTwice) }
    }
    var dbLanguage: String {
        get { _dbLanguage }
        set { _dbLanguage = newValue; UserDefaults.standard.set(newValue, forKey: Key.dbLanguage) }
    }
    var healthEnabled: Bool {
        get { _healthEnabled }
        set { _healthEnabled = newValue; UserDefaults.standard.set(newValue, forKey: Key.healthEnabled) }
    }
    var autofillWeight: Bool {
        get { _autofillWeight }
        set { _autofillWeight = newValue; UserDefaults.standard.set(newValue, forKey: Key.autofillWeight) }
    }
    var autocorrectNotes: Bool {
        get { _autocorrectNotes }
        set { _autocorrectNotes = newValue; UserDefaults.standard.set(newValue, forKey: Key.autocorrectNotes) }
    }
    var timerSound: String {
        get { _timerSound }
        set { _timerSound = newValue; UserDefaults.standard.set(newValue, forKey: Key.timerSound) }
    }
    var autoStartTimer: Bool {
        get { _autoStartTimer }
        set { _autoStartTimer = newValue; UserDefaults.standard.set(newValue, forKey: Key.autoStartTimer) }
    }
    var keepScreenOn: Bool {
        get { _keepScreenOn }
        set { _keepScreenOn = newValue; UserDefaults.standard.set(newValue, forKey: Key.keepScreenOn) }
    }
    var perSecondBuzz: Bool {
        get { _perSecondBuzz }
        set { _perSecondBuzz = newValue; UserDefaults.standard.set(newValue, forKey: Key.perSecondBuzz) }
    }
    var finishReminder: String {
        get { _finishReminder }
        set { _finishReminder = newValue; UserDefaults.standard.set(newValue, forKey: Key.finishReminder) }
    }
    /// Toggle stays (plan: wired to nothing — nothing is sent).
    var analytics: Bool {
        get { _analytics }
        set { _analytics = newValue; UserDefaults.standard.set(newValue, forKey: Key.analytics) }
    }
    var syncEnabled: Bool {
        get { _syncEnabled }
        set { _syncEnabled = newValue; UserDefaults.standard.set(newValue, forKey: Key.syncEnabled) }
    }
    var syncURL: String {
        get { _syncURL }
        set { _syncURL = newValue; UserDefaults.standard.set(newValue, forKey: Key.syncURL) }
    }
    var onboarded: Bool {
        get { _onboarded }
        set { _onboarded = newValue; UserDefaults.standard.set(newValue, forKey: Key.onboarded) }
    }
    /// Global single-arm/leg default (article 46).
    var singleLimbDefault: Bool {
        get { _singleLimbDefault }
        set { _singleLimbDefault = newValue; UserDefaults.standard.set(newValue, forKey: Key.singleLimbDefault) }
    }

    /// The sync token lives in the Keychain, never UserDefaults.
    var syncToken: String {
        get { Keychain.get("syncToken") ?? "" }
        set { Keychain.set(newValue, "syncToken") }
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
