import RealityKit
import ARKit
import AVFoundation
import Metal

private enum RecordingState: CaseIterable {
    case idle
    case start
    case capturing
    case end
}

public class RealityView: ARView {
    public var arView: ARView { return self }
    public var audioMode: AVAudioSession.Category = .playAndRecord
    public var audioOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]
    
    private var recordingStartTime = TimeInterval(0)
    private var writer: AVAssetWriter!
    private var input: AVAssetWriterInput!
    private var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    private var captureState: RecordingState = .idle
    private var filename: String = ""
    
    private var textureCache: CVMetalTextureCache?
    let metalDevice = MTLCreateSystemDefaultDevice()
    
    public func startRecording(outputURL: URL) {
        setupAudioSession()
        enableBuiltInMic()
        setupMetalStuff()
        captureState = .start
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
    
    private func setupMetalStuff() {
        guard let
                metalDevice = metalDevice, CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache) == kCVReturnSuccess
        else {
            return
        }
    }
    
    private func setupAssetWriter(width: Int, height: Int) {
        filename = UUID().uuidString
        let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(filename).mov")
        writer = try! AVAssetWriter(outputURL: videoPath, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080]
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = CMTimeScale(bitPattern: 600)
        input.expectsMediaDataInRealTime = true
        //input.transform = CGAffineTransform(rotationAngle: .pi/2)
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
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
        guard let availableInputs = session.availableInputs,
              let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) else {
                  print("The device must have a built-in microphone.")
                  return
              }
        
        // Make the built-in microphone input the preferred input.
        do {
            try session.setPreferredInput(builtInMicInput)
        } catch {
            print("Unable to set the built-in mic as the preferred input.")
        }
    }
    
    
}

extension RealityView: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        switch captureState {
        case .start:
            setupAssetWriter(width: width, height: height)
            captureState = .capturing
        case .idle:
            break
        case .capturing:
            guard let texture = transformFrames(pixelBuffer: pixelBuffer, width: width, height: height) else {
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
    
    func writeFrame(forTexture texture: MTLTexture) {
        
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
        
        guard let pixelBuffer = maybePixelBuffer else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer)!
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        
        texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let frameTime = CACurrentMediaTime() - recordingStartTime
        let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale: 240)
        assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: presentationTime)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
}
