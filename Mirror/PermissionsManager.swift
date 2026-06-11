import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

class PermissionsManager {

    func hasAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasScreenRecordingPermission() -> Bool {
        // ScreenCaptureKit doesn't expose a direct permission check API.
        // We detect it indirectly: try to access display list.
        // If permission is denied, SCShareableContent.current throws or returns empty.
        let semaphore = DispatchSemaphore(value: 0)
        var hasAccess = false
        Task {
            do {
                let content = try await SCShareableContent.current
                hasAccess = !content.displays.isEmpty
            } catch {
                hasAccess = false
            }
            semaphore.signal()
        }

        switch semaphore.wait(timeout: .now() + 1.0) {
        case .success:
            return hasAccess
        case .timedOut:
            return false
        }
    }

    func openAccessibilitySettings() {
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(prefPaneURL)
    }

    func openScreenRecordingSettings() {
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(prefPaneURL)
    }

    func openFullDiskAccessSettings() {
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(prefPaneURL)
    }
}
