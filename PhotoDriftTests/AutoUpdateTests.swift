import Testing
import Foundation
import Security
@testable import PhotoDrift

/// The unit tests run inside PhotoDrift.app, so `Bundle.main` and the current task's
/// entitlements are the app's own. These pin down what Sparkle needs to work in the
/// sandbox and what the design promised users about update behaviour.
struct AutoUpdateTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func feedURLPointsAtTheAppcastOnMain() throws {
        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(feed == "https://raw.githubusercontent.com/dinakartumu/PhotoDrift/main/appcast.xml")
    }

    @Test func publicEdDSAKeyIsA32ByteBase64String() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        let bytes = try #require(Data(base64Encoded: key))
        #expect(bytes.count == 32)
    }

    @Test func installerLauncherServiceIsEnabledForTheSandbox() {
        // Without this Sparkle cannot install outside the app's sandbox.
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
    }

    @Test func automaticChecksAreOnSoAWindowlessAgentShowsNoPermissionPrompt() {
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    }

    @Test func updatesAreNeverInstalledSilently() {
        let silent = info["SUAutomaticallyUpdate"] as? Bool ?? false
        #expect(silent == false)
    }

    // MARK: - Gentle reminders

    // Since Sparkle 2.2 a scheduled update alert will not steal focus, so on a menu bar app
    // it can sit unnoticed behind other windows. The app holds such alerts back and offers
    // the update from the status menu instead; choosing it runs a user-initiated check,
    // which Sparkle does show in focus.

    @Test func aScheduledAlertIsLeftToSparkleOnlyWhenItWouldBeInFocus() {
        #expect(AppDelegate.sparkleShouldShowScheduledUpdate(inImmediateFocus: true))
        #expect(!AppDelegate.sparkleShouldShowScheduledUpdate(inImmediateFocus: false))
    }

    @Test func theMenuOffersTheHeldBackUpdateByVersion() {
        #expect(AppDelegate.updateMenuTitle(forVersion: "1.3") == "Update to PhotoDrift 1.3...")
    }

    @Test func sandboxAllowsSparkleXPCServices() throws {
        let task = try #require(SecTaskCreateFromSelf(nil))
        let key = "com.apple.security.temporary-exception.mach-lookup.global-name" as CFString
        let names = try #require(SecTaskCopyValueForEntitlement(task, key, nil) as? [String])
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(names.contains("\(bundleID)-spks"))
        #expect(names.contains("\(bundleID)-spki"))
    }
}
