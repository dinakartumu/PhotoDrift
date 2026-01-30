import SwiftUI
import SwiftData
import Photos

struct AlbumPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Source", selection: $selectedTab) {
                Text("Photos").tag(0)
                Text("Lightroom").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                PhotosAlbumList()
            } else {
                LightroomAlbumList()
            }
        }
    }
}

struct PhotosAlbumList: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Album> { $0.sourceTypeRaw == "applePhotos" })
    private var photosAlbums: [Album]

    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch authStatus {
            case .authorized, .limited:
                if photosAlbums.isEmpty && !isLoading {
                    Text("No albums found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(photosAlbums) { album in
                        Toggle(isOn: Binding(
                            get: { album.isSelected },
                            set: { album.isSelected = $0 }
                        )) {
                            HStack {
                                Text(album.name)
                                Spacer()
                                Text("\(album.assetCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            case .denied, .restricted:
                Text("Photos access denied. Open System Settings to grant access.")
                    .font(.caption)
                    .foregroundStyle(.red)
            default:
                Button("Grant Photos Access") {
                    Task { await requestAccess() }
                }
            }
        }
        .task {
            authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if authStatus == .authorized || authStatus == .limited {
                await refreshAlbums()
            }
        }
    }

    private func requestAccess() async {
        authStatus = await PhotoKitConnector.shared.requestAuthorization()
        if authStatus == .authorized || authStatus == .limited {
            await refreshAlbums()
        }
    }

    private func refreshAlbums() async {
        isLoading = true
        let infos = await PhotoKitConnector.shared.fetchAlbums()
        let fetchedIDs = Set(infos.map(\.id))

        for album in photosAlbums where !fetchedIDs.contains(album.id) {
            modelContext.delete(album)
        }

        for info in infos {
            if let existing = photosAlbums.first(where: { $0.id == info.id }) {
                existing.name = info.name
                existing.assetCount = info.assetCount
            } else {
                let album = Album(id: info.id, name: info.name, sourceType: .applePhotos, assetCount: info.assetCount)
                modelContext.insert(album)
            }
        }

        isLoading = false
    }
}

struct LightroomAlbumList: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Album> { $0.sourceTypeRaw == "lightroomCloud" })
    private var lightroomAlbums: [Album]

    @State private var isSignedIn = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSignedIn {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected")
                        .font(.caption)
                    Spacer()
                    Button("Sign Out") {
                        Task { await signOut() }
                    }
                    .font(.caption)
                }

                if lightroomAlbums.isEmpty && !isLoading {
                    Text("No albums found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(lightroomAlbums) { album in
                        Toggle(isOn: Binding(
                            get: { album.isSelected },
                            set: { album.isSelected = $0 }
                        )) {
                            Text(album.name)
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Button("Sign in to Adobe Lightroom") {
                    Task { await signIn() }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task {
            let settings = AppSettings.current(in: modelContext)
            await AdobeAuthManager.shared.loadTokens(from: settings)
            isSignedIn = await AdobeAuthManager.shared.isSignedIn
            if isSignedIn {
                await refreshAlbums()
            }
        }
    }

    private func signIn() async {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else { return }
        do {
            _ = try await AdobeAuthManager.shared.signIn(from: window)
            let settings = AppSettings.current(in: modelContext)
            await AdobeAuthManager.shared.saveTokens(to: settings)
            try? modelContext.save()
            isSignedIn = true
            await refreshAlbums()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        await AdobeAuthManager.shared.signOut()
        let settings = AppSettings.current(in: modelContext)
        settings.adobeAccessToken = nil
        settings.adobeRefreshToken = nil
        settings.adobeTokenExpiry = nil
        settings.lightroomEnabled = false

        for album in lightroomAlbums {
            modelContext.delete(album)
        }

        isSignedIn = false
    }

    private func refreshAlbums() async {
        isLoading = true
        errorMessage = nil

        do {
            let infos = try await LightroomConnector.shared.fetchAlbums()
            let fetchedIDs = Set(infos.map(\.id))

            for album in lightroomAlbums where !fetchedIDs.contains(album.id) {
                modelContext.delete(album)
            }

            for info in infos {
                if let existing = lightroomAlbums.first(where: { $0.id == info.id }) {
                    existing.name = info.name
                } else {
                    let album = Album(id: info.id, name: info.name, sourceType: .lightroomCloud)
                    modelContext.insert(album)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
