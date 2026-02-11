import AppKit

enum WallpaperService {
    enum Warning: LocalizedError, Equatable {
        case allDesktopsPermissionDenied
        case allDesktopsAutomationFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .allDesktopsPermissionDenied:
                return "Wallpaper updated for current desktop only. Allow PhotoDrift to control System Events in Privacy & Security > Automation."
            case .allDesktopsAutomationFailed(let message):
                return "Wallpaper updated for current desktop only. \(message)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .allDesktopsPermissionDenied:
                return "Allow PhotoDrift to control System Events in System Settings > Privacy & Security > Automation to update all desktops."
            case .allDesktopsAutomationFailed:
                return nil
            }
        }
    }

    private enum AutomationError: Error {
        case permissionDenied
        case executionFailed(String)
    }

    static func desktopImageOptions(for scaling: WallpaperScaling) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        switch scaling {
        case .fillScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ]
        case .fitToScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
            ]
        case .stretchToFill:
            return [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true,
            ]
        case .center:
            return [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        case .tile:
            return [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
            ]
        }
    }

    @discardableResult
    static func setWallpaper(
        from url: URL,
        scaling: WallpaperScaling = .fitToScreen,
        applyToAllDesktops: Bool = true
    ) throws -> Warning? {
        let options = desktopImageOptions(for: scaling)
        for screen in NSScreen.screens {
            var opts = options
            opts[.fillColor] = NSColor.black
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
        }

        guard applyToAllDesktops else { return nil }

        do {
            try applyWallpaperToAllDesktops(url: url)
            return nil
        } catch AutomationError.permissionDenied {
            return .allDesktopsPermissionDenied
        } catch AutomationError.executionFailed(let message) {
            return .allDesktopsAutomationFailed(message: message)
        }
    }

    static func allDesktopsAppleScript(for url: URL, ensureLaunched: Bool = false) -> String {
        let escapedPath = escapeForAppleScript(url.path)
        let launchPrefix = ensureLaunched ? """
            launch
            repeat 30 times
                try
                    set _desktopCount to count of desktops
                    exit repeat
                on error
                    delay 0.1
                end try
            end repeat

        """ : ""
        return """
        tell application "System Events"
        \(launchPrefix)    -- Apply to every Space/desktop in the active display set.
            repeat with desk in desktops
                set picture of desk to POSIX file "\(escapedPath)"
            end repeat
            delay 0.2
            repeat with desk in desktops
                set picture of desk to POSIX file "\(escapedPath)"
            end repeat
        end tell
        """
    }

    static func escapeForAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func applyWallpaperToAllDesktops(url: URL) throws {
        let script = allDesktopsAppleScript(for: url, ensureLaunched: true)
        let deadline = Date().addingTimeInterval(8)
        var lastRetryError: AutomationError?

        while Date() < deadline {
            do {
                try executeAppleScript(script)
                return
            } catch let retryError as AutomationError {
                if case .permissionDenied = retryError { throw retryError }
                lastRetryError = retryError
                if shouldRetryAfterLaunchingSystemEvents(retryError) {
                    Thread.sleep(forTimeInterval: 0.2)
                    continue
                }
                throw retryError
            }
        }

        throw lastRetryError ?? .executionFailed("Timed out while updating all desktops.")
    }

    private static func executeAppleScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw AutomationError.executionFailed("Failed to compile AppleScript.")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw mapAppleScriptError(errorInfo)
        }
    }

    private static func mapAppleScriptError(_ errorInfo: NSDictionary) -> AutomationError {
        let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
        let errorMessage = (errorInfo[NSAppleScript.errorMessage] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if errorNumber == -1743 {
            return .permissionDenied
        }

        if let errorMessage,
           errorMessage.localizedCaseInsensitiveContains("not authorized")
            || errorMessage.localizedCaseInsensitiveContains("not permitted") {
            return .permissionDenied
        }

        if let errorMessage, !errorMessage.isEmpty {
            return .executionFailed(errorMessage)
        }

        if let errorNumber {
            return .executionFailed("AppleScript failed with error \(errorNumber).")
        }

        return .executionFailed("AppleScript failed with an unknown error.")
    }

    private static func shouldRetryAfterLaunchingSystemEvents(_ error: AutomationError) -> Bool {
        guard case .executionFailed(let message) = error else { return false }
        return message.localizedCaseInsensitiveContains("application isn’t running")
            || message.localizedCaseInsensitiveContains("application isn't running")
            || message.localizedCaseInsensitiveContains("not running")
    }
}
