@preconcurrency import Photos
@preconcurrency import Combine

final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    let changes = PassthroughSubject<Void, Never>()

    private(set) lazy var debouncedChanges: AnyPublisher<Void, Never> = {
        changes
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }()

    func startObserving() {
        PHPhotoLibrary.shared().register(self)
    }

    func stopObserving() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        changes.send()
    }
}
