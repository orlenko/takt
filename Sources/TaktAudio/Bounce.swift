import AVFoundation
import TaktCore

/// Offline render of a pattern to a WAV file, using the same graph and the
/// same timing/choke math as live playback. Serves WAV export and the
/// engine's own smoke test.
public enum Bounce {
    public static let sampleRate = 48000.0

    @discardableResult
    public static func render(pattern: TaktCore.Pattern, kit: Kit, tempoBPM: Double,
                              swingPercent: Double, loops: Int = 1,
                              tailSeconds: Double = 0.5, to url: URL) throws -> Double {
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
        let loopDur = Timing.loopDuration(stepCount: pattern.stepCount, tempoBPM: tempoBPM)
        for loop in 0..<max(1, loops) {
            for step in 0..<pattern.stepCount {
                for (i, track) in pattern.tracks.enumerated() {
                    guard track.steps.indices.contains(step) else { continue }
                    let hit = track.steps[step]
                    guard hit.isOn, pattern.isAudible(trackIndex: i) else { continue }
                    let t = Double(loop) * loopDur
                        + Timing.stepTime(step: step, tempoBPM: tempoBPM, swingPercent: swingPercent)
                    let choke = ChokeMath.limit(kit: kit, pattern: pattern, trackIndex: i,
                                                step: step, tempoBPM: tempoBPM,
                                                swingPercent: swingPercent)
                    let time = AVAudioTime(sampleTime: AVAudioFramePosition(t * sampleRate),
                                           atRate: sampleRate)
                    graph.trigger(voiceID: track.voiceID, gain: hit.gain * track.level,
                                  at: time, maxDuration: choke)
                }
            }
        }

        let totalSeconds = Double(max(1, loops)) * loopDur + tailSeconds
        let totalFrames = AVAudioFramePosition(totalSeconds * sampleRate)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings,
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
