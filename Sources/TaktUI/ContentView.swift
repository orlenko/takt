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
                .frame(minWidth: 1060, idealWidth: 1100,
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
        HStack(spacing: 22) {
            playButton
            tempoControl
            beatLED
            swingControl
            Spacer(minLength: 12)
            seedChips
            clearButton
        }
        .padding(.leading, 84) // room for the traffic lights (hidden title bar)
        .padding(.trailing, 20)
        .padding(.vertical, 13)
        .background(theme.raised.swiftUI)
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
                        if dragStartTempo == nil { dragStartTempo = model.project.tempoBPM }
                        model.setTempo((dragStartTempo ?? 120) - Double(value.translation.height) / 4)
                    }
                    .onEnded { _ in dragStartTempo = nil }
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
                   in: Project.swingRange)
                .controlSize(.small)
                .tint(theme.accent.swiftUI)
                .frame(width: 120)
            Text("\(Int(model.project.swingPercent.rounded()))%")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.dim.swiftUI)
                .frame(width: 34, alignment: .leading)
        }
    }

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
                    .buttonStyle(ChipStyle(theme: theme, active: active))
            }
        }
    }

    private var clearButton: some View {
        Button("clear") { model.clearPattern() }
            .buttonStyle(ChipStyle(theme: model.theme, active: false, subdued: true))
    }
}

struct ChipStyle: ButtonStyle {
    let theme: Theme
    let active: Bool
    var subdued = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, design: .monospaced))
            .kerning(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle((active ? theme.text : (subdued ? theme.dim : theme.text)).swiftUI)
            .background((active
                ? theme.accent.withAlphaComponent(0.16)
                : theme.surface).swiftUI)
            .overlay(Capsule().stroke((active ? theme.accent : theme.line).swiftUI, lineWidth: 1))
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
                    .buttonStyle(ChipStyle(theme: theme, active: false, subdued: true))
                    .help("Duplicate this slot into a new one")
                Button("+") { model.addEmptySlot() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, subdued: true))
                    .help("Add an empty slot")
            }
            Spacer()
            Text("KIT")
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .kerning(1.2)
                .foregroundStyle(theme.faint.swiftUI)
            ForEach(Kit.all, id: \.id) { kit in
                Button(kit.name) { model.selectKit(kit) }
                    .buttonStyle(ChipStyle(theme: theme, active: model.project.kitID == kit.id))
            }
            Spacer().frame(width: 14)
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
            Button("Duplicate") {
                model.selectSlot(index)
                model.duplicateSlot()
            }
            Button("Clear") {
                model.selectSlot(index)
                model.clearPattern()
            }
            Button("Delete", role: .destructive) { model.deleteSlot(index) }
                .disabled(model.project.patterns.count <= 1)
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
                Button("+") { model.appendSongEntry() }
                    .buttonStyle(ChipStyle(theme: theme, active: false, subdued: true))
                    .help("Append slot \(AppModel.slotName(model.editingSlot)) to the song")
            }
            if model.project.song.isEmpty {
                Text("arrange slots into a song · + adds the slot being edited")
                    .font(.system(size: 10, design: .monospaced))
                    .kerning(0.4)
                    .foregroundStyle(theme.faint.swiftUI)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(theme.raised.swiftUI)
    }

    private func songChip(_ index: Int) -> some View {
        let theme = model.theme
        let entry = model.project.song[index]
        return Button {
            model.cycleSongRepeats(at: index)
        } label: {
            Text("\(AppModel.slotName(entry.slot))×\(entry.repeats)")
        }
        .buttonStyle(ChipStyle(theme: theme, active: model.loopMode == .song))
        .help("Click: one more repeat (wraps past ×\(SongEntry.repeatsRange.upperBound))")
        .contextMenu {
            Button("Move Left") { model.moveSongEntry(at: index, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { model.moveSongEntry(at: index, by: 1) }
                .disabled(index == model.project.song.count - 1)
            Button("Remove", role: .destructive) { model.removeSongEntry(at: index) }
        }
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let theme = model.theme
        HStack(spacing: 16) {
            Text("click toggle · right-click velocity · drag paint · space play · a–k jam")
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
                    .buttonStyle(ChipStyle(theme: theme, active: false, subdued: true))
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
                .overlay(Capsule().stroke(theme.line.swiftUI, lineWidth: 1))
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
