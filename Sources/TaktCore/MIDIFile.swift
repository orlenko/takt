import Foundation

/// Standard MIDI File (type 0) writer. Pure function of the model: one chain
/// pass, GM note numbers on channel 10, swing baked into tick offsets via the
/// shared Timing math, velocities as stored. 960 PPQN.
public enum MIDIFile {
    public static let ppqn = 960

    public static func data(patterns: [Pattern], playOrder: [Int], kit: Kit,
                            tempoBPM: Double, swingPercent: Double) -> Data {
        let ticksPer16th = ppqn / 4
        let gate = ticksPer16th / 2 // short drum gate

        var events: [(tick: Int, bytes: [UInt8])] = []
        var metas: [(tick: Int, bytes: [UInt8])] = []
        var origin = 0
        var lastNumerator = 0
        for index in playOrder where patterns.indices.contains(index) {
            let pattern = patterns[index]
            // Time-signature meta wherever the meter changes. Bars are x/4 by
            // construction (stepCount = beats × 4 sixteenths).
            let numerator = max(1, pattern.stepCount / 4)
            if numerator != lastNumerator {
                metas.append((origin, [0xFF, 0x58, 0x04, UInt8(numerator), 2, 24, 8]))
                lastNumerator = numerator
            }
            for (t, track) in pattern.tracks.enumerated() {
                guard pattern.isAudible(trackIndex: t),
                      let note = kit.voice(id: track.voiceID)?.gmNote else { continue }
                for (s, step) in track.steps.enumerated() where step.isOn {
                    // Seconds → beats keeps the swing math in one place.
                    let beats = Timing.stepTime(step: s, tempoBPM: tempoBPM,
                                                swingPercent: swingPercent) * tempoBPM / 60
                    let tick = origin + Int((beats * Double(ppqn)).rounded())
                    events.append((tick, [0x99, note, step.velocity]))
                    events.append((tick + gate, [0x89, note, 0]))
                }
            }
            origin += pattern.stepCount * ticksPer16th
        }

        // Offs before ons at the same tick (0x89 < 0x99) so retriggered notes
        // never read as overlapping. Tempo meta is pinned ahead of the sort.
        events.sort { $0.tick == $1.tick ? $0.bytes[0] < $1.bytes[0] : $0.tick < $1.tick }
        // Time-signature metas land ahead of notes sharing their tick (a byte
        // sort would put 0xFF after 0x99).
        var merged: [(tick: Int, bytes: [UInt8])] = []
        var mi = 0
        for event in events {
            while mi < metas.count, metas[mi].tick <= event.tick {
                merged.append(metas[mi])
                mi += 1
            }
            merged.append(event)
        }
        merged.append(contentsOf: metas[mi...])
        events = merged
        let microsecondsPerQuarter = Int((60_000_000 / tempoBPM).rounded())
        events.insert((0, [0xFF, 0x51, 0x03,
                           UInt8((microsecondsPerQuarter >> 16) & 0xFF),
                           UInt8((microsecondsPerQuarter >> 8) & 0xFF),
                           UInt8(microsecondsPerQuarter & 0xFF)]), at: 0)
        events.append((max(origin, events.last?.tick ?? 0), [0xFF, 0x2F, 0x00]))

        var track: [UInt8] = []
        var previousTick = 0
        for event in events {
            track += vlq(event.tick - previousTick)
            track += event.bytes
            previousTick = event.tick
        }

        var bytes = Array("MThd".utf8) + u32(6) + u16(0) + u16(1) + u16(ppqn)
        bytes += Array("MTrk".utf8) + u32(track.count) + track
        return Data(bytes)
    }

    private static func vlq(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }

    private static func u16(_ v: Int) -> [UInt8] {
        [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func u32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
         UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}
