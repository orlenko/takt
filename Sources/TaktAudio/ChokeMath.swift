import TaktCore

/// Pattern-aware choke: an open hat scheduled at step k is truncated to end
/// where the next hit in its choke group lands (closed hat, or its own next
/// hit). Deterministic, identical in live playback and offline bounce.
/// Hand-played (unscheduled) hits do not choke in v1; see SPEC.md.
enum ChokeMath {
    /// Seconds from `step`'s start to the next audible choke-group hit,
    /// wrapping around the loop; nil when the voice has no choke group or no
    /// later hit exists in the group.
    static func limit(kit: Kit, pattern: Pattern, trackIndex: Int, step: Int,
                      tempoBPM: Double, swingPercent: Double) -> Double? {
        guard let group = kit.voice(id: pattern.tracks[trackIndex].voiceID)?.chokeGroup else {
            return nil
        }
        let n = pattern.stepCount
        let t0 = Timing.stepTime(step: step, tempoBPM: tempoBPM, swingPercent: swingPercent)
        let loop = Timing.loopDuration(stepCount: n, tempoBPM: tempoBPM)

        for offset in 1...n {
            let s = (step + offset) % n
            for (j, track) in pattern.tracks.enumerated() {
                guard track.steps.indices.contains(s), track.steps[s].isOn,
                      pattern.isAudible(trackIndex: j),
                      kit.voice(id: track.voiceID)?.chokeGroup == group else { continue }
                var t1 = Timing.stepTime(step: s, tempoBPM: tempoBPM, swingPercent: swingPercent)
                if s <= step { t1 += loop }
                return t1 - t0
            }
        }
        return nil
    }
}
