import AVFoundation
import TaktCore

/// Audio export container formats. WAV for DAWs; M4A (AAC) for phones and
/// long jogging mixes. Apple ships no MP3 encoder; AAC is the native
/// equivalent and plays everywhere Android does.
public enum AudioExportFormat: String, CaseIterable, Sendable {
    case wav
    case m4a

    public var fileExtension: String { rawValue }

    var fileSettings: [String: Any] {
        switch self {
        case .wav: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Bounce.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        case .m4a: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Bounce.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        }
    }
}

/// Offline render of a pattern to an audio file, using the same graph and the
/// same timing/choke math as live playback. Serves export and the engine's
/// own smoke test.
public enum Bounce {
    public static let sampleRate = 48000.0

    /// Single-pattern convenience: `loops` repeats of one pattern.
    @discardableResult
    public static func render(pattern: TaktCore.Pattern, kit: Kit, tempoBPM: Double,
                              swingPercent: Double, loops: Int = 1,
                              tailSeconds: Double = 0.5, to url: URL,
                              format: AudioExportFormat = .wav) throws -> Double {
        try render(patterns: [pattern], playOrder: [0], kit: kit, tempoBPM: tempoBPM,
                   swingPercent: swingPercent, cycles: loops, tailSeconds: tailSeconds,
                   to: url, format: format)
    }

    /// Renders `cycles` passes of the chain (`playOrder` indices into
    /// `patterns`), matching live playback exactly.
    @discardableResult
    public static func render(patterns: [TaktCore.Pattern], playOrder: [Int], kit: Kit,
                              tempoBPM: Double, swingPercent: Double, cycles: Int = 1,
                              tailSeconds: Double = 0.5, to url: URL,
                              format: AudioExportFormat = .wav) throws -> Double {
        let order = playOrder.filter { patterns.indices.contains($0) }
        guard !order.isEmpty else { throw TaktAudioError.renderFailed("empty chain") }

        let engine = AVAudioEngine()
        let buffers = try KitBuffers(kit: kit)
        let graph = DrumGraph(engine: engine, buffers: buffers)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw TaktAudioError.renderFailed("format")
        }
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        try engine.start()
        graph.startPlayers()

        // In manual rendering mode the player timeline starts at render
        // sample 0, so hits are scheduled directly at sample positions.
        var origin = 0.0
        for _ in 0..<max(1, cycles) {
            for patternIndex in order {
                let pattern = patterns[patternIndex]
                for step in 0..<pattern.stepCount {
                    for (i, track) in pattern.tracks.enumerated() {
                        guard track.steps.indices.contains(step) else { continue }
                        let hit = track.steps[step]
                        guard hit.isOn, pattern.isAudible(trackIndex: i) else { continue }
                        let t = origin + Timing.stepTime(step: step, tempoBPM: tempoBPM,
                                                         swingPercent: swingPercent)
                        let choke = ChokeMath.limit(kit: kit, pattern: pattern, trackIndex: i,
                                                    step: step, tempoBPM: tempoBPM,
                                                    swingPercent: swingPercent)
                        let time = AVAudioTime(sampleTime: AVAudioFramePosition(t * sampleRate),
                                               atRate: sampleRate)
                        graph.trigger(voiceID: track.voiceID, gain: hit.gain * track.level,
                                      at: time, maxDuration: choke)
                    }
                }
                origin += Timing.loopDuration(stepCount: pattern.stepCount, tempoBPM: tempoBPM)
            }
        }

        let totalSeconds = origin + tailSeconds
        let totalFrames = AVAudioFramePosition(totalSeconds * sampleRate)

        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.fileSettings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                         frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw TaktAudioError.bufferAllocation
        }

        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let frames = min(AVAudioFrameCount(remaining), engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(frames, to: buf)
            guard status == .success else {
                throw TaktAudioError.renderFailed("status \(status.rawValue)")
            }
            try file.write(from: buf)
        }
        engine.stop()
        return totalSeconds
    }
}
