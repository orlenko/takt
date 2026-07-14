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
                Button("wav") { model.exportAudio(format: .wav) }
                    .buttonStyle(ChipStyle(theme: theme, active: false, subdued: true))
                    .disabled(model.isExporting)
                Menu {
                    ForEach([5, 10, 20, 30], id: \.self) { minutes in
                        Button("\(minutes) minutes of loop") {
                            model.exportAudio(format: .m4a, minutes: Double(minutes))
                        }
                    }
                } label: {
                    Text(model.isExporting ? "rendering…" : "m4a")
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
