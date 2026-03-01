import AVFoundation
import RealityKit
import ReplayKit
import UIKit

public enum RealityVideoError: Error, Sendable {
    case alreadyRecording
    case notRecording
    case writerFailed(String)
    case snapshotFailed
    case replayKitFailed(Error)
}

public enum CaptureMethod: Sendable {
    case snapshot
    case replayKit
}

public struct Settings: Sendable {
    public var frameRate: Int
    public var videoBitrate: Int
    public var codec: AVVideoCodecType
    public var captureMethod: CaptureMethod
    
    public init(
        frameRate: Int = 30,
        videoBitrate: Int = 10_000_000,
        codec: AVVideoCodecType = .hevc,
        captureMethod: CaptureMethod = .snapshot
    ) {
        self.frameRate = frameRate
        self.videoBitrate = videoBitrate
        self.codec = codec
        self.captureMethod = captureMethod
    }
    
    public static let `default` = Settings()
}

@MainActor
public final class RealityVideoRecorder {
    
    private weak var arView: ARView?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var outputURL: URL?
    private var currentSettings: Settings = .default
    
    public private(set) var isRecording: Bool = false
    
    public init(arView: ARView) {
        self.arView = arView
    }
    
    public func startRecording(to url: URL? = nil, settings: Settings = .default) async throws {
        guard !isRecording else {
            throw RealityVideoError.alreadyRecording
        }
        
        guard let arView else {
            throw RealityVideoError.writerFailed("ARView is no longer available")
        }
        
        currentSettings = settings
        
        let fileURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        outputURL = fileURL
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        
        let width = Int(arView.bounds.width * arView.contentScaleFactor)
        let height = Int(arView.bounds.height * arView.contentScaleFactor)
        
        try setupWriter(url: fileURL, width: width, height: height, settings: settings)
        
        isRecording = true
        
        switch settings.captureMethod {
        case .snapshot:
            startSnapshotCapture()
        case .replayKit:
            try await startReplayKitCapture()
        }
    }
    
    public func stopRecording() async throws -> URL {
        guard isRecording else {
            throw RealityVideoError.notRecording
        }
        
        switch currentSettings.captureMethod {
        case .snapshot:
            stopSnapshotCapture()
        case .replayKit:
            await stopReplayKitCapture()
        }
        
        guard let videoWriterInput, let videoWriter, let outputURL else {
            throw RealityVideoError.writerFailed("Writer not configured")
        }
        
        videoWriterInput.markAsFinished()
        
        await withCheckedContinuation { continuation in
            videoWriter.finishWriting {
                continuation.resume()
            }
        }
        
        isRecording = false
        
        if videoWriter.status == .failed {
            throw RealityVideoError.writerFailed(videoWriter.error?.localizedDescription ?? "Unknown error")
        }
        
        self.videoWriter = nil
        self.videoWriterInput = nil
        self.pixelBufferAdaptor = nil
        
        return outputURL
    }
    
    private func setupWriter(url: URL, width: Int, height: Int, settings: Settings) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.videoBitrate,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        writer.add(input)
        
        videoWriter = writer
        videoWriterInput = input
        pixelBufferAdaptor = adaptor
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }
    
    // MARK: - Snapshot Capture
    
    private func startSnapshotCapture() {
        let displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(currentSettings.frameRate),
            maximum: Float(currentSettings.frameRate),
            preferred: Float(currentSettings.frameRate)
        )
        startTime = CACurrentMediaTime()
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }
    
    private func stopSnapshotCapture() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func captureFrame(_ displayLink: CADisplayLink) {
        guard isRecording,
              let arView,
              let videoWriterInput,
              videoWriterInput.isReadyForMoreMediaData else {
            return
        }
        
        let presentationTime = CMTime(seconds: displayLink.timestamp - startTime, preferredTimescale: 600)
        
        arView.snapshot(saveToHDR: false) { [weak self] image in
            guard let self, let image else { return }
            
            Task { @MainActor in
                self.appendImage(image, at: presentationTime)
            }
        }
    }
    
    private func appendImage(_ image: UIImage, at time: CMTime) {
        guard let pixelBufferAdaptor,
              let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool,
              videoWriterInput?.isReadyForMoreMediaData == true else {
            return
        }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        guard let cgImage = image.cgImage else { return }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        pixelBufferAdaptor.append(buffer, withPresentationTime: time)
    }
    
    // MARK: - ReplayKit Capture
    
    private func startReplayKitCapture() async throws {
        let recorder = RPScreenRecorder.shared()
        
        guard recorder.isAvailable else {
            throw RealityVideoError.writerFailed("Screen recording is not available")
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture { [weak self] sampleBuffer, sampleBufferType, error in
                guard let self else { return }
                
                if let error {
                    if self.isRecording {
                        Task { @MainActor in
                            self.isRecording = false
                        }
                    }
                    return
                }
                
                guard sampleBufferType == .video else { return }
                
                Task { @MainActor in
                    self.appendSampleBuffer(sampleBuffer)
                }
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: RealityVideoError.replayKitFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func stopReplayKitCapture() async {
        let recorder = RPScreenRecorder.shared()
        
        await withCheckedContinuation { continuation in
            recorder.stopCapture { _ in
                continuation.resume()
            }
        }
    }
    
    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let videoWriterInput,
              videoWriterInput.isReadyForMoreMediaData,
              let videoWriter,
              videoWriter.status == .writing else {
            return
        }
        
        videoWriterInput.append(sampleBuffer)
    }
}
