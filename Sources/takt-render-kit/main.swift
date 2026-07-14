// Bakes the built-in kits: renders each kit's eight synth voices to float32
// WAV one-shots (TAKT-1 ported 1:1 from the design mock's Web Audio recipes;
// Nine-Oh and Dust are style variants). Run manually:
//   swift run takt-render-kit [resources-dir]
// Output defaults to Sources/TaktAudio/Resources/<KIT-ID>/; commit the WAVs.

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

// MARK: - Color tools (used by the style kits)

func drive(_ x: Double, _ amount: Double) -> Double {
    tanh(x * amount) / tanh(amount)
}

struct OnePoleLP {
    var y = 0.0
    let a: Double
    init(cutoff: Double) { a = 1 - exp(-2 * .pi * cutoff / SR) }
    mutating func process(_ x: Double) -> Double { y += a * (x - y); return y }
}

func bitcrush(_ x: Double, bits: Double) -> Double {
    let q = pow(2, bits - 1)
    return (x * q).rounded() / q
}

/// Lo-fi post chain: drive → bitcrush → lowpass, applied per sample.
func dusty(_ samples: [Float], drive amount: Double, cutoff: Double, bits: Double) -> [Float] {
    var lp = OnePoleLP(cutoff: cutoff)
    return samples.map { s in
        Float(lp.process(bitcrush(drive(Double(s), amount), bits: bits)))
    }
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

// MARK: - Nine-Oh (takt-2): 909-flavored, punchier and brighter

func renderKick909() -> [Float] {
    var phase = 0.0
    var clickPhase = 0.0
    return render(0.36) { t, _ in
        let f = 210 * pow(52 / 210, min(t, 0.055) / 0.055)
        phase += f / SR
        clickPhase += 1200 / SR
        let body = sin(2 * .pi * phase) * expEnv(t, peak: 1.05, dur: 0.32)
        let click = square(clickPhase) * expEnv(t, peak: 0.5, dur: 0.004)
        return drive(body + click, 1.3)
    }
}

func renderSnare909() -> [Float] {
    var noise = Noise(state: 0x0909_0001)
    var hp = Biquad.highpass(700)
    var p1 = 0.0, p2 = 0.0
    return render(0.26) { t, _ in
        let snap = hp.process(noise.next()) * expEnv(t, peak: 0.55, dur: 0.20)
        p1 += 187 / SR; p2 += 330 / SR
        let tone = (triangle(p1) * 0.28 + triangle(p2) * 0.18) * expEnv(t, peak: 1, dur: 0.09)
        return snap + tone
    }
}

func renderClap909() -> [Float] {
    var noise = Noise(state: 0x0909_0002)
    var bp = Biquad.bandpass(1400, q: 1.2)
    func gain(_ t: Double) -> Double {
        for i in 0..<4 {
            let t0 = Double(i) * 0.009
            if t >= t0 && t < t0 + 0.009 && t < 0.036 {
                return expSeg(t - t0, from: 0.9, to: 0.3, dur: 0.008)
            }
        }
        return t >= 0.036 ? expEnv(t - 0.036, peak: 0.65, dur: 0.16) : 0
    }
    return render(0.24) { t, _ in bp.process(noise.next()) * gain(t) }
}

func renderRim909() -> [Float] {
    var noise = Noise(state: 0x0909_0003)
    var hp = Biquad.highpass(2500)
    var phase = 0.0
    return render(0.05) { t, _ in
        phase += 1750 / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 0.4, dur: 0.02)
            + hp.process(noise.next()) * expEnv(t, peak: 0.45, dur: 0.015)
    }
}

func renderHat909(open: Bool) -> [Float] {
    let freqs = [2.0, 3.0, 4.16, 5.43, 6.79, 8.21].map { 46 * $0 }
    var phases = [Double](repeating: 0, count: freqs.count)
    var bp = Biquad.bandpass(11500, q: 0.8)
    var hp = Biquad.highpass(8200)
    let dur = open ? 0.30 : 0.04
    return render(open ? 0.45 : 0.09) { t, _ in
        var s = 0.0
        for (i, f) in freqs.enumerated() {
            phases[i] += f / SR
            s += square(phases[i])
        }
        return hp.process(bp.process(s)) * expEnv(t, peak: 0.5, dur: dur)
    }
}

func renderTom909() -> [Float] {
    var phase = 0.0
    return render(0.34) { t, _ in
        let f = 175 * pow(88 / 175, min(t, 0.12) / 0.12)
        phase += f / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 0.9, dur: 0.30)
    }
}

func renderCow909() -> [Float] {
    var p1 = 0.0, p2 = 0.0
    var bp = Biquad.bandpass(1100, q: 2.0)
    func gain(_ t: Double) -> Double {
        t < 0.025
            ? expSeg(t, from: 0.6, to: 0.18, dur: 0.025)
            : expEnv(t - 0.025, peak: 0.18, dur: 0.20)
    }
    return render(0.24) { t, _ in
        p1 += 660 / SR; p2 += 990 / SR
        return bp.process(square(p1) + square(p2)) * gain(t)
    }
}

// MARK: - Dust (takt-3): lo-fi boom-bap, driven / crushed / low-passed

func renderKickDust() -> [Float] {
    var phase = 0.0
    let base = render(0.55) { t, _ in
        let f = 105 * pow(38 / 105, min(t, 0.12) / 0.12)
        phase += f / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 1.0, dur: 0.50)
    }
    return dusty(base, drive: 2.2, cutoff: 3200, bits: 12)
}

func renderSnareDust() -> [Float] {
    var noise = Noise(state: 0x00D_0001)
    var bp = Biquad.bandpass(1350, q: 1.2)
    var phase = 0.0
    let base = render(0.20) { t, _ in
        phase += 165 / SR
        return bp.process(noise.next()) * expEnv(t, peak: 0.7, dur: 0.13)
            + triangle(phase) * expEnv(t, peak: 0.4, dur: 0.07)
    }
    return dusty(base, drive: 1.8, cutoff: 5200, bits: 12)
}

func renderClapDust() -> [Float] {
    var noise = Noise(state: 0x00D_0002)
    var bp = Biquad.bandpass(950, q: 1.3)
    func gain(_ t: Double) -> Double {
        switch t {
        case ..<0.014: expSeg(t, from: 0.85, to: 0.3, dur: 0.013)
        case ..<0.028: expSeg(t - 0.014, from: 0.85, to: 0.3, dur: 0.013)
        default: expEnv(t - 0.028, peak: 0.6, dur: 0.14)
        }
    }
    let base = render(0.20) { t, _ in bp.process(noise.next()) * gain(t) }
    return dusty(base, drive: 1.7, cutoff: 4800, bits: 12)
}

func renderRimDust() -> [Float] {
    var noise = Noise(state: 0x00D_0003)
    var hp = Biquad.highpass(2000)
    var phase = 0.0
    let base = render(0.08) { t, _ in
        phase += 470 / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 0.5, dur: 0.05)
            + hp.process(noise.next()) * expEnv(t, peak: 0.3, dur: 0.02)
    }
    return dusty(base, drive: 1.5, cutoff: 5000, bits: 12)
}

func renderHatDust(open: Bool) -> [Float] {
    var noise = Noise(state: open ? 0x00D_0005 : 0x00D_0004)
    var hp = Biquad.highpass(open ? 4200 : 4800)
    let dur = open ? 0.22 : 0.035
    let base = render(open ? 0.30 : 0.07) { t, _ in
        hp.process(noise.next()) * expEnv(t, peak: open ? 0.42 : 0.4, dur: dur)
    }
    return dusty(base, drive: 1.4, cutoff: open ? 8000 : 8500, bits: 11)
}

func renderTomDust() -> [Float] {
    var phase = 0.0
    let base = render(0.32) { t, _ in
        let f = 130 * pow(62 / 130, min(t, 0.16) / 0.16)
        phase += f / SR
        return sin(2 * .pi * phase) * expEnv(t, peak: 0.85, dur: 0.28)
    }
    return dusty(base, drive: 1.8, cutoff: 3800, bits: 12)
}

func renderCowDust() -> [Float] {
    var p1 = 0.0, p2 = 0.0
    var bp = Biquad.bandpass(700, q: 2.0)
    func gain(_ t: Double) -> Double {
        t < 0.03
            ? expSeg(t, from: 0.5, to: 0.15, dur: 0.03)
            : expEnv(t - 0.03, peak: 0.15, dur: 0.17)
    }
    let base = render(0.22) { t, _ in
        p1 += 395 / SR; p2 += 590 / SR
        return bp.process(square(p1) + square(p2)) * gain(t)
    }
    return dusty(base, drive: 1.6, cutoff: 4200, bits: 12)
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

let kitRenderers: [(Kit, [String: () -> [Float]])] = [
    (.takt1, [
        "kick": renderKick, "snare": renderSnare, "clap": renderClap, "rim": renderRim,
        "chat": { renderHat(open: false) }, "ohat": { renderHat(open: true) },
        "tom": renderTom, "cow": renderCow,
    ]),
    (.takt2, [
        "kick": renderKick909, "snare": renderSnare909, "clap": renderClap909,
        "rim": renderRim909, "chat": { renderHat909(open: false) },
        "ohat": { renderHat909(open: true) }, "tom": renderTom909, "cow": renderCow909,
    ]),
    (.takt3, [
        "kick": renderKickDust, "snare": renderSnareDust, "clap": renderClapDust,
        "rim": renderRimDust, "chat": { renderHatDust(open: false) },
        "ohat": { renderHatDust(open: true) }, "tom": renderTomDust, "cow": renderCowDust,
    ]),
]

let baseDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/TaktAudio/Resources")

for (kit, renderers) in kitRenderers {
    let outDir = baseDir.appendingPathComponent(kit.id.uppercased())
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    for voice in kit.voices {
        guard let renderer = renderers[voice.id] else {
            fatalError("no renderer for voice \(voice.id) in \(kit.name)")
        }
        let samples = renderer()
        let url = outDir.appendingPathComponent(voice.sampleFile)
        try? FileManager.default.removeItem(at: url)
        try writeWAV(samples, to: url)
        let peak = samples.map(abs).max() ?? 0
        let ms = Int(Double(samples.count) / SR * 1000)
        print("\(kit.name)/\(voice.sampleFile): \(ms) ms, peak \(String(format: "%.3f", peak))")
    }
}
print("kits rendered to \(baseDir.path)")
