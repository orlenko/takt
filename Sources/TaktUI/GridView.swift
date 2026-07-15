import AppKit
import SwiftUI
import TaktAudio
import TaktCore

/// The pattern grid: step numbers, lane headers (dot, name, M/S), cells, and
/// the playhead, all drawn in one NSView so rows can never misalign and mouse
/// semantics match the design mock exactly (click toggle, right-click
/// velocity cycle, left-drag paint).
final class GridNSView: NSView {
    weak var model: AppModel?

    // Metrics (from the mock)
    private let padTop: CGFloat = 18
    private let padSide: CGFloat = 20
    private let padBottom: CGFloat = 20
    private let numRowHeight: CGFloat = 24
    private let headWidth: CGFloat = 172
    private let cellHeight: CGFloat = 42
    private let rowGap: CGFloat = 5
    private let cellGap: CGFloat = 4
    private let beatGap: CGFloat = 15
    private let msSize: CGFloat = 19

    static let steps = 16

    private var paintVelocity: UInt8?

    override var isFlipped: Bool { true }

    static var preferredHeight: CGFloat {
        18 + 24 + 8 * 47 - 5 + 20
    }

    // MARK: - Geometry

    private var cellWidth: CGFloat {
        let gaps = CGFloat(Self.steps - 4) * cellGap + 3 * beatGap
        return (bounds.width - 2 * padSide - headWidth - gaps) / CGFloat(Self.steps)
    }

    private func cellX(_ step: Int) -> CGFloat {
        let beats = CGFloat(step / 4)
        return padSide + headWidth + CGFloat(step) * (cellWidth + cellGap)
            + beats * (beatGap - cellGap)
    }

    private func rowY(_ track: Int) -> CGFloat {
        padTop + numRowHeight + CGFloat(track) * (cellHeight + rowGap)
    }

    private func cellRect(track: Int, step: Int) -> NSRect {
        NSRect(x: cellX(step), y: rowY(track), width: cellWidth, height: cellHeight)
    }

    private func muteRect(track: Int) -> NSRect {
        NSRect(x: padSide + headWidth - 14 - 2 * msSize - 4,
               y: rowY(track) + (cellHeight - msSize) / 2, width: msSize, height: msSize)
    }

    private func soloRect(track: Int) -> NSRect {
        NSRect(x: padSide + headWidth - 14 - msSize,
               y: rowY(track) + (cellHeight - msSize) / 2, width: msSize, height: msSize)
    }

    private func hitCell(_ point: NSPoint) -> (track: Int, step: Int)? {
        guard let model else { return nil }
        for track in 0..<model.kit.voices.count {
            for step in 0..<Self.steps
            where cellRect(track: track, step: step).insetBy(dx: -cellGap / 2, dy: -rowGap / 2)
                .contains(point) {
                return (track, step)
            }
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let theme = model.theme
        let pattern = model.project.currentPattern
        let now = Sequencer.hostSecondsNow()
        // The playhead only belongs on the grid when the sounding slot is the
        // one being shown.
        let playheadStep = model.playingSlot == model.editingSlot ? model.displayedStep : nil

        theme.surface.setFill()
        bounds.fill()

        let mono = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        let numAttrs: (NSColor) -> [NSAttributedString.Key: Any] = { color in
            [.font: mono, .foregroundColor: color]
        }

        // Step number row: beat numbers over downbeats, dots elsewhere.
        for step in 0..<Self.steps {
            let isBeat = step % 4 == 0
            let isNow = playheadStep == step
            let label = isBeat ? "\(step / 4 + 1)" : "·"
            let color = isNow ? theme.text : (isBeat ? theme.dim : theme.faint)
            NSAttributedString(string: label, attributes: numAttrs(color))
                .draw(at: NSPoint(x: cellX(step) + 4, y: padTop))
        }

        for (track, voice) in model.kit.voices.enumerated() {
            let y = rowY(track)
            let palette = model.voicePalettes[track]
            let trackData = pattern.tracks[track]
            let audible = pattern.isAudible(trackIndex: track)

            // Dot, flashing on triggers.
            let flashing = model.dotFlashes[track].map { now - $0 < AppModel.flashDuration } ?? false
            let dotSize: CGFloat = flashing ? 12 : 9
            let dotRect = NSRect(x: padSide, y: y + (cellHeight - dotSize) / 2,
                                 width: dotSize, height: dotSize)
            palette.dot.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            // Name.
            let nameColor = audible ? theme.dim : theme.faint
            let name = NSAttributedString(
                string: voice.name.uppercased(),
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                             .foregroundColor: nameColor, .kern: 0.9])
            name.draw(at: NSPoint(x: padSide + 18, y: y + (cellHeight - 13) / 2))

            // M / S buttons.
            drawToggle(muteRect(track: track), label: "M", on: trackData.isMuted, theme: theme)
            drawToggle(soloRect(track: track), label: "S", on: trackData.isSoloed, theme: theme)

            // Cells.
            for step in 0..<Self.steps {
                let rect = cellRect(track: track, step: step)
                let path = NSBezierPath(roundedRect: rect, xRadius: theme.cellRadius,
                                        yRadius: theme.cellRadius)
                let velocity = trackData.steps[step].velocity
                let level = VelocityLevel(nearest: velocity)

                var fill: NSColor = step % 4 == 0 ? theme.cellBeat : theme.cell
                var glow: NSColor?
                switch level {
                case .off: break
                case .soft: fill = palette.soft
                case .normal: fill = palette.normal
                case .accent: fill = palette.accent; glow = palette.glow
                }
                if !audible, level != .off {
                    fill = fill.withAlphaComponent(fill.alphaComponent * 0.28)
                    glow = nil
                }

                if let glow, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 12, color: glow.cgColor)
                    fill.setFill()
                    path.fill()
                    ctx.restoreGState()
                } else {
                    fill.setFill()
                    path.fill()
                }

                // Candy gumdrop gloss on filled steps.
                if theme.hasGloss, level != .off {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    NSColor.white.withAlphaComponent(0.55).setFill()
                    NSRect(x: rect.minX + 2, y: rect.minY + 1,
                           width: rect.width - 4, height: 1.5).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }

                // Trigger flash.
                if let start = model.cellFlashes[AppModel.FlashKey(track: track, step: step)] {
                    let k = 1 - (now - start) / AppModel.flashDuration
                    if k > 0 {
                        NSColor.white.withAlphaComponent(0.4 * k).setFill()
                        path.fill()
                    }
                }

                // Playhead ring.
                if playheadStep == step {
                    theme.ring.setStroke()
                    let ringPath = NSBezierPath(
                        roundedRect: rect.insetBy(dx: 0.75, dy: 0.75),
                        xRadius: theme.cellRadius, yRadius: theme.cellRadius)
                    ringPath.lineWidth = 1.5
                    ringPath.stroke()
                }
            }
        }
    }

    private func drawToggle(_ rect: NSRect, label: String, on: Bool, theme: Theme) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        if on {
            theme.cellBeat.setFill()
            path.fill()
            theme.dim.setStroke()
        } else {
            theme.line.withAlphaComponent(0.6).setStroke()
        }
        path.lineWidth = 1
        path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: on ? theme.text : theme.faint,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: rect.midX - size.width / 2,
                               y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)

        for track in 0..<model.kit.voices.count {
            if muteRect(track: track).contains(point) {
                model.toggleMute(track: track)
                return
            }
            if soloRect(track: track).contains(point) {
                model.toggleSolo(track: track)
                return
            }
        }
        if let (track, step) = hitCell(point) {
            model.beginUndoGesture() // click + any paint drag = one ⌘Z
            paintVelocity = model.toggleCell(track: track, step: step)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model, let paintVelocity else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let (track, step) = hitCell(point),
           model.project.currentPattern.tracks[track].steps[step].velocity != paintVelocity {
            model.setCell(track: track, step: step, velocity: paintVelocity)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if paintVelocity != nil { model?.endUndoGesture() }
        paintVelocity = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let (track, step) = hitCell(point) {
            model.cycleVelocity(track: track, step: step)
            return
        }
        // Lane headers are containers: they get the standard menu.
        if let track = hitLaneHeader(point) {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Clear", action: #selector(clearLane(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = track
            menu.addItem(item)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    private func hitLaneHeader(_ point: NSPoint) -> Int? {
        guard let model, point.x >= padSide, point.x < padSide + headWidth else { return nil }
        for track in 0..<model.kit.voices.count
        where NSRect(x: padSide, y: rowY(track), width: headWidth, height: cellHeight)
            .contains(point) {
            return track
        }
        return nil
    }

    @objc private func clearLane(_ sender: NSMenuItem) {
        model?.clearLane(sender.tag)
    }
}

struct GridView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeNSView(context: Context) -> GridNSView {
        let view = GridNSView()
        view.model = model
        model.gridNeedsDisplay = { [weak view] in view?.needsDisplay = true }
        return view
    }

    func updateNSView(_ view: GridNSView, context: Context) {
        view.model = model
        view.needsDisplay = true
    }
}
