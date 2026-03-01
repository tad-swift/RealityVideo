# RealityVideo

A Swift package for recording RealityKit AR experiences to video.

## Requirements

- iOS 26+
- Swift 6.0+

## Installation

Add RealityVideo to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/tad-swift/RealityVideo.git", from: "2.0.0")
]
```

## Usage

### SwiftUI

```swift
import SwiftUI
import RealityKit
import RealityVideo

struct ContentView: View {
    @State private var recorder: RealityVideoRecorder?
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            ARViewContainer(onARViewCreated: { arView in
                recorder = RealityVideoRecorder(arView: arView)
            })
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                Button(isRecording ? "Stop Recording" : "Start Recording") {
                    Task {
                        await toggleRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }
    
    func toggleRecording() async {
        guard let recorder else { return }
        
        if isRecording {
            do {
                let videoURL = try await recorder.stopRecording()
                print("Video saved to: \(videoURL)")
            } catch {
                print("Failed to stop recording: \(error)")
            }
        } else {
            do {
                try await recorder.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
        
        isRecording = recorder.isRecording
    }
}

struct ARViewContainer: UIViewRepresentable {
    let onARViewCreated: (ARView) -> Void
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        onARViewCreated(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}
```

### UIKit

```swift
import UIKit
import RealityKit
import RealityVideo

class ViewController: UIViewController {
    var arView: ARView!
    var recorder: RealityVideoRecorder!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        
        recorder = RealityVideoRecorder(arView: arView)
    }
    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        Task {
            if recorder.isRecording {
                let url = try await recorder.stopRecording()
                print("Saved to \(url)")
            } else {
                try await recorder.startRecording()
            }
        }
    }
}
```

## Configuration

Customize recording settings:

```swift
let settings = Settings(
    frameRate: 60,
    videoBitrate: 20_000_000,
    codec: .hevc,
    captureMethod: .snapshot
)

try await recorder.startRecording(settings: settings)
```

### Capture Methods

- **`.snapshot`** (default): Uses `ARView.snapshot()` to capture frames. Only captures the AR view content.
- **`.replayKit`**: Uses ReplayKit's screen capture. Captures the full screen including any UI overlays. Triggers a system permission prompt.

### Custom Output URL

```swift
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let videoURL = documentsURL.appendingPathComponent("my-ar-video.mp4")

try await recorder.startRecording(to: videoURL)
```

## API Reference

### RealityVideoRecorder

```swift
@MainActor
public final class RealityVideoRecorder {
    public init(arView: ARView)
    public var isRecording: Bool { get }
    public func startRecording(to url: URL? = nil, settings: Settings = .default) async throws
    public func stopRecording() async throws -> URL
}
```

### Settings

```swift
public struct Settings: Sendable {
    public var frameRate: Int          // Default: 30
    public var videoBitrate: Int       // Default: 10,000,000 (10 Mbps)
    public var codec: AVVideoCodecType // Default: .hevc
    public var captureMethod: CaptureMethod // Default: .snapshot
}
```

### CaptureMethod

```swift
public enum CaptureMethod: Sendable {
    case snapshot   // ARView.snapshot() - captures only AR content
    case replayKit  // Full screen capture via ReplayKit
}
```

### RealityVideoError

```swift
public enum RealityVideoError: Error, Sendable {
    case alreadyRecording
    case notRecording
    case writerFailed(String)
    case snapshotFailed
    case replayKitFailed(Error)
}
```

## License

MIT
