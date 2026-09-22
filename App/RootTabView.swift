import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings

    var body: some View {
        if router.isOnboarding {
            OnboardingView()
        } else {
            TabView(selection: $router.selectedTab) {
                LogTabView()
                    .tabItem { Label(AppRouter.Tab.log.rawValue, systemImage: AppRouter.Tab.log.icon) }
                    .tag(AppRouter.Tab.log)
                RoutinesTabView()
                    .tabItem { Label(AppRouter.Tab.routines.rawValue, systemImage: AppRouter.Tab.routines.icon) }
                    .tag(AppRouter.Tab.routines)
                StatisticsTabView()
                    .tabItem { Label(AppRouter.Tab.statistics.rawValue, systemImage: AppRouter.Tab.statistics.icon) }
                    .tag(AppRouter.Tab.statistics)
                ProfileTabView()
                    .tabItem { Label(AppRouter.Tab.profile.rawValue, systemImage: AppRouter.Tab.profile.icon) }
                    .tag(AppRouter.Tab.profile)
            }
        }
    }
}
