import SwiftUI
import SwiftData

/// Profile tab (plan §6.6): Settings, Edit Exercises, Edit Categories,
/// Feedback, Show Your Support, Data. No Premium upsell.
struct ProfileTabView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    @State private var showSettings = false
    @State private var showEditExercises = false
    @State private var showEditCategories = false
    @State private var showExport = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Palette.accent)
                            Text("Settings")
                        }
                    }
                    .accessibilityIdentifier("settings-link")
                }
                Section {
                    Button {
                        showEditExercises = true
                    } label: {
                        Label("Edit Exercises", systemImage: "dumbbell")
                    }
                    Button {
                        showEditCategories = true
                    } label: {
                        Label("Edit Categories", systemImage: "list.bullet")
                    }
                }
                Section("Feedback") {
                    Link(destination: URL(string: "mailto:enquiries@eamonmckiernan.im?subject=RepLog%20feedback")!) {
                        Label("Send Feedback", systemImage: "exclamationmark.bubble")
                    }
                    Link(destination: URL(string: "https://github.com/EamonMcKiernan05/RepLog")!) {
                        Label("Help and Support", systemImage: "questionmark.bubble")
                    }
                }
                Section("Data") {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export-csv")
                    ImportCSVButton()
                }
                Section("About") {
                    HStack {
                        Text("RepLog")
                        Spacer()
                        // Read from the bundle: a hard-coded version goes stale
                        // the moment the build number moves (it said 1.1.7 on a
                        // 1.1.8 build).
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .background(Palette.bg)
            .navigationTitle("Profile")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEditExercises) {
                EditExercisesView()
            }
            .sheet(isPresented: $showEditCategories) {
                EditCategoriesView()
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
        }
    }
}

/// Settings (plan §3.1 #22, §6.4, T6.4): every toggle from the matrix.
struct SettingsView: View {
    @Environment(Settings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Charts") {
                    Toggle("Show Actual Data", isOn: $settings.showActualData)
                    Toggle("Show Trend Line", isOn: $settings.showTrend)
                    Toggle("Include Warmup", isOn: $settings.includeWarmup)
                    Toggle("Count Single Arm / Single Leg twice", isOn: $settings.countSingleLimbTwice)
                }
                Section {
                    Picker("Exercise Database Language", selection: $settings.dbLanguage) {
                        Text("English").tag("English")
                    }
                    Picker("Weight Unit", selection: $settings.unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { u in
                            Text(u.display).tag(u)
                        }
                    }
                }
                Section("Integrations") {
                    Toggle("Apple Health", isOn: $settings.healthEnabled)
                }
                Section("Workout Log") {
                    Toggle("Autofill Weight", isOn: $settings.autofillWeight)
                    Toggle("Autocorrect for set notes", isOn: $settings.autocorrectNotes)
                    Toggle("Keep screen on when workout is active", isOn: $settings.keepScreenOn)
                }
                Section("Timer") {
                    Picker("Timer Sound", selection: $settings.timerSound) {
                        Text("Default").tag("default")
                        Text("Bell").tag("bell")
                        Text("Horn").tag("horn")
                        Text("Alarm").tag("alarm")
                    }
                    Toggle("Auto-start timer", isOn: $settings.autoStartTimer)
                    Toggle("Per-second buzz", isOn: $settings.perSecondBuzz)
                }
                Section("Privacy") {
                    Toggle("Send Anonymous Analytics", isOn: $settings.analytics)
                    Text("Nothing is sent. This toggle exists for parity and is wired to nothing.")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("done")
                }
            }
        }
    }
}

/// Onboarding (plan §6.9): units; "your data stays on this phone".
/// No account, nothing mandatory, and nothing to configure now that sync is
/// gone (2026-10-23) — a CSV export is the way a copy leaves the phone.
struct OnboardingView: View {
    @Environment(Settings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var page = 0

    var body: some View {
        @Bindable var settings = settings
        TabView(selection: $page) {
            // Page 1: units
            VStack(spacing: 24) {
                Image(systemName: "scalemass")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.accent)
                Text("Choose your weight unit")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Picker("Unit", selection: $settings.unit) {
                    ForEach(WeightUnit.allCases, id: \.self) { u in
                        Text(u.display).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
            }
            .tag(0)

            // Page 2: privacy
            VStack(spacing: 24) {
                Image(systemName: "iphone")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.accent)
                Text("Your data stays on this phone")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("RepLog stores everything locally with SwiftData. Nothing leaves this device: you export a CSV when you want a copy.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .tag(1)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if page < 1 {
                    page += 1
                } else {
                    finish()
                }
            } label: {
                Text(page < 1 ? "Continue" : "Get Started")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .padding()
            .accessibilityIdentifier("onboarding-next")
        }
    }

    private func finish() {
        settings.onboarded = true
        // Observable flip so RootTabView re-renders to the main app in-session.
        router.isOnboarding = false
    }
}
