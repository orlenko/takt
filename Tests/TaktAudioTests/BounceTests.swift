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
