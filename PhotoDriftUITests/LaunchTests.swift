import XCTest

/// PhotoDrift is an `LSUIElement` agent: no dock icon, no windows at launch, nothing for
/// XCUITest to tap. The one thing worth asserting at this level is that the app actually
/// comes up and stays up — the launch path builds a SwiftData container (which traps on
/// failure), installs the status item, and restores Keychain tokens.
final class LaunchTests: XCTestCase {

    @MainActor
    func testAppLaunchesAndStaysRunning() {
        let app = XCUIApplication()
        // An instance left behind by a previous run makes launch() racy, which is the
        // usual source of intermittent failures in tests like this one.
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning, "app did not reach a running state")

        // The launch path is asynchronous — a trap in the SwiftData or token-restore work
        // surfaces shortly after launch rather than during it, so hold the invariant for a
        // window instead of sampling once.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            XCTAssertNotEqual(app.state, .notRunning, "app terminated shortly after launching")
            usleep(100_000)
        }

        app.terminate()
    }
}
