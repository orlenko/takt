import AVFoundation
import Darwin
import TaktCore

/// The immutable snapshot the scheduler queue owns. UI edits send a fresh
/// value copy; the scheduler never reads shared mutable state (SPEC.md
/// concurrency contract).
///
/// `playOrder` is the looped chain of pattern indices: `[0]` loops slot A,
/// `[0, 1]` alternates A → B, `[0, 0, 1]` plays A twice then B.
public struct SequencerState: Sendable {
    public var kit: Kit
    public var patterns: [TaktCore.Pattern]
    public var playOrder: [Int]
    public var tempoBPM: Double
    public var swingPercent: Double

    public init(kit: Kit = .takt1, patterns: [TaktCore.Pattern], playOrder: [Int],
                tempoBPM: Double, swingPercent: Double) {
        self.kit = kit
        self.patterns = patterns
        self.playOrder = playOrder.isEmpty ? [0] : playOrder
        self.tempoBPM = tempoBPM
        self.swingPercent = swingPercent
    }

    public init(kit: Kit = .takt1, pattern: TaktCore.Pattern,
                tempoBPM: Double, swingPercent: Double) {
        self.init(kit: kit, patterns: [pattern], playOrder: [0],
                  tempoBPM: tempoBPM, swingPercent: swingPercent)
    }
}

/// Lookahead sequencer: a 25 ms timer on a serial queue schedules every hit
/// inside the next 120 ms window, anchored to host time. The same model as
/// the design mock's Web Audio scheduler.
public final class Sequencer {
    public static let lookaheadSeconds = 0.12
    private static let timerInterval = DispatchTimeInterval.milliseconds(25)

    private let queue = DispatchQueue(label: "takt.sequencer", qos: .userInteractive)
    private let graph: DrumGraph
    private var state: SequencerState
    private var timer: DispatchSourceTimer?
    private var stepIndex = 0
    private var orderPos = 0
    private var nextTime: Double = 0 // host-clock seconds
    private var cuedOrder: (order: [Int], startAt: Int)?

    /// Called on the sequencer queue for every scheduled step with
    /// (patternIndex, orderPos, step, hostSeconds when it sounds). Hop to
    /// main for UI.
    public var onStep: (@Sendable (Int, Int, Int, Double) -> Void)?

    /// Called on the sequencer queue when a cued play order takes effect at
    /// a pattern boundary (hardware-style quantized switching).
    public var onOrderChange: (@Sendable ([Int]) -> Void)?

    public private(set) var isPlaying = false

    public init(graph: DrumGraph, state: SequencerState) {
        self.graph = graph
        self.state = state
    }

    deinit { timer?.cancel() }

    public static func hostSecondsNow() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    /// Push a fresh snapshot; picked up within the scheduling horizon.
    /// Content changes (cells, tempo, swing, mutes) belong here. Play-order
    /// changes while playing should go through `cueOrder` instead, so they
    /// land on the pattern boundary.
    public func update(_ newState: SequencerState) {
        queue.async { self.state = newState }
    }

    /// Cue a play order to take effect when the current pattern finishes
    /// (hardware tradition: select sloppy, land tight). Pass nil to cancel.
    /// `startAt` is where in the new order playback resumes — song edits use
    /// it to keep the arrangement position instead of restarting at the top;
    /// later wraps still return to position 0.
    public func cueOrder(_ order: [Int]?, startAt: Int = 0) {
        queue.async { self.cuedOrder = order.map { ($0, startAt) } }
    }

    public func start() {
        guard !isPlaying else { return }
        isPlaying = true
        queue.async {
            self.stepIndex = 0
            self.orderPos = 0
            self.cuedOrder = nil
            self.nextTime = Self.hostSecondsNow() + 0.06
            self.scheduleWindow()
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.timerInterval, repeating: Self.timerInterval,
                   leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.scheduleWindow() }
        t.resume()
        timer = t
    }

    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        timer?.cancel()
        timer = nil
        graph.reset() // kill ringing tails and not-yet-sounded scheduled hits
    }

    private func scheduleWindow() {
        let horizon = Self.hostSecondsNow() + Self.lookaheadSeconds
        while nextTime < horizon {
            let s = state
            guard !s.patterns.isEmpty, !s.playOrder.isEmpty else { return }

            // A fresh snapshot may have fewer patterns or a shorter chain;
            // re-clamp our position instead of trusting stale indices.
            if orderPos >= s.playOrder.count { orderPos = 0 }
            let patternIndex = s.patterns.indices.contains(s.playOrder[orderPos])
                ? s.playOrder[orderPos] : 0
            let pattern = s.patterns[patternIndex]
            guard pattern.stepCount > 0 else { return }
            if stepIndex >= pattern.stepCount {
                wrapPattern()
                continue
            }
            let step = stepIndex

            for (i, track) in pattern.tracks.enumerated() {
                guard track.steps.indices.contains(step) else { continue }
                let hit = track.steps[step]
                guard hit.isOn, pattern.isAudible(trackIndex: i) else { continue }
                let choke = ChokeMath.limit(kit: s.kit, pattern: pattern, trackIndex: i,
                                            step: step, tempoBPM: s.tempoBPM,
                                            swingPercent: s.swingPercent)
                let time = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: nextTime))
                graph.trigger(voiceID: track.voiceID, gain: hit.gain * track.level,
                              at: time, maxDuration: choke)
            }

            onStep?(patternIndex, orderPos, step, nextTime)
            nextTime += Timing.stepDuration(step: step, tempoBPM: s.tempoBPM,
                                            swingPercent: s.swingPercent)
            stepIndex += 1
            if stepIndex >= pattern.stepCount {
                wrapPattern()
            }
        }
    }

    /// Pattern boundary: apply a pending cue, or walk the chain.
    private func wrapPattern() {
        stepIndex = 0
        if let cued = cuedOrder {
            cuedOrder = nil
            state.playOrder = cued.order.isEmpty ? [0] : cued.order
            orderPos = cued.startAt.clamped(to: 0...(state.playOrder.count - 1))
            onOrderChange?(state.playOrder)
        } else {
            orderPos = (orderPos + 1) % max(1, state.playOrder.count)
        }
    }
}
