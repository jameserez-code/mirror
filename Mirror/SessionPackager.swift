import Foundation

class SessionPackager {
    static let shared = SessionPackager()

    func package(sessionDir: URL, sessionId: String) {
        let zipURL = sessionDir.deletingLastPathComponent()
            .appendingPathComponent("\(sessionId).mirrorpack")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = [
            "-r",
            "-j",
            zipURL.path,
            sessionDir.path
        ]
        process.currentDirectoryURL = sessionDir.deletingLastPathComponent()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Mirrorpack packaging failed: \(error)")
        }
    }

    func loadEvents(from sessionDir: URL) -> [EventTapManager.CapturedEvent]? {
        let eventFile = sessionDir.appendingPathComponent("events.json")
        guard let data = try? Data(contentsOf: eventFile) else { return nil }
        return try? JSONDecoder().decode([EventTapManager.CapturedEvent].self, from: data)
    }

    func loadMetadata(from sessionDir: URL) -> [String: Any]? {
        let metaFile = sessionDir.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - OCR Context

    func loadOCRContext(from sessionDir: URL) -> String {
        let framesDir = sessionDir.appendingPathComponent("frames")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil),
              !contents.isEmpty else {
            return ""
        }

        let sortedFrames = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let sampleStride = max(1, sortedFrames.count / 20)
        var contextParts: [String] = []

        for i in stride(from: 0, to: sortedFrames.count, by: sampleStride) {
            let framePath = sortedFrames[i]
            if let result = ScreenOCR.shared.extractTextFromSingleFrame(framePath) {
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let frameName = framePath.lastPathComponent
                    contextParts.append("[\(frameName) OCR]:\n\(text.prefix(1500))")
                }
            }
        }

        return contextParts.joined(separator: "\n\n")
    }

    // MARK: - Activity Timeline

    func buildActivityTimeline(events: [EventTapManager.CapturedEvent]) -> String {
        var timeline: [String] = []
        var currentApp: String? = nil
        var keySequence: [String] = []
        var lastClickApp: String? = nil
        var lastClickPos: String? = nil
        var clickSequenceCount: Int = 0

        func flushKeys() {
            if !keySequence.isEmpty {
                let joined = keySequence.joined()
                if joined.count > 80 {
                    timeline.append("  typed: \"\(joined.prefix(80))...\"")
                } else {
                    timeline.append("  typed: \"\(joined)\"")
                }
                keySequence = []
            }
        }

        for event in events {
            if event.targetApp != currentApp {
                flushKeys()
                currentApp = event.targetApp
                clickSequenceCount = 0
                timeline.append("\n[\(formatTime(event.timestamp))] APP: \(currentApp ?? "Unknown")")
            }

            switch event.type {
            case "keyDown":
                let redacted = event.redacted == true
                let char = redacted ? "•" : (event.characters ?? "?")
                keySequence.append(char)

            case "keyUp":
                break

            case "mouseDown":
                flushKeys()
                let pos = "(\(formatCoord(event.position?["x"] ?? 0)), \(formatCoord(event.position?["y"] ?? 0)))"
                let urlInfo = event.targetURL != nil ? " url:\(event.targetURL!)" : ""

                if lastClickApp == event.targetApp && lastClickPos == pos && clickSequenceCount > 0 {
                    clickSequenceCount += 1
                } else {
                    if clickSequenceCount > 0 {
                        timeline[timeline.count - 1] = timeline[timeline.count - 1].replacingOccurrences(of: "click at", with: "\(clickSequenceCount + 1)x click at")
                    }
                    clickSequenceCount = 0
                    timeline.append("  click at \(pos)\(urlInfo)")
                }
                lastClickApp = event.targetApp
                lastClickPos = pos

            case "rightMouseDown":
                flushKeys()
                timeline.append("  right-click at (\(formatCoord(event.position?["x"] ?? 0)), \(formatCoord(event.position?["y"] ?? 0)))")

            case "clipboardChange":
                flushKeys()
                let snippet = (event.clipboardSnapshot ?? "").prefix(150)
                timeline.append("  clipboard: \"\(snippet)\"")

            case "scrollWheel":
                break

            case "flagsChanged":
                if let mods = event.modifiers, !mods.isEmpty {
                    keySequence.append("[\(mods.joined(separator: "+"))]")
                }

            default:
                break
            }
        }

        flushKeys()
        return timeline.joined(separator: "\n")
    }

    // MARK: - Rich Timeline (with OCR)

    func buildRichActivityTimeline(events: [EventTapManager.CapturedEvent], sessionDir: URL) -> String {
        let eventTimeline = buildActivityTimeline(events: events)
        let ocrContext = loadOCRContext(from: sessionDir)

        var parts: [String] = []
        parts.append("=== EVENT TIMELINE ===")
        parts.append(eventTimeline)

        if !ocrContext.isEmpty {
            parts.append("\n=== SCREEN CONTEXT (OCR) ===")
            parts.append(ocrContext)
        }

        parts.append("\n=== METADATA ===")
        if let metadata = loadMetadata(from: sessionDir) {
            if let name = metadata["sessionName"] as? String { parts.append("Session: \(name)") }
            if let dur = metadata["duration"] as? Double { parts.append("Duration: \(String(format: "%.1f", dur))s") }
            if let count = metadata["eventCount"] as? Int { parts.append("Events: \(count)") }
        }

        return parts.joined(separator: "\n")
    }

    private func formatTime(_ t: Double) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatCoord(_ v: Double) -> String {
        return String(format: "%.0f", v)
    }
}