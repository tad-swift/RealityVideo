import RealityKit
import ARKit
import AVFoundation
import Metal

public enum RecordingState: String, CaseIterable {
    case idle
    case start
    case capturing
    case end
}

public class RealityView: ARView {
    public var arView: ARView { return self }
    public var audioMode: AVAudioSession.Category = .record
    public var audioOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    
    private(set) var captureState: RecordingState = .idle
    
    private var recordingStartTime = TimeInterval(0)
    private var writer: AVAssetWriter!
    private var input: AVAssetWriterInput!
    private var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    private var filename: String = ""
    private var assetWriterWidth: Int!
    private var assetWriterHeight: Int!
    private var frameCount = 0
    private var outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, conformingTo: .quickTimeMovie)
    
    private var textureCache: CVMetalTextureCache?
    let metalDevice = MTLCreateSystemDefaultDevice()
    
    public required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        setupAudioSession()
        enableBuiltInMic()
        setupMetal()
        self.session.delegate = self
    }
    
    @MainActor required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func startRecording() {
        captureState = .start
        setupAssetWriter(width: assetWriterWidth, height: assetWriterHeight)
        captureState = .capturing
    }
    
    public func endRecording(_ completion: (() -> Void)? = nil) {
        captureState = .end
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            self.writer = nil
            self.input = nil
            completion?()
        }
    }
    
    private func setupMetal() {
        guard let
                metalDevice = metalDevice, CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache) == kCVReturnSuccess
        else {
            print("setup metal failed")
            return
        }
    }
    
    private func setupAssetWriter(width: Int, height: Int) {
        writer = try! AVAssetWriter(outputURL: outputURL, fileType: .mov)
        print(writer.status.rawValue)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: assetWriterWidth as! Int,
            AVVideoHeightKey: assetWriterHeight as! Int,
            AVVideoCompressionPropertiesKey: [
                //                "AllowFrameReordering": 1,
                "AverageBitRate": 1000000,
                "ExpectedFrameRate": 60,
                //                "Priority": 80,
                "ProfileLevel": AVVideoProfileLevelH264MainAutoLevel,
                //                "RealTime": 1
            ]
        ]
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        //        input.mediaTimeScale = CMTimeScale(bitPattern: 600)
        input.expectsMediaDataInRealTime = true
        //        input.transform = CGAffineTransform(rotationAngle: .pi/2)
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        print(writer.status.rawValue)
        if assetWriterPixelBufferInput.pixelBufferPool == nil {
            print("pool is nil")
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(audioMode, options: audioOptions)
            try session.setActive(true)
        } catch {
            fatalError("Failed to configure and activate session.")
        }
    }
    
    private func enableBuiltInMic() {
        // Get the shared audio session.
        let session = AVAudioSession.sharedInstance()
        
        // Find the built-in microphone input.
        guard let availableInputs = session.availableInputs else {
            print("The device must have a built-in microphone.")
            return
        }
        if let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) {
            // Make the built-in microphone input the preferred input.
            do {
                try session.setPreferredInput(builtInMicInput)
            } catch {
                // use the first available input
                try? session.setPreferredInput(availableInputs.first!)
            }
        }
    }
    
}

extension RealityView: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        let pixelBuffer = frame.capturedImage
        assetWriterWidth = CVPixelBufferGetWidth(pixelBuffer)
        assetWriterHeight = CVPixelBufferGetHeight(pixelBuffer)
        if writer != nil {
            print(writer.status.rawValue)
        }
        switch captureState {
        case .start:
            break
        case .idle:
            break
        case .capturing:
            guard let texture = transformFrames(pixelBuffer: pixelBuffer, width: assetWriterWidth, height: assetWriterHeight) else {
                return
            }
            writeFrame(forTexture: texture)
        case .end:
            break
        }
    }
    
}

// MARK: Metal Stuff
extension RealityView {
    private func transformFrames(pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MTLTexture? {
        let format: MTLPixelFormat = .bgra8Unorm
        var textureRef: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pixelBuffer, nil, format, width, height, 0, &textureRef)
        guard
            let unwrappedImageTexture = textureRef,
            let texture = CVMetalTextureGetTexture(unwrappedImageTexture),
            result == kCVReturnSuccess
        else {
            return nil
        }
        return texture
    }
    
    private func writeFrame(forTexture texture: MTLTexture) {
        
        while !input.isReadyForMoreMediaData {}
        
        guard let pixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool else {
            print("Pixel buffer asset writer input did not have a pixel buffer pool available; cannot retrieve frame")
            return
        }
        
        var maybePixelBuffer: CVPixelBuffer? = nil
        let status  = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &maybePixelBuffer)
        if status != kCVReturnSuccess {
            print("Could not get pixel buffer from asset writer input; dropping frame...")
            return
        }
        
        guard let pixelBuffer = maybePixelBuffer else {
            print("pixelBuffer is nil")
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer)!
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        
        texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let frameTime = CACurrentMediaTime() - recordingStartTime
        let presentationTime = CMTime(seconds: Double(frameCount), preferredTimescale: 60)
        
        assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: presentationTime)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        print("frame complete")
    }
}
