import Testing
import AppKit
@testable import PhotoDrift

/// The About panel is Apple's standard one; the app only supplies the credits block, so
/// that is what gets pinned down: the links a user would want from an About page.
struct AboutPanelTests {
    private var links: [URL] {
        let credits = AppDelegate.aboutCredits()
        var found: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { found.append(url) }
        }
        return found
    }

    @Test func creditsLinkToTheProductPage() {
        #expect(links.contains(URL(string: "https://dinakartumu.com/photodrift")!))
    }

    @Test func creditsLinkToTheSourceOnGitHub() {
        #expect(links.contains(URL(string: "https://github.com/dinakartumu/PhotoDrift")!))
    }

    @Test func creditsAcknowledgeSparkle() {
        #expect(links.contains(URL(string: "https://sparkle-project.org")!))
    }

    @Test func creditsAreShortEnoughForThePanel() {
        // The standard panel gives credits a small scroll view; a few lines is the limit
        // before it stops reading as an About page.
        #expect(AppDelegate.aboutCredits().string.count < 200)
    }
}
