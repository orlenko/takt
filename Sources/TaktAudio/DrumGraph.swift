import AVFoundation
import TaktCore

/// The node graph for one kit inside a given engine (live or offline):
/// per-voice pools of player nodes (round-robin so fast retriggers overlap
/// instead of queueing) → per-voice mixer → main mixer (0.8) → peak limiter →
/// output.
public final class DrumGraph {
    public let buffers: KitBuffers

    private final class VoiceChannel {
        let players: [AVAudioPlayerNode]
        let mixer = AVAudioMixerNode()
        private var next = 0

        init(poolSize: Int) {
            players = (0..<poolSize).map { _ in AVAudioPlayerNode() }
        }

        func nextPlayer() -> AVAudioPlayerNode {
            defer { next = (next + 1) % players.count }
            return players[next]
        }
    }

    private var channels: [String: VoiceChannel] = [:]
    private let limiter: AVAudioUnitEffect

    public init(engine: AVAudioEngine, buffers: KitBuffers, poolSize: Int = 3) {
        self.buffers = buffers

        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        engine.attach(limiter)

        for voice in buffers.kit.voices {
            let channel = VoiceChannel(poolSize: poolSize)
            engine.attach(channel.mixer)
            for player in channel.players {
                engine.attach(player)
                engine.connect(player, to: channel.mixer, format: buffers.format)
            }
            engine.connect(channel.mixer, to: engine.mainMixerNode, format: nil)
            channels[voice.id] = channel
        }

        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.8
    }

    /// Call once after `engine.start()`.
    public func startPlayers() {
        forEachPlayer { $0.play() }
    }

    /// Stops every player, killing ringing tails and any hits scheduled but
    /// not yet sounding, then restarts the pools so they are ready.
    public func reset() {
        forEachPlayer { $0.stop(); $0.play() }
    }

    /// Schedule (or immediately fire, when `time` is nil) one hit.
    public func trigger(voiceID: String, gain: Float, at time: AVAudioTime?,
                        maxDuration: Double? = nil) {
        guard let channel = channels[voiceID],
              let buffer = buffers.hitBuffer(voiceID: voiceID, gain: gain,
                                             maxDuration: maxDuration) else { return }
        let player = channel.nextPlayer()
        player.scheduleBuffer(buffer, at: time, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func forEachPlayer(_ body: (AVAudioPlayerNode) -> Void) {
        for channel in channels.values {
            for player in channel.players { body(player) }
        }
    }
}
