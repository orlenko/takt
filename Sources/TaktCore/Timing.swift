import Foundation

/// Pure timing math shared by the live scheduler, WAV bounce, and MIDI export.
/// Swing shifts every odd 16th later within its pair: 50% = straight,
/// 66.7% = triplet feel, 75% = hard shuffle (the cap).
public enum Timing {
    /// Duration of one straight 16th note, seconds.
    public static func sixteenth(tempoBPM: Double) -> Double {
        60 / tempoBPM / 4
    }

    /// Start of step `k` (0-based) within the loop, seconds.
    public static func stepTime(step: Int, tempoBPM: Double, swingPercent: Double) -> Double {
        let pair = 2 * sixteenth(tempoBPM: tempoBPM)
        let base = Double(step / 2) * pair
        return step.isMultiple(of: 2) ? base : base + pair * (swingPercent / 100)
    }

    /// Time from the start of step `k` to the start of the next step, seconds.
    /// Even steps last `pair * swing`, odd steps `pair * (1 - swing)`.
    public static func stepDuration(step: Int, tempoBPM: Double, swingPercent: Double) -> Double {
        let pair = 2 * sixteenth(tempoBPM: tempoBPM)
        let sw = swingPercent / 100
        return step.isMultiple(of: 2) ? pair * sw : pair * (1 - sw)
    }

    /// Full loop length, seconds. Independent of swing.
    public static func loopDuration(stepCount: Int, tempoBPM: Double) -> Double {
        Double(stepCount) * sixteenth(tempoBPM: tempoBPM)
    }
}
