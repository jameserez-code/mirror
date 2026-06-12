import Foundation
import ScreenCaptureKit
import CoreGraphics
import AVFoundation

class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var sessionDir: URL?
    private var frameCount: Int = 0
    private var isRecording: Bool = false
    private let frameInterval: TimeInterval = 1.0
    private var lastFrameTime: TimeInterval = 0
    private let processingQueue = DispatchQueue(label: "com.mirror.screenrecorder.processing", qos: .utility)

    struct ScreenFrame: Codable {
        let index: Int
        let timestamp: Double
        let filename: String
    }

    func startCapture(sessionDirectory: URL) async throws {
        sessionDir = sessionDirectory
        frameCount = 0
        lastFrameTime = 0

        let framesDir = sessionDirectory.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw RecorderError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: processingQueue)
        try await stream?.startCapture()
        isRecording = true
    }

    func stopCapture() async throws {
        guard isRecording else { return }
        isRecording = false
        try await stream?.stopCapture()
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, isRecording else { return }

        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= frameInterval else { return }
        lastFrameTime = now

        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let bitmapImage = NSBitmapImageRep(cgImage: cgImage)
        bitmapImage.size = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
        guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return }

        let filename = "frame_\(String(format: "%04d", frameCount)).png"
        let fileURL = sessionDir?.appendingPathComponent("frames").appendingPathComponent(filename)
        try? pngData.write(to: fileURL!)

        frameCount += 1
    }

    enum RecorderError: Error {
        case noDisplayAvailable
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Mirror] Screen recording stream stopped with error: \(error.localizedDescription)")
        isRecording = false
    }
}
