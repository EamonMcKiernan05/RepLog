import SwiftUI
import SwiftData

/// Cross-tab navigation state.
@Observable
final class AppRouter {
    var selectedTab: Tab = .log

    enum Tab: String, CaseIterable {
        case log = "Log"
        case routines = "Routines"
        case statistics = "Statistics"
        case profile = "Profile"

        var icon: String {
            switch self {
            case .log: "book.closed"
            case .routines: "rectangle.stack"
            case .statistics: "chart.bar"
            case .profile: "person"
            }
        }
    }

    /// The session being edited in the active-workout screen (if any).
    var activeSessionId: String?

    /// Set to push the active-workout screen onto the Log tab's stack.
    var activeSession: Session?

    var isOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "onboarded")
    }

    func startWorkout(session: Session) {
        activeSession = session
        selectedTab = .log
    }
}
