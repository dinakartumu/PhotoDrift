@preconcurrency import Photos
@preconcurrency import Combine

/// PhotoKit delivers `photoLibraryDidChange` on an arbitrary queue, so this observer cannot
/// be main-actor isolated. Nothing here needs to be: the subject is thread-safe to send on,
/// and `debouncedChanges` already hops to the main queue for delivery.
nonisolated final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
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
