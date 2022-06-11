# RealityVideo

Allows you to record videos in RealityKit. Just replace your `ARView` with `RealityView`,
then you can call the methods on RealityView `myARView.startRecording()` `myARView.endRecording()`.
No additional setup neccessary.

## SwiftUI Example
```swift
// 1. Initialize RealityView for SwiftUI
struct ARViewContainer: UIViewRepresentable {
    var arView: RealityView!

    func makeUIView(context: Context) -> RealityView {
        // 2. (Optional) set up options for recording
        // note: audio settings must be set before initialization
        let settings = RealityVideoSettings()
        settings.outputURL = FileManager....some location in the file system
        arView = RealityView(settings: settings)
        // you are responsible for this file, RealityVideo simply writes to that location
        // Load the "Box" scene from the "Experience" Reality File
        let boxAnchor = try! Experience.loadBox()

        // Add the box anchor to the scene
        arView.scene.anchors.append(boxAnchor)
        return arView
    }

    func updateUIView(_ uiView: RealityView, context: Context) {}

}
    
struct ContentView: View {
    // 3. Add the swiftui view
    var arView: ARViewContainer = ARViewContainer()
    
    var body: some View {
        ZStack {
            arView.edgesIgnoringSafeArea(.all)
            Button {
                // 4. start recording
                switch arView.arView.captureState {
                case .idle:
                    arView.arView.startRecording()
                case .capturing:
                    arView.arView.endRecording { 
                        // optionally perform some work when recording finishes
                    }
                default:
                    break
                }
            } label: {
                Text("Record")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```
