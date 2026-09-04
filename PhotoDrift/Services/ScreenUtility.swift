import AppKit

/// Reads live window-server state, so it genuinely belongs to the main actor — the
/// isolation here is a real requirement, not a default inherited from the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION`. Callers off the main actor must hop.
@MainActor
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
