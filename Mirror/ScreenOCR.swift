import Foundation
import Vision
import AppKit

class ScreenOCR {
    static let shared = ScreenOCR()

    struct OCRResult {
        let frameIndex: Int
        let timestamp: Double
        let text: String
        let confidence: Double
    }

    func extractText(from sessionDir: URL, frameCount: Int) -> [OCRResult] {
        var results: [OCRResult] = []

        let metadataFile = sessionDir.appendingPathComponent("metadata.json")
        guard let metaData = try? Data(contentsOf: metadataFile),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let startTime = meta["startTime"] as? Double else {
            return results
        }

        for i in 0..<frameCount {
            let filename = "frame_\(String(format: "%04d", i)).png"
            let framePath = sessionDir.appendingPathComponent("frames/\(filename)")

            guard FileManager.default.fileExists(atPath: framePath.path) else { continue }

            if let ocr = performOCR(on: framePath) {
                let timestamp = startTime + Double(i)
                results.append(OCRResult(
                    frameIndex: i,
                    timestamp: timestamp,
                    text: ocr.text,
                    confidence: ocr.confidence
                ))
            }
        }

        return results
    }

    func extractTextFromSingleFrame(_ framePath: URL) -> (text: String, confidence: Double)? {
        return performOCR(on: framePath)
    }

    private func performOCR(on imageURL: URL) -> (text: String, confidence: Double)? {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let request = VNRecognizeTextRequest { request, error in
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else {
            return nil
        }

        var texts: [String] = []
        var totalConfidence: Float = 0

        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                texts.append(candidate.string)
                totalConfidence += candidate.confidence
            }
        }

        let avgConfidence = observations.isEmpty ? 0 : Double(totalConfidence / Float(observations.count))

        return (text: texts.joined(separator: "\n"), confidence: avgConfidence)
    }
}