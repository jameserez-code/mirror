import Foundation
import AppKit

// MARK: - Vision Frame Analyzer

/// Sends frames to GPT-4.1 nano (vision-capable) to get text descriptions.
/// Then the descriptions are fed to the main analysis model (Haiku).
struct VisionFrameAnalyzer {

    private static let visionModel = "gpt-4.1-nano"
    private static let maxFrames = 120
    private static let framesPerBatch = 10  // batch frames to reduce API calls

    // MARK: - Batch Analyze Frames

    /// Analyze all frames in a session directory using vision model.
    /// Returns concatenated frame descriptions for the main analysis prompt.
    /// Limits to maxFrames frames, evenly sampled.
    static func analyzeFrames(sessionDir: URL, progress: ((Int, Int) -> Void)? = nil) async -> String {
        let framesDir = sessionDir.appendingPathComponent("frames")
        guard FileManager.default.fileExists(atPath: framesDir.path) else {
            return ""
        }

        let allFrames = (try? FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)) ?? []
        let pngFrames = allFrames.filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !pngFrames.isEmpty else { return "" }

        // Evenly sample up to maxFrames
        let sampleStep = max(1, pngFrames.count / maxFrames)
        let sampled = Swift.stride(from: 0, to: pngFrames.count, by: sampleStep).prefix(maxFrames).map { pngFrames[$0] }

        var allDescriptions: [String] = []

        for batchStart in Swift.stride(from: 0, to: sampled.count, by: framesPerBatch) {
            let batchEnd = min(batchStart + framesPerBatch, sampled.count)
            let batch = Array(sampled[batchStart..<batchEnd])

            progress?(batchStart, sampled.count)

            for frame in batch {
                guard let imageData = try? Data(contentsOf: frame) else { continue }
                let base64 = imageData.base64EncodedString()
                if let description = await describeFrame(base64: base64, filename: frame.lastPathComponent) {
                    allDescriptions.append(description)
                }
            }

            // Small delay between batches to respect rate limits
            if batchEnd < sampled.count {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }

        progress?(sampled.count, sampled.count)
        return allDescriptions.joined(separator: "\n")
    }

    // MARK: - Describe Single Frame

    private static func describeFrame(base64: String, filename: String) async -> String? {
        guard let apiKey = CredentialStore.shared.getAPIKey(provider: "openrouter") else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://mirror.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Mirror", forHTTPHeaderField: "X-Title")

        let prompt = """
        Describe this screenshot in detail. Focus on:
        1. What application or website is visible? (check window titles, URL bars, app chrome)
        2. What is the user doing? (typing, clicking, reading, copying, pasting)
        3. What data is visible? (text content, numbers, table headers, form fields, buttons)
        4. What UI elements are present? (search boxes, compose windows, spreadsheets, dialogs)
        5. Any visible file names, email subjects, spreadsheet names, or account names?

        Be specific and concise. This is for workflow automation analysis.
        """

        let body: [String: Any] = [
            "model": visionModel,
            "max_tokens": 300,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64)"]]
                ]]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let text = message["content"] as? String else {
                return nil
            }
            return "[\(filename)]: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            print("[VisionAnalyzer] Frame \(filename) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
