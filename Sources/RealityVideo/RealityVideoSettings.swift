//
//  File.swift
//  
//
//  Created by Tadreik Campbell on 6/11/22.
//

import AVFoundation

public protocol VideoSettings {
    var bitrate: Int { get set }
    var audioMode: AVAudioSession.Category { get set }
    var audioOptions: AVAudioSession.CategoryOptions { get set }
    var outputURL: URL { get set }
}

public struct RealityVideoSettings: VideoSettings {
    public var bitrate: Int
    public var audioMode: AVAudioSession.Category
    public var audioOptions: AVAudioSession.CategoryOptions
    public var outputURL: URL
    
    public static var standard: Self {
        RealityVideoSettings(
            bitrate: 1000000,
            audioMode: .record,
            audioOptions: [.mixWithOthers],
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, conformingTo: .quickTimeMovie)
            
        )
    }
}
