import AppKit
import AVFoundation
import Combine
import SwiftUI
import TaktAudio
import TaktCore
import TaktMIDI
import UniformTypeIdentifiers

@MainActor
public final class AppModel: ObservableObject {
    let kit = Kit.takt1

    @Published var project: Project
    @Published var isPlaying = false
    @Published var displayedStep: Int?
    @Published var activeSeedName: String?
    @Published var engineError: String?
    @Published var midiSourceNames: [String] = []
    @Published var isExporting = false
    /// Pattern slot currently sounding (nil when stopped).
    @Published var playingSlot: Int?
    /// true: loop the whole chain of slots in order; false: loop the editing slot.
    @Published var loopChain = true

    static let maxSlots = 8
    @Published var themeID: ThemeID {
        didSet {
            UserDefaults.standard.set(themeID.rawValue, forKey: "themeID")
            rebuildPalettes()
        }
    }

    private(set) var theme: Theme
    private(set) var voicePalettes: [VoiceColors] = []

    /// Cell/dot trigger flashes keyed by track (and step for cells), storing
    /// the host-clock second the flash began. The grid view reads these.
    private(set) var cellFlashes: [FlashKey: Double] = [:]
    private(set) var dotFlashes: [Int: Double] = [:]
    static let flashDuration = 0.11

    struct FlashKey: Hashable {
        let track: Int
        let step: Int
    }

    /// Set by the grid view so the model can request redraws.
    var gridNeedsDisplay: (() -> Void)?

    private var engine: AVAudioEngine?
    private var graph: DrumGraph?
    private var sequencer: Sequencer?
    private var midi: MIDIInput?
    private var pendingSteps: [(slot: Int, step: Int, time: Double)] = []
    private var displayTimer: Timer?
    private var keyMonitor: Any?
    private static let jamKeys = Array("asdfghjk")

    public init() {
        let seed = Seeds.house
        self.project = Project(tempoBPM: seed.tempoBPM, swingPercent: seed.swingPercent,
                               patterns: [seed.pattern(kit: .takt1)])
        self.activeSeedName = seed.name
        let stored = UserDefaults.standard.string(forKey: "themeID")
        let id = stored.flatMap(ThemeID.init(rawValue:)) ?? .candy
        self.themeID = id
        self.theme = Theme.theme(id)
        rebuildPalettes()
        installKeyMonitor()
        startMIDI()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    private func rebuildPalettes() {
        theme = Theme.theme(themeID)
        voicePalettes = kit.voices.map { theme.voiceColors(hue: $0.hueDegrees) }
        gridNeedsDisplay?()
    }

    // MARK: - Transport

    func togglePlay() {
        isPlaying ? stop() : play()
    }

    func play() {
        do {
            let sequencer = try ensureEngine()
            pendingSteps.removeAll()
            sequencer.update(currentState())
            sequencer.start()
            isPlaying = true
            startDisplayTimer()
        } catch {
            engineError = "\(error)"
        }
    }

    func stop() {
        sequencer?.stop()
        isPlaying = false
        pendingSteps.removeAll()
        displayedStep = nil
        playingSlot = nil
        gridNeedsDisplay?()
    }

    func setTempo(_ bpm: Double) {
        project.tempoBPM = bpm.clamped(to: Project.tempoRange)
        pushState()
    }

    func setSwing(_ percent: Double) {
        project.swingPercent = percent.clamped(to: Project.swingRange)
        pushState()
    }

    // MARK: - Editing

    func setCell(track: Int, step: Int, velocity: UInt8) {
        guard project.currentPattern.tracks.indices.contains(track),
              project.currentPattern.tracks[track].steps.indices.contains(step) else { return }
        project.currentPattern.tracks[track].steps[step].velocity = velocity
        activeSeedName = nil
        pushState()
        gridNeedsDisplay?()
    }

    /// Left click: toggle off ↔ normal. Returns the velocity to paint with
    /// while dragging.
    func toggleCell(track: Int, step: Int) -> UInt8 {
        let current = project.currentPattern.tracks[track].steps[step].velocity
        let value: UInt8 = current > 0 ? 0 : VelocityLevel.normal.midi
        setCell(track: track, step: step, velocity: value)
        return value
    }

    /// Right click: off → accent → soft → normal → accent (mock semantics).
    func cycleVelocity(track: Int, step: Int) {
        let current = project.currentPattern.tracks[track].steps[step].velocity
        let next: UInt8 = switch VelocityLevel(nearest: current) {
        case .off: VelocityLevel.accent.midi
        case .accent: VelocityLevel.soft.midi
        case .soft: VelocityLevel.normal.midi
        case .normal: VelocityLevel.accent.midi
        }
        setCell(track: track, step: step, velocity: next)
    }

    func toggleMute(track: Int) {
        project.currentPattern.tracks[track].isMuted.toggle()
        pushState()
        gridNeedsDisplay?()
    }

    func toggleSolo(track: Int) {
        project.currentPattern.tracks[track].isSoloed.toggle()
        pushState()
        gridNeedsDisplay?()
    }

    func loadSeed(_ seed: Seed) {
        project.currentPattern = seed.pattern(kit: kit)
        project.tempoBPM = seed.tempoBPM
        project.swingPercent = seed.swingPercent
        activeSeedName = seed.name
        pushState()
        gridNeedsDisplay?()
    }

    func clearPattern() {
        project.currentPattern = Pattern(kit: kit)
        activeSeedName = nil
        pushState()
        gridNeedsDisplay?()
    }

    // MARK: - Pattern slots

    var editingSlot: Int { project.currentPatternIndex }

    func selectSlot(_ index: Int) {
        guard project.patterns.indices.contains(index) else { return }
        project.currentPatternIndex = index
        activeSeedName = nil
        pushState() // play order changes in slot-loop mode
        gridNeedsDisplay?()
    }

    /// Duplicates the current slot into a new slot right after it and
    /// selects the copy: the "add another block like this one" gesture.
    func duplicateSlot() {
        guard project.patterns.count < Self.maxSlots else { return }
        let copy = project.currentPattern
        project.patterns.insert(copy, at: project.currentPatternIndex + 1)
        project.currentPatternIndex += 1
        pushState()
        gridNeedsDisplay?()
    }

    /// Adds an empty slot at the end and selects it.
    func addEmptySlot() {
        guard project.patterns.count < Self.maxSlots else { return }
        project.patterns.append(Pattern(kit: kit))
        project.currentPatternIndex = project.patterns.count - 1
        activeSeedName = nil
        pushState()
        gridNeedsDisplay?()
    }

    func deleteSlot(_ index: Int) {
        guard project.patterns.count > 1,
              project.patterns.indices.contains(index) else { return }
        project.patterns.remove(at: index)
        if project.currentPatternIndex >= project.patterns.count {
            project.currentPatternIndex = project.patterns.count - 1
        }
        pushState()
        gridNeedsDisplay?()
    }

    func setLoopChain(_ chain: Bool) {
        loopChain = chain
        pushState()
    }

    static func slotName(_ index: Int) -> String {
        let letters = Array("ABCDEFGH")
        return index < letters.count ? String(letters[index]) : "\(index + 1)"
    }

    private var playOrder: [Int] {
        loopChain ? Array(project.patterns.indices) : [project.currentPatternIndex]
    }

    // MARK: - Export

    /// WAV: fixed 4 loops + tail, for DAWs. M4A: `minutes` of seamless-ish
    /// looped beat (no tail), for phones and jogging playlists.
    func exportAudio(format: AudioExportFormat, minutes: Double? = nil) {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .wav ? .wav : .mpeg4Audio]
        panel.nameFieldStringValue = defaultExportName(format: format, minutes: minutes)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let patterns = project.patterns
        let order = playOrder
        let tempo = project.tempoBPM
        let swing = project.swingPercent
        let kit = kit
        let chainDuration = order.reduce(0.0) { acc, i in
            acc + Timing.loopDuration(stepCount: patterns[i].stepCount, tempoBPM: tempo)
        }
        let cycles = minutes.map { max(1, Int(($0 * 60 / chainDuration).rounded(.up))) } ?? 4
        let tail = format == .wav ? 0.5 : 0.0

        isExporting = true
        Task { @MainActor [weak self] in
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try Bounce.render(patterns: patterns, playOrder: order, kit: kit,
                                      tempoBPM: tempo, swingPercent: swing, cycles: cycles,
                                      tailSeconds: tail, to: url, format: format)
                }.value
                self?.isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self?.isExporting = false
                self?.engineError = "\(error)"
            }
        }
    }

    private func defaultExportName(format: AudioExportFormat, minutes: Double?) -> String {
        let base = (activeSeedName ?? project.currentPattern.name)
            .lowercased().replacingOccurrences(of: " ", with: "-")
        let bpm = Int(project.tempoBPM.rounded())
        let suffix = minutes.map { "-\(Int($0))min" } ?? ""
        return "takt-\(base)-\(bpm)bpm\(suffix).\(format.fileExtension)"
    }

    // MARK: - MIDI

    private func startMIDI() {
        let midi = MIDIInput()
        midi.onNoteOn = { [weak self] note, velocity in
            DispatchQueue.main.async {
                self?.handleMIDINote(note: note, velocity: velocity)
            }
        }
        midi.onSourcesChanged = { [weak self] names in
            DispatchQueue.main.async {
                self?.midiSourceNames = names
            }
        }
        do {
            try midi.start()
            self.midi = midi
        } catch {
            engineError = "\(error)"
        }
    }

    private func handleMIDINote(note: UInt8, velocity: UInt8) {
        let voiceID = project.midiOverrides[note] ?? kit.voice(gmNote: note)?.id
        guard let voiceID,
              let index = kit.voices.firstIndex(where: { $0.id == voiceID }) else { return }
        do {
            _ = try ensureEngine()
        } catch {
            engineError = "\(error)"
            return
        }
        graph?.trigger(voiceID: voiceID, gain: Float(velocity) / 127, at: nil)
        dotFlashes[index] = Sequencer.hostSecondsNow()
        startDisplayTimer()
        gridNeedsDisplay?()
    }

    // MARK: - Jam

    func jam(voiceIndex: Int) {
        guard kit.voices.indices.contains(voiceIndex) else { return }
        do {
            _ = try ensureEngine()
        } catch {
            engineError = "\(error)"
            return
        }
        graph?.trigger(voiceID: kit.voices[voiceIndex].id, gain: 1, at: nil)
        dotFlashes[voiceIndex] = Sequencer.hostSecondsNow()
        startDisplayTimer()
        gridNeedsDisplay?()
    }

    // MARK: - Engine plumbing

    private func currentState() -> SequencerState {
        SequencerState(patterns: project.patterns,
                       playOrder: playOrder,
                       tempoBPM: project.tempoBPM,
                       swingPercent: project.swingPercent)
    }

    private func pushState() {
        sequencer?.update(currentState())
    }

    private func ensureEngine() throws -> Sequencer {
        if let sequencer { return sequencer }
        let engine = AVAudioEngine()
        let buffers = try KitBuffers(kit: kit)
        let graph = DrumGraph(engine: engine, buffers: buffers)
        try engine.start()
        graph.startPlayers()
        let sequencer = Sequencer(graph: graph, kit: kit, state: currentState())
        sequencer.onStep = { [weak self] slot, step, time in
            DispatchQueue.main.async {
                self?.pendingSteps.append((slot, step, time))
            }
        }
        self.engine = engine
        self.graph = graph
        self.sequencer = sequencer
        return sequencer
    }

    // MARK: - Playhead / flash display loop

    private func startDisplayTimer() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.displayTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func displayTick() {
        let now = Sequencer.hostSecondsNow()
        var newStep: Int?
        var newSlot: Int?
        while let first = pendingSteps.first, first.time <= now {
            newStep = first.step
            newSlot = first.slot
            pendingSteps.removeFirst()
            if now - first.time < 0.08, project.patterns.indices.contains(first.slot) {
                let pattern = project.patterns[first.slot]
                for (i, track) in pattern.tracks.enumerated()
                where track.steps.indices.contains(first.step)
                    && track.steps[first.step].isOn
                    && pattern.isAudible(trackIndex: i) {
                    // Cell flashes only make sense on the pattern being shown.
                    if first.slot == editingSlot {
                        cellFlashes[FlashKey(track: i, step: first.step)] = first.time
                    }
                    dotFlashes[i] = first.time
                }
            }
        }
        cellFlashes = cellFlashes.filter { now - $0.value < Self.flashDuration }
        dotFlashes = dotFlashes.filter { now - $0.value < Self.flashDuration }

        var dirty = false
        if let newSlot, newSlot != playingSlot {
            playingSlot = newSlot
            dirty = true
        }
        if let newStep, newStep != displayedStep {
            displayedStep = newStep
            dirty = true
        }
        if !cellFlashes.isEmpty || !dotFlashes.isEmpty { dirty = true }

        if dirty { gridNeedsDisplay?() }

        if !isPlaying && cellFlashes.isEmpty && dotFlashes.isEmpty {
            displayTimer?.invalidate()
            displayTimer = nil
        }
    }

    // MARK: - QWERTY

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.option),
                  !event.isARepeat else { return event }
            if event.keyCode == 49 { // space
                self.togglePlay()
                return nil
            }
            if let ch = event.charactersIgnoringModifiers?.lowercased().first,
               let index = Self.jamKeys.firstIndex(of: ch) {
                self.jam(voiceIndex: index)
                return nil
            }
            return event
        }
    }
}
