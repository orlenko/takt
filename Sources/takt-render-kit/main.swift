// Bakes the TAKT-1 kit: renders the eight synth voices (ported 1:1 from the
// design mock's Web Audio recipes) to float32 WAV one-shots. Run manually:
//   swift run takt-render-kit [output-dir]
// Output defaults to Sources/TaktAudio/Resources/TAKT-1; commit the WAVs.

import AVFoundation
import Foundation
import TaktCore

let SR = 48000.0

// MARK: - DSP primitives

struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(_ f: Double, q: Double, sr: Double = SR) -> Biquad {
        let w0 = 2 * .pi * f / sr, alpha = sin(w0) / (2 * q), c = cos(w0)
        let a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0,
                      a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    static func highpass(_ f: Double, q: Double = 0.7071, sr: Double = SR) -> Biquad {
        let w0 = 2 * .pi * f / sr, alpha = sin(w0) / (2 * q), c = cos(w0)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0,
                      a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Exponential decay from `peak` to 0.001 over `dur` (Web Audio
/// exponentialRampToValueAtTime shape), zero afterwards.
func expEnv(_ t: Double, peak: Double, dur: Double) -> Double {
    guard t >= 0, t < dur else { return 0 }
    return peak * pow(0.001 / peak, t / dur)
}

/// Exponential segment from `from` to `to` over `dur`, clamped.
func expSeg(_ t: Double, from: Double, to: Double, dur: Double) -> Double {
    from * pow(to / from, min(max(t, 0), dur) / dur)
}

/// Deterministic white noise (xorshift32) so renders are reproducible.
struct Noise {
    var state: UInt32 = 0x9E37_79B9
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
}

func square(_ phase: Double) -> Double {
    phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1
}

func triangle(_ phase: Double) -> Double {
    let frac = phase.truncatingRemainder(dividingBy: 1)
    return 4 * abs(frac - 0.5) - 1
}

func render(_ seconds: Double, _ sample: (Double, Int) -> Double) -> [Float] {
    let n = Int(seconds * SR)
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n { out[i] = Float(sample(Double(i) / SR, i)) }
    return out
}

// MARK: - Voices (mock parity)

func renderKick() -> [Float] {
    var phase = 0.0
    return render(0.46) { t, _ in
        let f = 165 * pow(46 / 165, min(t, 0.10) / 0.10)
        phase += f / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 1.1, dur: 0.42)
    }
}

func renderSnare() -> [Float] {
    var noise = Noise()
    var bp = Biquad.bandpass(1900, q: 0.8)
    var tonePhase = 0.0
    return render(0.24) { t, _ in
        let n = bp.process(noise.next()) * expEnv(t, peak: 0.75, dur: 0.16)
        tonePhase += 196 / SR
        let tone = triangle(tonePhase) * expEnv(t, peak: 0.45, dur: 0.09)
        return n + tone
    }
}

func renderClap() -> [Float] {
    var noise = Noise(state: 0xC0FF_EE01)
    var bp = Biquad.bandpass(1150, q: 1.4)
    func gain(_ t: Double) -> Double {
        switch t {
        case ..<0.012: expSeg(t, from: 0.85, to: 0.25, dur: 0.011)
        case ..<0.024: expSeg(t - 0.012, from: 0.85, to: 0.25, dur: 0.011)
        case ..<0.036: expSeg(t - 0.024, from: 0.85, to: 0.25, dur: 0.011)
        default: expEnv(t - 0.036, peak: 0.7, dur: 0.22 - 0.036)
        }
    }
    return render(0.26) { t, _ in bp.process(noise.next()) * gain(t) }
}

func renderRim() -> [Float] {
    var noise = Noise(state: 0xDEAD_BEEF)
    var hp = Biquad.highpass(3800)
    var phase = 0.0
    return render(0.07) { t, _ in
        let click = hp.process(noise.next()) * expEnv(t, peak: 0.5, dur: 0.03)
        phase += 640 / SR
        return click + sin(2 * .pi * phase) * expEnv(t, peak: 0.35, dur: 0.045)
    }
}

func renderHat(open: Bool) -> [Float] {
    // Classic 808-style metallic stack: six detuned squares through band/highpass.
    let freqs = [2.0, 3.0, 4.16, 5.43, 6.79, 8.21].map { 40 * $0 }
    var phases = [Double](repeating: 0, count: freqs.count)
    var bp = Biquad.bandpass(10500, q: 0.8)
    var hp = Biquad.highpass(7500)
    let dur = open ? 0.45 : 0.055
    let peak = open ? 0.5 : 0.45
    return render(open ? 0.60 : 0.12) { t, _ in
        var s = 0.0
        for (i, f) in freqs.enumerated() {
            phases[i] += f / SR
            s += square(phases[i])
        }
        return hp.process(bp.process(s)) * expEnv(t, peak: peak, dur: dur)
    }
}

func renderTom() -> [Float] {
    var phase = 0.0
    return render(0.32) { t, _ in
        let f = 150 * pow(78 / 150, min(t, 0.18) / 0.18)
        phase += f / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 0.95, dur: 0.28)
    }
}

func renderCow() -> [Float] {
    var p1 = 0.0, p2 = 0.0
    var bp = Biquad.bandpass(900, q: 2.2)
    func gain(_ t: Double) -> Double {
        t < 0.03
            ? expSeg(t, from: 0.65, to: 0.18, dur: 0.03)
            : expEnv(t - 0.03, peak: 0.18, dur: 0.25)
    }
    return render(0.30) { t, _ in
        p1 += 540 / SR; p2 += 810 / SR
        return bp.process(square(p1) + square(p2)) * gain(t)
    }
}

// MARK: - Output

func writeWAV(_ samples: [Float], to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: SR,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SR,
                            channels: 1, interleaved: false)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))!
    buf.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer {
        buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
    }
    try file.write(from: buf)
}

let renderers: [String: () -> [Float]] = [
    "kick": renderKick,
    "snare": renderSnare,
    "clap": renderClap,
    "rim": renderRim,
    "chat": { renderHat(open: false) },
    "ohat": { renderHat(open: true) },
    "tom": renderTom,
    "cow": renderCow,
]

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/TaktAudio/Resources/TAKT-1")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for voice in Kit.takt1.voices {
    guard let renderer = renderers[voice.id] else {
        fatalError("no renderer for voice \(voice.id)")
    }
    let samples = renderer()
    let url = outDir.appendingPathComponent(voice.sampleFile)
    try? FileManager.default.removeItem(at: url)
    try writeWAV(samples, to: url)
    let peak = samples.map(abs).max() ?? 0
    let ms = Int(Double(samples.count) / SR * 1000)
    print("\(voice.sampleFile): \(ms) ms, peak \(String(format: "%.3f", peak))")
}
print("kit TAKT-1 rendered to \(outDir.path)")
