import SwiftUI
import SwiftData

@main
struct PhotoDriftApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Album.self,
            Asset.self,
            AppSettings.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var shuffleEngine: ShuffleEngine?

    var body: some Scene {
        MenuBarExtra("PhotoDrift", systemImage: "photo.on.rectangle.angled") {
            MenuBarView(shuffleEngine: shuffleEngine)
                .modelContainer(sharedModelContainer)
                .onOpenURL { url in
                    guard url.scheme == AdobeConfig.callbackScheme else { return }
                    Task {
                        await AdobeAuthManager.shared.handleCallback(url: url)
                    }
                }
                .onAppear {
                    if shuffleEngine == nil {
                        let engine = ShuffleEngine(modelContainer: sharedModelContainer)
                        shuffleEngine = engine
                        loadSavedTokens()
                        autoStartIfNeeded(engine)
                        observeWake(engine)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .modelContainer(sharedModelContainer)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Choose Albums", id: "album-picker") {
            AlbumPickerWindow()
                .modelContainer(sharedModelContainer)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private func loadSavedTokens() {
        let context = ModelContext(sharedModelContainer)
        let settings = AppSettings.current(in: context)
        Task {
            await AdobeAuthManager.shared.configure(modelContainer: sharedModelContainer)
            await AdobeAuthManager.shared.loadTokens(from: settings)
        }
    }

    private func autoStartIfNeeded(_ engine: ShuffleEngine) {
        let context = ModelContext(sharedModelContainer)
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isSelected == true }
        )
        if let albums = try? context.fetch(descriptor), !albums.isEmpty {
            engine.start()
        }
    }

    private func observeWake(_ engine: ShuffleEngine) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            engine.handleWake()
        }
    }
}
