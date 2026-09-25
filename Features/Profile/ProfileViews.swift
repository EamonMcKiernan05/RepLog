import SwiftUI
import SwiftData

/// Profile tab (plan §6.6): Sync section (replaces the account block),
/// Edit Exercises, Edit Categories, Feedback, Show Your Support.
/// No Premium upsell.
struct ProfileTabView: View {
    @Environment(DataStore.self) private var store
    @Environment(Settings.self) private var settings
    @Environment(SyncEngine.self) private var sync
    @State private var showSettings = false
    @State private var showEditExercises = false
    @State private var showEditCategories = false
    @State private var showExport = false

    /// The sync control's own text: the old Log button's wording, moved here
    /// with it (owner, 2026-09-25: the Log's toolbar is a single +).
    private var syncControlTitle: String {
        if sync.isSyncing { return "Syncing…" }
        if sync.outbox.queuedCount > 0 {
            let n = sync.outbox.queuedCount
            return "\(n) to sync"
        }
        return sync.statusText
    }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var sync = sync
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
                Section("Sync") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Sync lives here now: the Log's toolbar is a single +
                        // (owner, 2026-09-25: "remove the 'n to sync' button on
                        // the top of the log page. Just make it a single +
                        // button"). It is still manual — nothing uploads on
                        // launch or when the network comes back — so the control
                        // has to stay somewhere reachable.
                        Button {
                            sync.syncNow()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(sync.authFailed ? Palette.destructive
                                          : (settings.syncEnabled ? Palette.success : Palette.textSecondary))
                                    .frame(width: 8, height: 8)
                                Text(syncControlTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                if sync.isSyncing {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                // Explicit hit shape: in a List row a
                                // .plain Button whose label has a Spacer has
                                // no tap area of its own — the tap lands on
                                // the row and nothing happens (found
                                // 2026-09-25: the drill tapped it, the sync
                                // never ran and the service saw no request).
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(sync.isSyncing)
                        .accessibilityIdentifier("sync-now")
                        // The label is the real state — "1 to sync", "Up to
                        // date · 2 minutes ago", "Auth failed — check your
                        // token" — not a constant "Sync now".
                        .accessibilityLabel(syncControlTitle)
                        if settings.syncEnabled {
                            HStack {
                                Text("Server")
                                Spacer()
                                Text(settings.syncURL)
                                    .font(.caption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Button {
                            showExport = true
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

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
                    ImportCSVButton()
                }
                Section("About") {
                    HStack {
                        Text("RepLog")
                        Spacer()
                        Text("1.1.7")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    HStack {
                        Text("Sync is manual: tap the sync control above when you want to upload.")
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
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        @Bindable var sync = sync
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
                Section("Sync") {
                    Toggle("Enable Sync", isOn: $settings.syncEnabled)
                        .accessibilityIdentifier("enable-sync")
                    if settings.syncEnabled {
                        TextField("Server URL", text: $settings.syncURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("sync-url-field")
                        SecureField("Token", text: $settings.syncToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("sync-token-field")
                        Button("Test Connection") {
                            Task {
                                sync.applyConfig()
                                _ = await sync.client.health()
                            }
                        }
                        .disabled(settings.syncURL.isEmpty)
                        .accessibilityIdentifier("test-connection")
                    }
                    Text("RepLog talks to your lift-sync server over plain HTTP on your local network or tailnet. The token is stored in the Keychain.")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        sync.applyConfig()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("done")
                }
            }
        }
    }
}

/// Onboarding (plan §6.9): units; "your data stays on this phone";
/// optional sync. No account, nothing mandatory.
struct OnboardingView: View {
    @Environment(Settings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var page = 0
    @State private var syncURL = ""
    @State private var syncToken = ""

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
                Text("RepLog stores everything locally with SwiftData. Sync to your own lift-sync server is optional — nothing leaves this device until you turn it on.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .tag(1)

            // Page 3: optional sync
            VStack(spacing: 20) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.accent)
                Text("Optional: sync to your server")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                TextField("http://192.168.1.12:8080", text: $syncURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-sync-url")
                SecureField("Token", text: $syncToken)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-sync-token")
                Text("Leave blank to skip. You can set this up later in Profile → Settings.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .tag(2)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if page < 2 {
                    page += 1
                } else {
                    finish()
                }
            } label: {
                Text(page < 2 ? "Continue" : "Get Started")
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
        if !syncURL.isEmpty {
            settings.syncURL = syncURL
            settings.syncToken = syncToken
            settings.syncEnabled = true
        }
        settings.onboarded = true
        // Observable flip so RootTabView re-renders to the main app in-session.
        router.isOnboarding = false
    }
}
