import AVFoundation
import XCTest
import TaktCore
@testable import TaktAudio

final class BounceTests: XCTestCase {
    private func rms(of url: URL, fromSecond: Double = 0, toSecond: Double? = nil) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TaktAudioError.bufferAllocation
        }
        try file.read(into: buf)
        guard let data = buf.floatChannelData?[0] else { throw TaktAudioError.bufferAllocation }
        let sr = format.sampleRate
        let start = Int(fromSecond * sr)
        let end = min(Int(buf.frameLength), toSecond.map { Int($0 * sr) } ?? Int(buf.frameLength))
        guard end > start else { return 0 }
        var sum = 0.0
        for i in start..<end { sum += Double(data[i]) * Double(data[i]) }
        return (sum / Double(end - start)).squareRoot()
    }

    func testHouseSeedBounceIsAudibleAndExactLength() throws {
        let seed = Seeds.house
        let pattern = seed.pattern(kit: .takt1)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-bounce-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = try Bounce.render(pattern: pattern, kit: .takt1,
                                        tempoBPM: seed.tempoBPM,
                                        swingPercent: seed.swingPercent,
                                        loops: 2, to: url)

        let expected = 2 * Timing.loopDuration(stepCount: 16, tempoBPM: seed.tempoBPM) + 0.5
        XCTAssertEqual(seconds, expected, accuracy: 1e-9)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length), expected * Bounce.sampleRate, accuracy: 4096)

        // Loud enough overall, and still playing in the second loop.
        XCTAssertGreaterThan(try rms(of: url), 0.02)
        XCTAssertGreaterThan(try rms(of: url, fromSecond: expected / 2, toSecond: expected - 0.5), 0.02)
        // The first kick lands at t=0, so the head must not be silent.
        XCTAssertGreaterThan(try rms(of: url, fromSecond: 0, toSecond: 0.05), 0.05)
    }

    func testEveryKitLoadsAndSounds() throws {
        for kit in Kit.all {
            let buffers = try KitBuffers(kit: kit)
            for voice in kit.voices {
                XCTAssertNotNil(buffers.hitBuffer(voiceID: voice.id, gain: 1),
                                "\(kit.name)/\(voice.id) must load")
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("takt-kit-\(kit.id)-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let seed = Seeds.house
            try Bounce.render(pattern: seed.pattern(kit: kit), kit: kit,
                              tempoBPM: seed.tempoBPM, swingPercent: seed.swingPercent,
                              loops: 1, to: url)
            XCTAssertGreaterThan(try rms(of: url), 0.02, "\(kit.name) must be audible")
        }
    }

    func testChainRendersSlotsInOrder() throws {
        // Slot A: lone kick at step 0. Slot B: lone snare at step 0.
        // Chain A→B at 120 BPM: kick energy at 0 s, silence late in A,
        // snare energy at 2 s.
        let kit = Kit.takt1
        var a = Pattern(kit: kit)
        a.tracks[0].steps[0] = Step(velocity: 127) // kick
        var b = Pattern(kit: kit)
        b.tracks[1].steps[0] = Step(velocity: 127) // snare

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-chain-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = try Bounce.render(patterns: [a, b], playOrder: [0, 1], kit: kit,
                                        tempoBPM: 120, swingPercent: 50,
                                        cycles: 1, tailSeconds: 0.2, to: url)
        XCTAssertEqual(seconds, 4.2, accuracy: 1e-9) // two 2 s loops + tail

        XCTAssertGreaterThan(try rms(of: url, fromSecond: 0.0, toSecond: 0.2), 0.05,
                             "kick must open slot A")
        XCTAssertLessThan(try rms(of: url, fromSecond: 1.2, toSecond: 1.9), 0.001,
                          "late slot A must be silent")
        XCTAssertGreaterThan(try rms(of: url, fromSecond: 2.0, toSecond: 2.2), 0.02,
                             "snare must open slot B")
    }

    func testM4AExportRendersReadableAudio() throws {
        let seed = Seeds.techno
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-m4a-test-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = try Bounce.render(pattern: seed.pattern(kit: .takt1), kit: .takt1,
                                        tempoBPM: seed.tempoBPM,
                                        swingPercent: seed.swingPercent,
                                        loops: 2, tailSeconds: 0, to: url, format: .m4a)

        let file = try AVAudioFile(forReading: url)
        let decodedSeconds = Double(file.length) / file.processingFormat.sampleRate
        // AAC adds priming/remainder frames; a quarter second of tolerance
        // is far beyond what the encoder pads.
        XCTAssertEqual(decodedSeconds, seconds, accuracy: 0.25)
        XCTAssertGreaterThan(try rms(of: url), 0.02)
    }

    func testChokeShortensOpenHat() throws {
        // Pattern A: lone open hat on step 0. Pattern B: same, plus a closed
        // hat on step 2. The open-hat tail energy after the closed hat must
        // drop in B.
        let kit = Kit.takt1
        var lone = Pattern(kit: kit)
        let ohatIndex = kit.voices.firstIndex { $0.id == "ohat" }!
        let chatIndex = kit.voices.firstIndex { $0.id == "chat" }!
        lone.tracks[ohatIndex].steps[0] = Step(velocity: 127)

        var choked = lone
        choked.tracks[chatIndex].steps[2] = Step(velocity: 1) // barely audible chat, still chokes

        let tempo = 120.0
        let urlA = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-choke-a-\(UUID().uuidString).wav")
        let urlB = FileManager.default.temporaryDirectory
            .appendingPathComponent("takt-choke-b-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        try Bounce.render(pattern: lone, kit: kit, tempoBPM: tempo, swingPercent: 50,
                          loops: 1, to: urlA)
        try Bounce.render(pattern: choked, kit: kit, tempoBPM: tempo, swingPercent: 50,
                          loops: 1, to: urlB)

        // Steps are 0.125 s at 120 BPM; the chat lands at 0.25 s and its own
        // burst dies by ~0.31 s. The open hat decays exponentially, so the
        // absolute tail level is tiny; what matters is the ratio.
        let tailA = try rms(of: urlA, fromSecond: 0.31, toSecond: 0.43)
        let tailB = try rms(of: urlB, fromSecond: 0.31, toSecond: 0.43)
        XCTAssertGreaterThan(tailA, 1e-4, "unchoked open hat should still ring")
        XCTAssertLessThan(tailB, tailA / 3, "choke must cut the open-hat tail")
    }
}
