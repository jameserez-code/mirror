import Foundation
import ScreenCaptureKit

class CaptureManager {
    static let shared = CaptureManager()

    private let screenRecorder = ScreenRecorder()
    private let eventTapManager = EventTapManager()
    private var sessionId: String = ""
    private var sessionName: String = ""
    private var startTime: Date = Date()
    private var isCapturing: Bool = false
    private var sessionDir: URL = URL(fileURLWithPath: "")

    var onEventCountUpdate: ((Int) -> Void)?
    var onCaptureComplete: ((String) -> Void)?

    func startCapture(sessionName: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard !isCapturing else {
            completion(false, "Already recording")
            return
        }

        guard eventTapManager.checkPermissions() else {
            completion(false, "Accessibility permission not granted")
            return
        }

        sessionId = UUID().uuidString
        self.sessionName = sessionName ?? "Untitled Recording"
        startTime = Date()

        // Create session directory
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Mirror/Sessions")
            .appendingPathComponent(sessionId)
        sessionDir = baseDir

        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        } catch {
            completion(false, "Failed to create session directory: \(error.localizedDescription)")
            return
        }

        guard eventTapManager.startCapture() else {
            completion(false, "Failed to start event tap")
            return
        }

        Task {
            do {
                try await screenRecorder.startCapture(sessionDirectory: sessionDir)
                isCapturing = true
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                // Screen capture failed but event tap is still running
                DispatchQueue.main.async {
                    completion(true, "Screen recording unavailable; events only")
                }
                isCapturing = true
            }
        }
    }

    func stopCapture(completion: @escaping (String) -> Void) {
        guard isCapturing else { return }
        isCapturing = false

        let events = eventTapManager.stopCapture()

        Task {
            do {
                try await screenRecorder.stopCapture()
            } catch {
                // Screen recording cleanup error is non-fatal
            }

            await MainActor.run {
                self.packageSession(events: events, sessionId: self.sessionId)
                completion(self.sessionId)
            }
        }
    }

    func isCurrentlyCapturing() -> Bool {
        return isCapturing
    }

    func getEventCount() -> Int {
        return eventTapManager.eventCount()
    }

    func pollClipboard() -> String? {
        return eventTapManager.checkClipboard()
    }

    // MARK: - Session Packaging

    private func packageSession(events: [EventTapManager.CapturedEvent], sessionId: String) {
        // Write events.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let eventData = try? encoder.encode(events) {
            let eventFile = sessionDir.appendingPathComponent("events.json")
            try? eventData.write(to: eventFile)
        }

        // Write metadata.json
        let metadata: [String: Any] = [
            "sessionId": sessionId,
            "sessionName": sessionName,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970,
            "duration": Date().timeIntervalSince(startTime),
            "eventCount": events.count,
            "version": "1.0",
        ]
        if let metaData = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
            let metaFile = sessionDir.appendingPathComponent("metadata.json")
            try? metaData.write(to: metaFile)
        }

        // Create mirrorpack bundle
        SessionPackager.shared.package(sessionDir: sessionDir, sessionId: sessionId)
    }
}
