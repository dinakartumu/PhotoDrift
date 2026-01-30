import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?
    @State private var launchAtLogin = false

    private let intervals: [(label: String, minutes: Int)] = [
        ("15 minutes", 15),
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
    ]

    var body: some View {
        Form {
            if let settings {
                Section("Shuffle Interval") {
                    Picker("Change wallpaper every", selection: Binding(
                        get: { settings.shuffleIntervalMinutes },
                        set: { settings.shuffleIntervalMinutes = $0 }
                    )) {
                        ForEach(intervals, id: \.minutes) { interval in
                            Text(interval.label).tag(interval.minutes)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Sources") {
                    Toggle("Apple Photos", isOn: Binding(
                        get: { settings.photosEnabled },
                        set: { settings.photosEnabled = $0 }
                    ))

                    Toggle("Adobe Lightroom", isOn: Binding(
                        get: { settings.lightroomEnabled },
                        set: { settings.lightroomEnabled = $0 }
                    ))

                    if settings.lightroomEnabled {
                        if settings.adobeAccessToken != nil {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Connected to Adobe")
                            }
                        } else {
                            Text("Sign in via Choose Albums > Lightroom tab")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("General") {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 340)
        .navigationTitle("Settings")
        .task {
            settings = AppSettings.current(in: modelContext)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
