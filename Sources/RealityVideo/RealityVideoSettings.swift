//
//  File.swift
//  
//
//  Created by Tadreik Campbell on 6/11/22.
//

import AVFoundation

public struct RealityVideoSettings {
    public var bitrate: Int
    public var audioMode: AVAudioSession.Category
    public var audioOptions: AVAudioSession.CategoryOptions
    public var outputURL: URL
    
    public static var standard: RealityVideoSettings {
        RealityVideoSettings(
            bitrate: 1000000,
            audioMode: .record,
            audioOptions: [.mixWithOthers],
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, conformingTo: .quickTimeMovie)
            
        )
    }
}
