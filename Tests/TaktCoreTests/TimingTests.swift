import XCTest
@testable import TaktCore

final class TimingTests: XCTestCase {
    func testStraightTimingAt120() {
        // 120 BPM: a 16th is 0.125 s.
        XCTAssertEqual(Timing.sixteenth(tempoBPM: 120), 0.125, accuracy: 1e-12)
        for step in 0..<16 {
            XCTAssertEqual(Timing.stepTime(step: step, tempoBPM: 120, swingPercent: 50),
                           Double(step) * 0.125, accuracy: 1e-12, "step \(step)")
        }
        XCTAssertEqual(Timing.loopDuration(stepCount: 16, tempoBPM: 120), 2.0, accuracy: 1e-12)
    }

    func testTripletSwing() {
        // Swing 66.667%: the offbeat lands two-thirds into the pair.
        let swing = 200.0 / 3.0
        let pair = 0.25 // at 120 BPM
        XCTAssertEqual(Timing.stepTime(step: 1, tempoBPM: 120, swingPercent: swing),
                       pair * 2 / 3, accuracy: 1e-9)
        // Even steps are unaffected by swing.
        XCTAssertEqual(Timing.stepTime(step: 2, tempoBPM: 120, swingPercent: swing),
                       pair, accuracy: 1e-12)
    }

    func testDurationsSumToLoop() {
        for swing in [50.0, 54.0, 200.0 / 3.0, 75.0] {
            let total = (0..<16).reduce(0.0) { acc, step in
                acc + Timing.stepDuration(step: step, tempoBPM: 122, swingPercent: swing)
            }
            XCTAssertEqual(total, Timing.loopDuration(stepCount: 16, tempoBPM: 122),
                           accuracy: 1e-9, "swing \(swing)")
        }
    }

    func testStepTimeMatchesAccumulatedDurations() {
        // The absolute form (bounce/export) must agree with the incremental
        // form (live scheduler).
        let tempo = 96.0, swing = 61.0
        var acc = 0.0
        for step in 0..<16 {
            XCTAssertEqual(Timing.stepTime(step: step, tempoBPM: tempo, swingPercent: swing),
                           acc, accuracy: 1e-9, "step \(step)")
            acc += Timing.stepDuration(step: step, tempoBPM: tempo, swingPercent: swing)
        }
    }
}
