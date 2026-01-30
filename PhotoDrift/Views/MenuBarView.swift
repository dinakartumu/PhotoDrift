import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Album> { $0.isSelected == true })
    private var selectedAlbums: [Album]
    var shuffleEngine: ShuffleEngine?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PhotoDrift")
                    .font(.headline)
                Spacer()
                if let engine = shuffleEngine, engine.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }

            if let engine = shuffleEngine {
                Divider()

                if let source = engine.currentSource {
                    Label("Source: \(source)", systemImage: source == "Photos" ? "photo" : "cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let next = engine.nextShuffleDate, engine.isRunning {
                    Label {
                        Text("Next: \(next, style: .relative)")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let status = engine.statusMessage {
                    Label(status, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            if selectedAlbums.isEmpty {
                Label("No albums selected", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let photosCount = selectedAlbums.filter { $0.sourceType == .applePhotos }.count
                let lrCount = selectedAlbums.filter { $0.sourceType == .lightroomCloud }.count
                let parts = [
                    photosCount > 0 ? "\(photosCount) Photos" : nil,
                    lrCount > 0 ? "\(lrCount) Lightroom" : nil,
                ].compactMap { $0 }
                Label(parts.joined(separator: ", "), systemImage: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Shuffle Now") {
                guard let engine = shuffleEngine else { return }
                Task { await engine.shuffleNow() }
            }
            .disabled(selectedAlbums.isEmpty)

            if let engine = shuffleEngine {
                if engine.isRunning {
                    Button("Pause") { engine.stop() }
                } else if !selectedAlbums.isEmpty {
                    Button("Resume") { engine.start() }
                }
            }

            Divider()

            Button("Choose Albums...") {
                openWindow(id: "album-picker")
            }

            Button("Settings...") {
                openWindow(id: "settings")
            }

            #if DEBUG
            Button("Set Test Wallpaper") {
                Task { await setTestWallpaper() }
            }
            #endif

            Divider()

            Button("Quit PhotoDrift") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
    }

    #if DEBUG
    private func setTestWallpaper() async {
        do {
            let size = ScreenUtility.targetSize
            let image = NSImage(size: NSSize(width: size.width, height: size.height))
            image.lockFocus()
            NSColor.systemTeal.setFill()
            NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
            let text = "PhotoDrift Test" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(
                    x: (image.size.width - textSize.width) / 2,
                    y: (image.size.height - textSize.height) / 2
                ),
                withAttributes: attrs
            )
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            else { return }

            let url = try await ImageCacheManager.shared.store(data: jpegData, forKey: "test_wallpaper.jpg")
            try WallpaperService.setWallpaper(from: url)
        } catch {
            // Debug only
        }
    }
    #endif
}

struct AlbumPickerWindow: View {
    var body: some View {
        ScrollView {
            AlbumPickerView()
                .padding()
        }
        .frame(width: 360, height: 420)
        .navigationTitle("Choose Albums")
    }
}
