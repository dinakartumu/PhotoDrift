import Testing
import AppKit
@testable import PhotoDrift

/// `statusItemImage()` builds AppKit objects and stays main-actor isolated, so these tests
/// run there rather than loosening the production isolation to suit the test.
@MainActor
struct StatusItemTests {
    @Test func statusItemImageIsATemplateSoAppKitCanTintIt() throws {
        let image = try #require(AppDelegate.statusItemImage())
        // Template mode is what lets AppKit invert the glyph for light/dark menu bars
        // and for the highlighted state when the menu is open.
        #expect(image.isTemplate)
    }

    @Test func statusItemImageSitsAtMenuBarHeight() throws {
        // rectangle.stack is intrinsically 22pt tall, which crowds the bar.
        let image = try #require(AppDelegate.statusItemImage())
        #expect(image.size.height == 16)
    }

    @Test func statusItemImageKeepsItsAspectRatio() throws {
        let image = try #require(AppDelegate.statusItemImage())
        let intrinsic = try #require(
            NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: nil)
        )
        let expected = (16 * intrinsic.size.width / intrinsic.size.height).rounded()
        #expect(image.size.width == expected)
    }
}
