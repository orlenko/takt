import AppKit
import SwiftUI
import TaktCore

public struct ContentView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            TransportView(model: model)
            Rectangle().fill(theme.line.swiftUI).frame(height: 1)
            PatternBarView(model: model)
            Rectangle().fill(theme.line.swiftUI).frame(height: 1)
            SongBarView(model: model)
            Rectangle().fill(theme.line.swiftUI).frame(height: 1)
            GridView(model: model)
                .frame(minWidth: 1140, idealWidth: 1180,
                       minHeight: GridNSView.preferredHeight,
                       maxHeight: GridNSView.preferredHeight)
            Rectangle().fill(theme.line.swiftUI).frame(height: 1)
            StatusBarView(model: model)
        }
        .background(theme.surface.swiftUI)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - Transport

struct TransportView: View {
    @ObservedObject var model: AppModel
    @State private var dragStartTempo: Double?

    var body: some View {
        let theme = model.theme
        HStack(spacing: 16) {
            playButton
            loopChips
            Rectangle().fill(theme.line.swiftUI).frame(width: 1, height: 18)
            tempoControl
            beatLED
            swingControl
            Spacer(minLength: 12)
            seedChips
        }
        .padding(.leading, 84) // room for the traffic lights (hidden title bar)
        .padding(.trailing, 20)
        .padding(.vertical, 13)
        .background(theme.raised.swiftUI)
    }

    /// Loop mode lives next to play: it is a play-mode selector (the 909's
    /// pattern/song switch), not a property of any one row of chips.
    private var loopChips: some View {
        let theme = model.theme
        return HStack(spacing: 8) {
            Text("LOOP")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            Button("chain") { model.setLoopMode(.chain) }
                .buttonStyle(ChipStyle(theme: theme, active: model.loopMode == .chain))
                .help("Loop every slot in order")
            Button("slot") { model.setLoopMode(.slot) }
                .buttonStyle(ChipStyle(theme: theme, active: model.loopMode == .slot))
                .help("Loop only the slot being edited")
            Button("song") { model.setLoopMode(.song) }
                .buttonStyle(ChipStyle(theme: theme, active: model.loopMode == .song))
                .disabled(model.project.song.isEmpty)
                .help(model.project.song.isEmpty
                    ? "Build a song in the SONG row first"
                    : "Follow the song arrangement")
        }
    }

    private var playButton: some View {
        let theme = model.theme
        return Button(action: model.togglePlay) {
            Text(model.isPlaying ? "■" : "▶")
                .font(.system(size: 15, design: .monospaced).weight(.bold))
                .frame(width: 64, height: 34)
                .background(model.isPlaying ? theme.accent.swiftUI : theme.surface.swiftUI)
                .foregroundStyle(model.isPlaying ? theme.onAccent.swiftUI : theme.text.swiftUI)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke((model.isPlaying ? theme.accent : theme.line).swiftUI, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Stop" : "Play")
    }

    private var tempoControl: some View {
        let theme = model.theme
        return HStack(spacing: 8) {
            stepper("−") { model.setTempo(model.project.tempoBPM - 1) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(model.project.tempoBPM.rounded()))")
                    .font(.system(size: 24, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.text.swiftUI)
                    .frame(minWidth: 46, alignment: .trailing)
                Text("BPM")
                    .font(.system(size: 9, design: .monospaced).weight(.medium))
                    .kerning(1.2)
                    .foregroundStyle(theme.faint.swiftUI)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartTempo == nil {
                            dragStartTempo = model.project.tempoBPM
                            model.beginUndoGesture() // the whole drag = one ⌘Z
                        }
                        model.setTempo((dragStartTempo ?? 120) - Double(value.translation.height) / 4)
                    }
                    .onEnded { _ in
                        dragStartTempo = nil
                        model.endUndoGesture()
                    }
            )
            stepper("+") { model.setTempo(model.project.tempoBPM + 1) }
        }
    }

    private func stepper(_ label: String, action: @escaping () -> Void) -> some View {
        let theme = model.theme
        return Button(action: action) {
            Text(label)
                .font(.system(size: 14, design: .monospaced))
                .frame(width: 24, height: 26)
                .foregroundStyle(theme.dim.swiftUI)
                .background(theme.surface.swiftUI)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.line.swiftUI, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var beatLED: some View {
        let theme = model.theme
        let on = model.isPlaying && (model.displayedStep.map { $0 % 4 == 0 } ?? false)
        return Circle()
            .fill((on ? theme.accent : theme.faint.withAlphaComponent(0.5)).swiftUI)
            .frame(width: 8, height: 8)
            .shadow(color: on ? theme.accent.swiftUI : .clear, radius: on ? 4 : 0)
    }

    private var swingControl: some View {
        let theme = model.theme
        return HStack(spacing: 10) {
            Text("SWING")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            Slider(value: Binding(get: { model.project.swingPercent },
                                  set: { model.setSwing($0) }),
                   in: Project.swingRange,
                   onEditingChanged: { editing in
                       editing ? model.beginUndoGesture() : model.endUndoGesture()
                   })
                .controlSize(.small)
                .tint(theme.accent.swiftUI)
                .frame(width: 104)
            Text("\(Int(model.project.swingPercent.rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.dim.swiftUI)
                .frame(width: 34, alignment: .leading)
        }
    }

    /// Seeds are actions (dashed), not selectors: one click overwrites the
    /// bar and retunes tempo + swing. ⌘Z undoes.
    private var seedChips: some View {
        let theme = model.theme
        return HStack(spacing: 8) {
            Text("SEED")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            ForEach(Seeds.all, id: \.name) { seed in
                let active = model.activeSeedName == seed.name
                Button(seed.name) { model.loadSeed(seed) }
                    .buttonStyle(ChipStyle(theme: theme, active: active, action: true))
                    .help("Load the \(seed.name) groove: bar, tempo, and swing (⌘Z undoes)")
            }
        }
    }
}

/// Two visual registers (grammar R2): chips that show a current state get
/// the accent ring when active; chips that DO something (`action`) get a
/// dashed outline and dim text so they can never be mistaken for selectors.
struct ChipStyle: ButtonStyle {
    let theme: Theme
    let active: Bool
    var action = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, design: .monospaced))
            .kerning(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle((action && !active ? theme.dim : theme.text).swiftUI)
            .background((active
                ? theme.accent.withAlphaComponent(0.16)
                : theme.surface).swiftUI)
            .overlay(Capsule().stroke(
                (active ? theme.accent : theme.line).swiftUI,
                style: StrokeStyle(lineWidth: 1, dash: action && !active ? [3.5, 2.5] : [])))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Pattern bar

/// Slot chips (A, B, C…), duplicate/add, and the loop mode toggle. The chain
/// plays every slot in order; slot mode loops only the one being edited.
struct PatternBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let theme = model.theme
        HStack(spacing: 8) {
            Text("PATTERN")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            ForEach(model.project.patterns.indices, id: \.self) { index in
                slotChip(index)
            }
            if model.project.patterns.count < AppModel.maxSlots {
                Button("⧉") { model.duplicateSlot() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                    .help("Duplicate this slot into a new one")
                Button("+") { model.addEmptySlot() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                    .help("Add an empty slot")
            }
            Rectangle().fill(theme.line.swiftUI).frame(width: 1, height: 18)
            // Destructive labels name their object (grammar L3): the clear
            // chip tracks the slot being edited.
            Button("clear \(AppModel.slotName(model.editingSlot))") { model.clearPattern() }
                .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                .help("Empty slot \(AppModel.slotName(model.editingSlot))'s pattern (⌘Z undoes)")
            // Time signature is a per-bar value: click cycles, ⌥-click
            // walks backwards (the song-chip gesture pair).
            Button("\(model.editingMeterBeats)/4") {
                model.cycleMeter(reverse: NSEvent.modifierFlags.contains(.option))
            }
            .buttonStyle(ChipStyle(theme: theme, active: false))
            .help("Time signature of slot \(AppModel.slotName(model.editingSlot)) · click 2/4→7/4, ⌥-click backwards")
            Spacer()
            Text("KIT")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            ForEach(Kit.all, id: \.id) { kit in
                Button(kit.name) { model.selectKit(kit) }
                    .buttonStyle(ChipStyle(theme: theme, active: model.project.kitID == kit.id))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(theme.raised.swiftUI)
    }

    private func slotChip(_ index: Int) -> some View {
        let theme = model.theme
        let playing = model.playingSlot == index && model.isPlaying
        let cued = model.cuedSlot == index && model.isPlaying
        return Button {
            model.selectSlot(index)
        } label: {
            HStack(spacing: 5) {
                // Filled dot: sounding now. Hollow dot: cued, takes over at
                // the end of the current pattern.
                Circle()
                    .strokeBorder(theme.accent.swiftUI, lineWidth: cued && !playing ? 1.2 : 0)
                    .background(Circle().fill(playing ? theme.accent.swiftUI : .clear))
                    .frame(width: 5.5, height: 5.5)
                    .opacity(playing || cued ? 1 : 0)
                Text(AppModel.slotName(index))
            }
        }
        .buttonStyle(ChipStyle(theme: theme, active: model.editingSlot == index))
        .help(cued ? "Cued: plays when the current pattern ends" : "")
        .contextMenu {
            // Menu verbs act on their target and never move selection, cue,
            // or playback (grammar L4).
            Button("Duplicate") { model.duplicateSlot(at: index) }
                .disabled(model.project.patterns.count >= AppModel.maxSlots)
            Button("Clear") { model.clearPattern(at: index) }
            Button("Remove", role: .destructive) { model.removeSlot(at: index) }
                .disabled(model.project.patterns.count <= 1)
            Divider()
            Button("Move Left") { model.moveSlot(at: index, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { model.moveSlot(at: index, by: 1) }
                .disabled(index == model.project.patterns.count - 1)
        }
    }
}

// MARK: - Song bar

/// The song arrangement: an ordered row of slot×repeat chips (`A×4 B×2 …`).
/// `+` appends the slot being edited; clicking a chip adds a repeat; the
/// context menu reorders and removes. The "song" loop mode plays this row.
struct SongBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let theme = model.theme
        HStack(spacing: 8) {
            Text("SONG")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            ForEach(model.project.song.indices, id: \.self) { index in
                songChip(index)
            }
            if model.project.song.count < AppModel.maxSongEntries {
                // The append chip names what it will append (grammar L3).
                Button("+ \(AppModel.slotName(model.editingSlot))") { model.appendSongEntry() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                    .help("Append slot \(AppModel.slotName(model.editingSlot)) to the song")
            }
            if model.project.song.isEmpty {
                Text("arrange slots into a song · + adds the slot being edited")
                    .font(.system(size: 10, design: .monospaced))
                    .kerning(0.4)
                    .foregroundStyle(theme.faint.swiftUI)
            } else {
                Rectangle().fill(theme.line.swiftUI).frame(width: 1, height: 18)
                Button("clear song") { model.clearSong() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                    .help("Empty the whole arrangement (⌘Z undoes)")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(theme.raised.swiftUI)
    }

    @ViewBuilder
    private func songChip(_ index: Int) -> some View {
        // ForEach over indices can re-evaluate a chip with a stale index
        // while entries are being removed; subscripting blindly would crash.
        if model.project.song.indices.contains(index) {
            songChipBody(index)
        }
    }

    private func songChipBody(_ index: Int) -> some View {
        let theme = model.theme
        let entry = model.project.song[index]
        return Button {
            // Repeats are a value; click walks the powers-of-two ladder,
            // ⌥-click walks it backwards (Decision B).
            model.cycleSongRepeats(at: index,
                                   reverse: NSEvent.modifierFlags.contains(.option))
        } label: {
            Text("\(AppModel.slotName(entry.slot))×\(entry.repeats)")
        }
        .buttonStyle(ChipStyle(theme: theme, active: model.loopMode == .song))
        .help("Click: ×1→×2→×4→×8→×16 · ⌥-click: backwards")
        .contextMenu {
            Button("Duplicate") { model.duplicateSongEntry(at: index) }
                .disabled(model.project.song.count >= AppModel.maxSongEntries)
            Button("Remove", role: .destructive) { model.removeSongEntry(at: index) }
            Divider()
            Button("Move Left") { model.moveSongEntry(at: index, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { model.moveSongEntry(at: index, by: 1) }
                .disabled(index == model.project.song.count - 1)
            Divider()
            Menu("Repeats") {
                ForEach(AppModel.repeatSteps, id: \.self) { n in
                    Button("×\(n)\(entry.repeats == n ? "  ✓" : "")") {
                        model.setSongRepeats(at: index, to: n)
                    }
                }
            }
        }
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let theme = model.theme
        HStack(spacing: 16) {
            Text("click toggle · right-click velocity/menu · drag paint · ⌘Z undo · space play · a–k jam")
                .font(.system(size: 10, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(theme.faint.swiftUI)
            Text(model.midiSourceNames.isEmpty
                ? "midi: none"
                : "midi: \(model.midiSourceNames.joined(separator: ", "))")
                .font(.system(size: 10, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(theme.faint.swiftUI)
                .lineLimit(1)
            if let error = model.engineError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("EXPORT")
                    .font(.system(size: 9, design: .monospaced).weight(.medium))
                    .kerning(1.2)
                    .foregroundStyle(theme.faint.swiftUI)
                Button("midi") { model.exportMIDI() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, action: true))
                    .disabled(model.isExporting)
                Menu {
                    Button("1 pass") { model.exportAudio(format: .wav, cycles: 1) }
                    Button("2 passes") { model.exportAudio(format: .wav, cycles: 2) }
                    Button("4 passes") { model.exportAudio(format: .wav, cycles: 4) }
                    Divider()
                    ForEach([5, 10, 20, 30], id: \.self) { minutes in
                        Button("m4a jog mix · \(minutes) min") {
                            model.exportAudio(format: .m4a, minutes: Double(minutes))
                        }
                    }
                } label: {
                    Text(model.isExporting ? "rendering…" : "wav")
                        .font(.system(size: 11, design: .monospaced))
                        .kerning(0.6)
                        .foregroundStyle(theme.dim.swiftUI)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.surface.swiftUI)
                .overlay(Capsule().stroke(theme.line.swiftUI,
                                          style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5])))
                .clipShape(Capsule())
                .disabled(model.isExporting)
            }
            Rectangle().fill(theme.line.swiftUI).frame(width: 1, height: 16)
            HStack(spacing: 6) {
                ForEach(ThemeID.allCases) { id in
                    Button(id.label) { model.themeID = id }
                        .buttonStyle(ChipStyle(theme: theme, active: model.themeID == id))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.raised.swiftUI)
    }
}
