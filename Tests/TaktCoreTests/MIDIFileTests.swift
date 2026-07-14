import XCTest
@testable import TaktCore

final class MIDIFileTests: XCTestCase {
    /// Minimal SMF reader for round-trip assertions. Assumes the writer's
    /// output shape: no running status, single track.
    private struct Event: Equatable {
        let tick: Int
        let bytes: [UInt8]
    }

    private func parse(_ data: Data) -> (division: Int, events: [Event]) {
        let b = [UInt8](data)
        XCTAssertEqual(Array(b[0..<4]), Array("MThd".utf8))
        let division = Int(b[12]) << 8 | Int(b[13])
        XCTAssertEqual(Array(b[14..<18]), Array("MTrk".utf8))
        var i = 22
        var tick = 0
        var events: [Event] = []
        while i < b.count {
            var delta = 0
            while true {
                delta = (delta << 7) | Int(b[i] & 0x7F)
                let more = b[i] & 0x80 != 0
                i += 1
                if !more { break }
            }
            tick += delta
            if b[i] == 0xFF {
                let length = Int(b[i + 2])
                events.append(Event(tick: tick, bytes: Array(b[i..<(i + 3 + length)])))
                i += 3 + length
            } else {
                events.append(Event(tick: tick, bytes: Array(b[i..<(i + 3)])))
                i += 3
            }
        }
        return (division, events)
    }

    func testHeaderAndTempo() {
        let seed = Seeds.house
        let data = MIDIFile.data(patterns: [seed.pattern(kit: .takt1)], playOrder: [0],
                                 kit: .takt1, tempoBPM: seed.tempoBPM,
                                 swingPercent: seed.swingPercent)
        let (division, events) = parse(data)
        XCTAssertEqual(division, 960)
        // Tempo meta: 60_000_000 / 122 rounded, big-endian 24-bit.
        let mpqn = Int((60_000_000 / seed.tempoBPM).rounded())
        XCTAssertEqual(events.first, Event(tick: 0, bytes: [0xFF, 0x51, 0x03,
                                                            UInt8((mpqn >> 16) & 0xFF),
                                                            UInt8((mpqn >> 8) & 0xFF),
                                                            UInt8(mpqn & 0xFF)]))
        XCTAssertEqual(events.last?.bytes, [0xFF, 0x2F, 0x00])
        XCTAssertEqual(events.last?.tick, 16 * 240)
    }

    func testNoteEventsMatchPattern() {
        let seed = Seeds.house
        let pattern = seed.pattern(kit: .takt1)
        let data = MIDIFile.data(patterns: [pattern], playOrder: [0], kit: .takt1,
                                 tempoBPM: seed.tempoBPM, swingPercent: seed.swingPercent)
        let (_, events) = parse(data)
        let noteOns = events.filter { $0.bytes.first == 0x99 }
        let expectedHits = pattern.tracks.flatMap(\.steps).filter(\.isOn).count
        XCTAssertEqual(noteOns.count, expectedHits)
        // First hit: accented kick (GM 36, velocity 127) at tick 0.
        XCTAssertEqual(noteOns.first, Event(tick: 0, bytes: [0x99, 36, 127]))
        // Every note-on has a matching note-off.
        XCTAssertEqual(events.filter { $0.bytes.first == 0x89 }.count, expectedHits)
    }

    func testSwingBakedIntoOddTicks() {
        var pattern = Pattern(kit: .takt1)
        pattern.tracks[0].steps[1] = Step(velocity: 96) // odd step, swung
        let data = MIDIFile.data(patterns: [pattern], playOrder: [0], kit: .takt1,
                                 tempoBPM: 120, swingPercent: 75)
        let (_, events) = parse(data)
        let noteOn = events.first { $0.bytes.first == 0x99 }
        // Pair is half a beat (480 ticks); at 75% swing the offbeat lands at 360.
        XCTAssertEqual(noteOn?.tick, 360)
    }

    func testChainOffsetsSecondSlot() {
        var a = Pattern(kit: .takt1)
        a.tracks[0].steps[0] = Step(velocity: 127)
        var b = Pattern(kit: .takt1)
        b.tracks[1].steps[0] = Step(velocity: 96)
        let data = MIDIFile.data(patterns: [a, b], playOrder: [0, 1], kit: .takt1,
                                 tempoBPM: 120, swingPercent: 50)
        let (_, events) = parse(data)
        let noteOns = events.filter { $0.bytes.first == 0x99 }
        XCTAssertEqual(noteOns.count, 2)
        XCTAssertEqual(noteOns[0], Event(tick: 0, bytes: [0x99, 36, 127]))
        // Slot B starts one 16-step pattern later: 16 * 240 ticks.
        XCTAssertEqual(noteOns[1], Event(tick: 3840, bytes: [0x99, 38, 96]))
        XCTAssertEqual(events.last?.tick, 7680, "end of track closes the full chain")
    }

    func testMutedTracksAreExcluded() {
        var pattern = Pattern(kit: .takt1)
        pattern.tracks[0].steps[0] = Step(velocity: 127)
        pattern.tracks[1].steps[4] = Step(velocity: 96)
        pattern.tracks[1].isMuted = true
        let data = MIDIFile.data(patterns: [pattern], playOrder: [0], kit: .takt1,
                                 tempoBPM: 120, swingPercent: 50)
        let (_, events) = parse(data)
        let noteOns = events.filter { $0.bytes.first == 0x99 }
        XCTAssertEqual(noteOns.map { $0.bytes[1] }, [36], "muted snare must not export")
    }
}
