import Foundation
import CoreGraphics
import AppKit

class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var events: [CapturedEvent] = []
    private var startTime: Double = 0
    private var isRunning: Bool = false
    private var lastClipboardChangeCount: Int = 0

    struct CapturedEvent: Codable {
        var timestamp: Double
        var type: String
        var keyCode: Int?
        var characters: String?
        var modifiers: [String]?
        var position: [String: Double]?
        var targetApp: String?
        var targetURL: String?
        var clipboardSnapshot: String?
        var redacted: Bool?
    }

    func startCapture() -> Bool {
        guard checkPermissions() else { return false }
        guard eventTap == nil else { return true }

        events = []
        startTime = CACurrentMediaTime()
        lastClipboardChangeCount = NSPasteboard.general.changeCount

        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon!).takeUnretainedValue()
                manager.handleEvent(proxy: proxy, type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = tap else { return false }
        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stopCapture() -> [CapturedEvent] {
        guard isRunning else { return events }

        isRunning = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        return events
    }

    func eventCount() -> Int {
        return events.count
    }

    func checkClipboard() -> String? {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return nil }
        lastClipboardChangeCount = currentCount
        let text = NSPasteboard.general.string(forType: .string)
        if let text = text, !text.isEmpty {
            let now = CACurrentMediaTime()
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
            let clipEvent = CapturedEvent(
                timestamp: now - startTime,
                type: "clipboardChange",
                keyCode: nil,
                characters: nil,
                modifiers: nil,
                position: nil,
                targetApp: frontApp,
                targetURL: nil,
                clipboardSnapshot: text,
                redacted: nil
            )
            events.append(clipEvent)
        }
        return text
    }

    func checkPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        let now = CACurrentMediaTime()
        let pos = event.location

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontApp.localizedName ?? "Unknown"

        var captEv = CapturedEvent(
            timestamp: now - startTime,
            type: eventTypeString(type),
            keyCode: nil,
            characters: nil,
            modifiers: nil,
            position: ["x": pos.x, "y": pos.y],
            targetApp: appName,
            targetURL: nil,
            clipboardSnapshot: nil,
            redacted: nil
        )

        switch type {
        case .keyDown, .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            captEv.keyCode = Int(keyCode)
            captEv.modifiers = decodeModifiers(event.flags)
            captEv.characters = decodeCharacters(event)

            if isSecureFieldActive() {
                captEv.characters = "[REDACTED]"
                captEv.redacted = true
            }

        case .flagsChanged:
            captEv.keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            captEv.modifiers = decodeModifiers(event.flags)

        case .mouseMoved:
            break  // position already set

        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
            var targetURL: String? = nil
            if let safariName = appName as String?, safariName == "Google Chrome" || safariName == "Safari" || safariName == "Arc" {
                targetURL = readBrowserURL(appName: appName)
            }
            captEv.targetURL = targetURL

        case .scrollWheel:
            captEv.position = ["x": pos.x, "y": pos.y]

        default:
            break
        }

        events.append(captEv)
    }

    // MARK: - Character Decoding

    private func decodeCharacters(_ event: CGEvent) -> String? {
        let maxLen = 4
        var actualLen = 0
        var chars = [UniChar](repeating: 0, count: maxLen)
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLen, unicodeString: &chars)
        if actualLen > 0 {
            return String(utf16CodeUnits: chars, count: actualLen)
        }
        return nil
    }

    private func decodeModifiers(_ flags: CGEventFlags) -> [String] {
        var mods: [String] = []
        if flags.contains(.maskCommand) { mods.append("cmd") }
        if flags.contains(.maskShift) { mods.append("shift") }
        if flags.contains(.maskAlternate) { mods.append("option") }
        if flags.contains(.maskControl) { mods.append("ctrl") }
        if flags.contains(.maskAlphaShift) { mods.append("capsLock") }
        if flags.contains(.maskSecondaryFn) { mods.append("fn") }
        return mods
    }

    private func eventTypeString(_ type: CGEventType) -> String {
        switch type {
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .flagsChanged: return "flagsChanged"
        case .leftMouseDown: return "mouseDown"
        case .leftMouseUp: return "mouseUp"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .mouseMoved: return "mouseMoved"
        case .scrollWheel: return "scrollWheel"
        default: return "unknown"
        }
    }

    // MARK: - Secure Field Detection

    private func isSecureFieldActive() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElem: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        guard result == .success, let elem = focusedElem else { return false }

        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(elem as! AXUIElement, kAXRoleAttribute as CFString, &role)
        if roleResult == .success, let r = role as? String {
            if r == "AXSecureTextField" { return true }
        }

        var subrole: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(elem as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
        if subroleResult == .success, let s = subrole as? String {
            if s == "AXSecureTextField" { return true }
        }

        return false
    }

    private func readBrowserURL(appName: String) -> String? {
        // Read browser URL via Accessibility API
        // This is a best-effort operation for context gathering
        let runningApps = NSWorkspace.shared.runningApplications
        guard let app = runningApps.first(where: { $0.localizedName == appName }) else { return nil }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowList: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList) == .success,
              let windows = windowList as? [AXUIElement], let mainWindow = windows.first else { return nil }

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(mainWindow, kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String else { return nil }
        return title
    }
}
