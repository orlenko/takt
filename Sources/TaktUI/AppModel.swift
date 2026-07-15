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
    var kit: Kit { Kit.kit(id: project.kitID) ?? .takt1 }

    @Published var project: Project
    @Published var isPlaying = false
    @Published var displayedStep: Int?
    @Published var activeSeedName: String?
    @Published var engineError: String?
    @Published var midiSourceNames: [String] = []
    @Published public private(set) var isExporting = false
    /// Pattern slot currently sounding (nil when stopped).
    @Published var playingSlot: Int?
    /// Slot cued to take over at the next pattern boundary (nil when none).
    @Published var cuedSlot: Int?

    enum LoopMode: String, CaseIterable {
        case chain // loop every slot in order
        case slot  // loop the slot being edited
        case song  // follow the song arrangement
    }
    @Published var loopMode: LoopMode = .chain

    /// The play order currently sounding; cued changes replace it when they
    /// land at a boundary (see Sequencer.onOrderChange).
    private var activePlayOrder: [Int] = [0]

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

    // MARK: - Undo

    /// The undo unit. Project alone is not enough: loopMode and the seed
    /// label live outside it but are coupled to it (emptying the song
    /// force-flips song → chain), and restoring one without the others
    /// would land in states the user never inhabited.
    struct Snapshot {
        let project: Project
        let loopMode: LoopMode
        let seedName: String?
    }

    static let maxUndoDepth = 100
    @Published private var undoStack: [Snapshot] = []
    @Published private var redoStack: [Snapshot] = []
    private var inUndoGesture = false

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() -> Snapshot {
        Snapshot(project: project, loopMode: loopMode, seedName: activeSeedName)
    }

    /// Called before every mutation. Continuous gestures (drag-paint, BPM
    /// drag, swing slide) wrap themselves in begin/endUndoGesture so the
    /// whole stroke coalesces into one undo step.
    private func recordUndo() {
        guard !inUndoGesture else { return }
        undoStack.append(snapshot())
        if undoStack.count > Self.maxUndoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func beginUndoGesture() {
        recordUndo()
        inUndoGesture = true
    }

    func endUndoGesture() {
        inUndoGesture = false
    }

    public func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(snap)
    }

    public func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(snap)
    }

    /// Restoring a snapshot replays side effects (kit buffers) and treats
    /// any structural difference like slot add/remove: resync the play
    /// order immediately, cancel cues. Undo never cues — ⌘Z scheduling a
    /// pattern switch at the next boundary would be baffling — and never
    /// stops playback.
    private func apply(_ snap: Snapshot) {
        let kitChanged = snap.project.kitID != project.kitID
        project = snap.project
        loopMode = snap.loopMode
        activeSeedName = snap.seedName
        if kitChanged { refreshKitBuffers() }
        cuedSlot = nil
        sequencer?.cueOrder(nil)
        activePlayOrder = restingOrder()
        pushState()
        gridNeedsDisplay?()
    }

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
            activePlayOrder = restingOrder()
            cuedSlot = nil
            sequencer.cueOrder(nil)
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
        cuedSlot = nil
        gridNeedsDisplay?()
    }

    func setTempo(_ bpm: Double) {
        let clamped = bpm.clamped(to: Project.tempoRange)
        guard clamped != project.tempoBPM else { return }
        recordUndo()
        project.tempoBPM = clamped
        pushState()
    }

    func setSwing(_ percent: Double) {
        let clamped = percent.clamped(to: Project.swingRange)
        guard clamped != project.swingPercent else { return }
        recordUndo()
        project.swingPercent = clamped
        pushState()
    }

    // MARK: - Editing

    func setCell(track: Int, step: Int, velocity: UInt8) {
        guard project.currentPattern.tracks.indices.contains(track),
              project.currentPattern.tracks[track].steps.indices.contains(step) else { return }
        recordUndo()
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
        recordUndo()
        project.currentPattern.tracks[track].isMuted.toggle()
        pushState()
        gridNeedsDisplay?()
    }

    func toggleSolo(track: Int) {
        recordUndo()
        project.currentPattern.tracks[track].isSoloed.toggle()
        pushState()
        gridNeedsDisplay?()
    }

    /// A seed retunes the whole instrument: bar content plus tempo and
    /// swing (Decision A — project-scoped, one click from a groove).
    func loadSeed(_ seed: Seed) {
        recordUndo()
        project.currentPattern = seed.pattern(kit: kit)
        project.tempoBPM = seed.tempoBPM
        project.swingPercent = seed.swingPercent
        activeSeedName = seed.name
        pushState()
        gridNeedsDisplay?()
    }

    /// Verb law: Clear empties the content, the container stays.
    func clearPattern(at index: Int) {
        guard project.patterns.indices.contains(index) else { return }
        recordUndo()
        project.patterns[index] = Pattern(kit: kit)
        if index == editingSlot { activeSeedName = nil }
        pushState()
        gridNeedsDisplay?()
    }

    /// The "clear A" chip: empties the slot being edited.
    func clearPattern() {
        clearPattern(at: editingSlot)
    }

    /// Lane menu Clear: silences one voice's row in the editing pattern.
    func clearLane(_ track: Int) {
        guard project.currentPattern.tracks.indices.contains(track) else { return }
        recordUndo()
        let count = project.currentPattern.tracks[track].steps.count
        project.currentPattern.tracks[track].steps = Array(repeating: Step(), count: count)
        activeSeedName = nil
        pushState()
        gridNeedsDisplay?()
    }

    // MARK: - Pattern slots

    var editingSlot: Int { project.currentPatternIndex }

    /// Hardware tradition: what you select is what plays next. While playing,
    /// selecting a slot shows it for editing immediately and cues it to take
    /// over at the pattern boundary; selecting the sounding slot cancels a
    /// pending cue. While stopped, selection is just selection. In song mode
    /// the song drives playback, so slot clicks only choose what to edit.
    func selectSlot(_ index: Int) {
        guard project.patterns.indices.contains(index) else { return }
        project.currentPatternIndex = index
        activeSeedName = nil
        if isPlaying, loopMode != .song {
            if index == playingSlot {
                cuedSlot = nil
                sequencer?.cueOrder(nil)
            } else {
                cuedSlot = index
                sequencer?.cueOrder(cuedOrder(startingAt: index))
            }
            // content refresh below; play order untouched until the cue lands
        }
        pushState()
        gridNeedsDisplay?()
    }

    /// Play order when starting fresh (stopped → play).
    private func restingOrder() -> [Int] {
        switch loopMode {
        case .chain: Array(project.patterns.indices)
        case .slot: [editingSlot]
        case .song: project.songOrder.isEmpty ? [editingSlot] : project.songOrder
        }
    }

    /// Play order for a cue: slot mode traps the slot; chain mode continues
    /// the chain from the cued slot onward. (Song mode never cues per slot.)
    private func cuedOrder(startingAt slot: Int) -> [Int] {
        guard loopMode == .chain else { return [slot] }
        let count = project.patterns.count
        return (0..<count).map { (slot + $0) % count }
    }

    /// Inserts a copy of `index` right after it. Menu verbs never move
    /// selection (grammar L4); the ⧉ button selects the copy because it is
    /// the "add another block like this one" gesture, not a menu verb.
    private func insertDuplicate(of index: Int, selectCopy: Bool) {
        guard project.patterns.count < Self.maxSlots,
              project.patterns.indices.contains(index) else { return }
        recordUndo()
        project.patterns.insert(project.patterns[index], at: index + 1)
        if selectCopy {
            project.currentPatternIndex = index + 1
        } else if project.currentPatternIndex > index {
            project.currentPatternIndex += 1
        }
        project.song = project.song.map {
            $0.slot > index ? SongEntry(slot: $0.slot + 1, repeats: $0.repeats) : $0
        }
        resyncAfterStructureChange()
    }

    /// ⧉ button: duplicate the editing slot and select the copy.
    func duplicateSlot() {
        insertDuplicate(of: editingSlot, selectCopy: true)
    }

    /// Slot menu Duplicate: copy alongside, selection untouched.
    func duplicateSlot(at index: Int) {
        insertDuplicate(of: index, selectCopy: false)
    }

    /// Adds an empty slot at the end and selects it.
    func addEmptySlot() {
        guard project.patterns.count < Self.maxSlots else { return }
        recordUndo()
        project.patterns.append(Pattern(kit: kit))
        project.currentPatternIndex = project.patterns.count - 1
        activeSeedName = nil
        resyncAfterStructureChange()
    }

    /// Verb law: Remove takes the container out.
    func removeSlot(at index: Int) {
        guard project.patterns.count > 1,
              project.patterns.indices.contains(index) else { return }
        recordUndo()
        project.patterns.remove(at: index)
        if index < project.currentPatternIndex {
            project.currentPatternIndex -= 1
        } else if project.currentPatternIndex >= project.patterns.count {
            project.currentPatternIndex = project.patterns.count - 1
        }
        project.song = project.song.compactMap {
            if $0.slot == index { return nil }
            return $0.slot > index ? SongEntry(slot: $0.slot - 1, repeats: $0.repeats) : $0
        }
        if project.song.isEmpty, loopMode == .song { loopMode = .chain }
        resyncAfterStructureChange()
    }

    /// Slot menu Move Left/Right: swaps neighbors; song entries and the
    /// selection follow their patterns.
    func moveSlot(at index: Int, by delta: Int) {
        let target = index + delta
        guard project.patterns.indices.contains(index),
              project.patterns.indices.contains(target) else { return }
        recordUndo()
        project.patterns.swapAt(index, target)
        project.song = project.song.map { entry in
            if entry.slot == index { return SongEntry(slot: target, repeats: entry.repeats) }
            if entry.slot == target { return SongEntry(slot: index, repeats: entry.repeats) }
            return entry
        }
        if project.currentPatternIndex == index {
            project.currentPatternIndex = target
        } else if project.currentPatternIndex == target {
            project.currentPatternIndex = index
        }
        resyncAfterStructureChange()
    }

    /// Adding/removing slots shifts indices, so a pending cue and the active
    /// order can go stale; rebuild both immediately (the one structural case
    /// that does not wait for the boundary).
    private func resyncAfterStructureChange() {
        cuedSlot = nil
        sequencer?.cueOrder(nil)
        activePlayOrder = restingOrder()
        pushState()
        gridNeedsDisplay?()
    }

    func setLoopMode(_ mode: LoopMode) {
        guard loopMode != mode else { return }
        loopMode = mode
        cueRestingOrder()
    }

    /// Land the current mode's play order at the pattern boundary (playing)
    /// or just make it the next start order (stopped).
    private func cueRestingOrder() {
        guard isPlaying else {
            pushState()
            return
        }
        let order: [Int] = switch loopMode {
        case .chain: cuedOrder(startingAt: playingSlot ?? editingSlot)
        case .slot: [editingSlot]
        case .song: restingOrder()
        }
        sequencer?.cueOrder(order)
        cuedSlot = order.first == playingSlot ? nil : order.first
    }

    // MARK: - Song

    static let maxSongEntries = 16
    /// The click ladder for repeats: songs are shaped in powers of two, so
    /// ×8 is three clicks away, not seven (Decision B).
    static let repeatSteps = [1, 2, 4, 8, 16]

    /// The "+ A" chip: appends the slot being edited to the song.
    func appendSongEntry() {
        guard project.song.count < Self.maxSongEntries else { return }
        recordUndo()
        project.song.append(SongEntry(slot: editingSlot))
        songDidChange()
    }

    /// Left click on a song chip: next power of two, wrapping past ×16.
    /// ⌥-click walks the ladder backwards. The one documented exception to
    /// "clicks don't mutate" — repeats are a value, and this is its gesture.
    func cycleSongRepeats(at index: Int, reverse: Bool = false) {
        guard project.song.indices.contains(index) else { return }
        recordUndo()
        let current = project.song[index].repeats
        project.song[index].repeats = reverse
            ? Self.repeatSteps.last { $0 < current } ?? Self.repeatSteps.last!
            : Self.repeatSteps.first { $0 > current } ?? Self.repeatSteps.first!
        songDidChange()
    }

    /// Menu direct-set: declarative, no incremental walking.
    func setSongRepeats(at index: Int, to repeats: Int) {
        guard project.song.indices.contains(index),
              project.song[index].repeats != repeats else { return }
        recordUndo()
        project.song[index].repeats = repeats.clamped(to: SongEntry.repeatsRange)
        songDidChange()
    }

    func duplicateSongEntry(at index: Int) {
        guard project.song.count < Self.maxSongEntries,
              project.song.indices.contains(index) else { return }
        recordUndo()
        project.song.insert(project.song[index], at: index + 1)
        songDidChange()
    }

    func removeSongEntry(at index: Int) {
        guard project.song.indices.contains(index) else { return }
        recordUndo()
        project.song.remove(at: index)
        if project.song.isEmpty, loopMode == .song {
            loopMode = .chain // nothing left to follow
            cueRestingOrder()
        } else {
            songDidChange()
        }
    }

    /// The "clear song" chip: empties the whole arrangement (⌘Z undoes).
    func clearSong() {
        guard !project.song.isEmpty else { return }
        recordUndo()
        project.song.removeAll()
        if loopMode == .song {
            loopMode = .chain
            cueRestingOrder()
        } else {
            songDidChange()
        }
    }

    func moveSongEntry(at index: Int, by delta: Int) {
        let target = index + delta
        guard project.song.indices.contains(index),
              project.song.indices.contains(target) else { return }
        recordUndo()
        project.song.swapAt(index, target)
        songDidChange()
    }

    /// Song edits are structure changes: while the song is driving playback
    /// they land at the pattern boundary and restart the arrangement. In
    /// chain/slot modes they leave playback alone.
    private func songDidChange() {
        if isPlaying, loopMode == .song {
            cueRestingOrder()
        } else {
            pushState()
        }
    }

    // MARK: - Kits

    func selectKit(_ newKit: Kit) {
        guard newKit.id != project.kitID else { return }
        recordUndo()
        project.kitID = newKit.id
        refreshKitBuffers()
        pushState()
        gridNeedsDisplay?()
    }

    /// Point the running graph at the current kit's samples. No-op before
    /// the engine exists; the kit loads lazily with it.
    private func refreshKitBuffers() {
        guard let graph else { return }
        do {
            graph.setBuffers(try KitBuffers(kit: kit))
        } catch {
            engineError = "\(error)"
        }
    }

    static func slotName(_ index: Int) -> String {
        let letters = Array("ABCDEFGH")
        return index < letters.count ? String(letters[index]) : "\(index + 1)"
    }

    /// Order used for state pushes and exports: what is (or would be) sounding.
    private var playOrder: [Int] {
        isPlaying ? activePlayOrder : restingOrder()
    }

    // MARK: - Export

    /// WAV: `cycles` passes of the chain + tail, for DAWs. M4A: `minutes` of
    /// looped beat (no tail), for phones and jogging playlists.
    func exportAudio(format: AudioExportFormat, minutes: Double? = nil, cycles cyclesOverride: Int? = nil) {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .wav ? .wav : .mpeg4Audio]
        panel.nameFieldStringValue = defaultExportName(ext: format.fileExtension, minutes: minutes)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let patterns = project.patterns
        let order = playOrder
        let tempo = project.tempoBPM
        let swing = project.swingPercent
        let kit = kit
        let chainDuration = order.reduce(0.0) { acc, i in
            acc + Timing.loopDuration(stepCount: patterns[i].stepCount, tempoBPM: tempo)
        }
        let cycles = cyclesOverride
            ?? minutes.map { max(1, Int(($0 * 60 / chainDuration).rounded(.up))) }
            ?? 1
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

    private func defaultExportName(ext: String, minutes: Double? = nil) -> String {
        let base = (activeSeedName ?? project.currentPattern.name)
            .lowercased().replacingOccurrences(of: " ", with: "-")
        let bpm = Int(project.tempoBPM.rounded())
        let suffix = minutes.map { "-\(Int($0))min" } ?? ""
        return "takt-\(base)-\(bpm)bpm\(suffix).\(ext)"
    }

    /// File-menu wrappers: export is a document verb, so it lives on the
    /// File menu (canonical, with shortcuts); the status-bar chips remain
    /// the fast path.
    public func exportWAV(passes: Int) {
        exportAudio(format: .wav, cycles: passes)
    }

    public func exportJogMix(minutes: Double) {
        exportAudio(format: .m4a, minutes: minutes)
    }

    /// Standard MIDI File of one chain pass, following the loop mode.
    public func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = defaultExportName(ext: "mid")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = MIDIFile.data(patterns: project.patterns, playOrder: playOrder,
                                 kit: kit, tempoBPM: project.tempoBPM,
                                 swingPercent: project.swingPercent)
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            engineError = "\(error)"
        }
    }

    // MARK: - Documents (.takt)

    private static let taktType = UTType(filenameExtension: "takt", conformingTo: .json) ?? .json

    /// File › New: a fresh instrument. Undoable, like everything else.
    public func newProject() {
        stop()
        recordUndo()
        project = Project(patterns: [Pattern(kit: .takt1)])
        loopMode = .chain
        activeSeedName = nil
        refreshKitBuffers()
        pushState()
        gridNeedsDisplay?()
    }

    public func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.taktType]
        panel.allowsOtherFileTypes = false
        panel.nameFieldStringValue = defaultExportName(ext: "takt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(project).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            engineError = "\(error)"
        }
    }

    public func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.taktType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
            guard !loaded.patterns.isEmpty else { throw TaktAudioError.renderFailed("empty project") }
            stop()
            recordUndo() // "undo open" restores the previous session
            project = loaded
            project.currentPatternIndex = min(project.currentPatternIndex,
                                              project.patterns.count - 1)
            if Kit.kit(id: project.kitID) == nil { project.kitID = Kit.takt1.id }
            refreshKitBuffers()
            activeSeedName = nil
            pushState()
            gridNeedsDisplay?()
        } catch {
            engineError = "could not open: \(error)"
        }
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
        SequencerState(kit: kit,
                       patterns: project.patterns,
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
        let sequencer = Sequencer(graph: graph, state: currentState())
        sequencer.onStep = { [weak self] slot, step, time in
            DispatchQueue.main.async {
                self?.pendingSteps.append((slot, step, time))
            }
        }
        sequencer.onOrderChange = { [weak self] order in
            DispatchQueue.main.async {
                self?.activePlayOrder = order
                self?.cuedSlot = nil
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
