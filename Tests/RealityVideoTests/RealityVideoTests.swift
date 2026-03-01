import XCTest
import AVFoundation
@testable import RealityVideo

final class RealityVideoTests: XCTestCase {
    
    func testDefaultSettings() {
        let settings = Settings()
        
        XCTAssertEqual(settings.frameRate, 30)
        XCTAssertEqual(settings.videoBitrate, 10_000_000)
        XCTAssertEqual(settings.codec, .hevc)
        XCTAssertTrue(settings.captureMethod == .snapshot)
    }
    
    func testStaticDefaultSettings() {
        let settings = Settings.default
        
        XCTAssertEqual(settings.frameRate, 30)
        XCTAssertEqual(settings.videoBitrate, 10_000_000)
    }
    
    func testCustomSettings() {
        let settings = Settings(
            frameRate: 60,
            videoBitrate: 20_000_000,
            codec: .h264,
            captureMethod: .replayKit
        )
        
        XCTAssertEqual(settings.frameRate, 60)
        XCTAssertEqual(settings.videoBitrate, 20_000_000)
        XCTAssertEqual(settings.codec, .h264)
        XCTAssertTrue(settings.captureMethod == .replayKit)
    }
    
    func testCaptureMethodEquality() {
        XCTAssertTrue(CaptureMethod.snapshot == .snapshot)
        XCTAssertTrue(CaptureMethod.replayKit == .replayKit)
        XCTAssertFalse(CaptureMethod.snapshot == .replayKit)
    }
    
    func testErrorDescriptions() {
        let alreadyRecording = RealityVideoError.alreadyRecording
        let notRecording = RealityVideoError.notRecording
        let writerFailed = RealityVideoError.writerFailed("Test error")
        
        XCTAssertNotNil(alreadyRecording)
        XCTAssertNotNil(notRecording)
        XCTAssertNotNil(writerFailed)
    }
}
