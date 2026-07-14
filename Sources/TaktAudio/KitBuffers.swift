import AVFoundation
import TaktCore

public enum TaktAudioError: Error, CustomStringConvertible {
    case missingSample(String)
    case bufferAllocation
    case renderFailed(String)

    public var description: String {
        switch self {
        case .missingSample(let name): "missing sample \(name) (run: swift run takt-render-kit)"
        case .bufferAllocation: "could not allocate audio buffer"
        case .renderFailed(let why): "offline render failed: \(why)"
        }
    }
}

/// Loaded one-shot buffers for a kit, plus a cache of velocity-scaled (and
/// optionally choke-truncated) copies. Baking gain into the buffer keeps
/// per-hit velocity correct in offline renders, where node volume cannot be
/// scheduled over time.
public final class KitBuffers {
    public let kit: Kit
    public let format: AVAudioFormat

    private var sources: [String: AVAudioPCMBuffer] = [:]
    private var cache: [HitKey: AVAudioPCMBuffer] = [:]
    private let lock = NSLock()

    private struct HitKey: Hashable {
        let voiceID: String
        let gainBucket: Int
        let frames: AVAudioFrameCount
    }

    public init(kit: Kit) throws {
        self.kit = kit
        var loaded: [String: AVAudioPCMBuffer] = [:]
        for voice in kit.voices {
            let base = (voice.sampleFile as NSString).deletingPathExtension
            guard let url = Bundle.module.url(forResource: base, withExtension: "wav",
                                              subdirectory: kit.id.uppercased()) else {
                throw TaktAudioError.missingSample(voice.sampleFile)
            }
            let file = try AVAudioFile(forReading: url)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)) else {
                throw TaktAudioError.bufferAllocation
            }
            try file.read(into: buf)
            loaded[voice.id] = buf
        }
        guard let any = loaded.values.first else { throw TaktAudioError.bufferAllocation }
        self.sources = loaded
        self.format = any.format
    }

    /// A playable copy scaled by `gain` (bucketed to keep the cache small),
    /// truncated to `maxDuration` with a short fade when choked.
    public func hitBuffer(voiceID: String, gain: Float, maxDuration: Double? = nil) -> AVAudioPCMBuffer? {
        guard let src = sources[voiceID], let srcData = src.floatChannelData?[0] else { return nil }
        let bucket = min(32, Int((max(0, gain) * 32).rounded()))
        guard bucket > 0 else { return nil }

        var frames = src.frameLength
        if let d = maxDuration {
            frames = min(frames, AVAudioFrameCount(max(64, d * src.format.sampleRate)))
        }
        let key = HitKey(voiceID: voiceID, gainBucket: bucket, frames: frames)

        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }

        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: frames),
              let dstData = dst.floatChannelData?[0] else { return nil }
        dst.frameLength = frames
        let g = Float(bucket) / 32
        for i in 0..<Int(frames) { dstData[i] = srcData[i] * g }
        if frames < src.frameLength {
            let fade = min(128, Int(frames))
            for i in 0..<fade {
                dstData[Int(frames) - fade + i] *= Float(fade - i) / Float(fade)
            }
        }
        cache[key] = dst
        return dst
    }
}
