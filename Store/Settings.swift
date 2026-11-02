import Foundation
import SwiftUI

/// App settings backed by UserDefaults (plan §3.1 #22, §6.4).
///
/// Every setting is a *stored* property (so `@Observable` tracks it and views
/// re-render when it changes) exposed through a computed accessor that also
/// persists to UserDefaults. The previous version used computed properties
/// that read UserDefaults directly; `@Observable` does not track those, so a
/// toggle or picker updated the store but never re-rendered the UI (a
/// permission row never appeared after its toggle was flipped).
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
        static let defaultRest = "timer.defaultRest"
        static let keepScreenOn = "timer.keepScreenOn"
        static let finishReminder = "log.finishReminder"
        static let analytics = "privacy.analytics"
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
    private var _defaultRest: Double =
        UserDefaults.standard.object(forKey: Key.defaultRest) as? Double ?? 90
    private var _keepScreenOn: Bool =
        UserDefaults.standard.object(forKey: Key.keepScreenOn) as? Bool ?? true
    private var _finishReminder: String =
        UserDefaults.standard.string(forKey: Key.finishReminder) ?? "off"
    private var _analytics: Bool =
        UserDefaults.standard.object(forKey: Key.analytics) as? Bool ?? true
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
    /// The rest timer's starting interval, in seconds (Settings → Timer). The
    /// workout's timer reads it once when it opens, and −15/+15 nudge from
    /// there. `Key.defaultRest` is the same UserDefaults key
    /// `RestTimerController.settingKey` reads, so no extra plumbing.
    var defaultRest: Double {
        get { _defaultRest }
        set {
            _defaultRest = newValue
            UserDefaults.standard.set(newValue, forKey: Key.defaultRest)
        }
    }
    var keepScreenOn: Bool {
        get { _keepScreenOn }
        set { _keepScreenOn = newValue; UserDefaults.standard.set(newValue, forKey: Key.keepScreenOn) }
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
    var onboarded: Bool {
        get { _onboarded }
        set { _onboarded = newValue; UserDefaults.standard.set(newValue, forKey: Key.onboarded) }
    }
    /// Global single-arm/leg default (article 46).
    var singleLimbDefault: Bool {
        get { _singleLimbDefault }
        set { _singleLimbDefault = newValue; UserDefaults.standard.set(newValue, forKey: Key.singleLimbDefault) }
    }
}
