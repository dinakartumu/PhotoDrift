import AppKit

enum ScreenUtility {
    static var targetSize: CGSize {
        guard let screen = NSScreen.main else {
            return CGSize(width: 2560, height: 1600)
        }
        let scale = screen.backingScaleFactor
        let frame = screen.frame
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}
