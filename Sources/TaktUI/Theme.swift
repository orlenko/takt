import AppKit
import SwiftUI

/// Exact OKLCH → sRGB conversion (Björn Ottosson's OKLab matrices), so the
/// app reproduces DESIGN.md / the design mock to the digit. Out-of-gamut
/// channels are clamped, matching browser behavior closely enough for these
/// palettes.
func oklch(_ L: Double, _ C: Double, _ h: Double, _ alpha: Double = 1) -> NSColor {
    let hr = h * .pi / 180
    let a = C * cos(hr)
    let b = C * sin(hr)

    let l0 = L + 0.3963377774 * a + 0.2158037573 * b
    let m0 = L - 0.1055613458 * a - 0.0638541728 * b
    let s0 = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l0 * l0 * l0, m = m0 * m0 * m0, s = s0 * s0 * s0

    let rLin = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bLin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    func gamma(_ c: Double) -> CGFloat {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
        return CGFloat(min(max(v, 0), 1))
    }
    return NSColor(srgbRed: gamma(rLin), green: gamma(gLin), blue: gamma(bLin),
                   alpha: CGFloat(alpha))
}

enum ThemeID: String, CaseIterable, Identifiable {
    case candy, tungsten, linen
    var id: String { rawValue }
    var label: String { rawValue }
}

/// Velocity rendering for one voice hue under the current theme.
struct VoiceColors {
    let soft: NSColor
    let normal: NSColor
    let accent: NSColor
    let glow: NSColor
    let dot: NSColor
}

/// Token set mirroring DESIGN.md. Values are authored in OKLCH there; this
/// struct holds the converted NSColors plus the per-theme voice parameters.
struct Theme {
    let id: ThemeID
    let bg: NSColor
    let surface: NSColor
    let raised: NSColor
    let cell: NSColor
    let cellBeat: NSColor
    let line: NSColor
    let text: NSColor
    let dim: NSColor
    let faint: NSColor
    let accent: NSColor
    let accentHover: NSColor
    let onAccent: NSColor
    let ring: NSColor
    let cellRadius: CGFloat
    let hasGloss: Bool
    let isDark: Bool

    // voice rendering parameters (VL/VC = lightness/chroma of the lane hue)
    let vl: Double, vc: Double        // soft + normal fills, dot
    let vl3: Double, vc3: Double      // accent fill
    let a1: Double, a2: Double        // soft / normal alphas
    let glowAlpha: Double

    func voiceColors(hue: Double) -> VoiceColors {
        VoiceColors(
            soft: oklch(vl, vc, hue, a1),
            normal: oklch(vl, vc, hue, a2),
            accent: oklch(vl3, vc3, hue),
            glow: oklch(vl, vc, hue, glowAlpha),
            dot: oklch(vl, vc, hue))
    }

    static func theme(_ id: ThemeID) -> Theme {
        switch id {
        case .candy: candy
        case .tungsten: tungsten
        case .linen: linen
        }
    }

    /// Daylight and play: sugar-glass brights on vanilla cream.
    static let candy = Theme(
        id: .candy,
        bg: oklch(0.92, 0.03, 345),
        surface: oklch(0.972, 0.012, 85),
        raised: oklch(0.945, 0.018, 350),
        cell: oklch(0.915, 0.014, 340),
        cellBeat: oklch(0.885, 0.018, 340),
        line: oklch(0.86, 0.025, 345),
        text: oklch(0.34, 0.06, 30),
        dim: oklch(0.50, 0.05, 25),
        faint: oklch(0.64, 0.035, 25),
        accent: oklch(0.66, 0.20, 35),
        accentHover: oklch(0.70, 0.20, 35),
        onAccent: oklch(0.99, 0.01, 90),
        ring: oklch(0.34, 0.06, 340, 0.55),
        cellRadius: 10, hasGloss: true, isDark: false,
        vl: 0.72, vc: 0.17, vl3: 0.68, vc3: 0.20,
        a1: 0.40, a2: 0.78, glowAlpha: 0.45)

    /// Evening, dim room, stage-dark warmth.
    static let tungsten = Theme(
        id: .tungsten,
        bg: oklch(0.13, 0.006, 70),
        surface: oklch(0.185, 0.008, 65),
        raised: oklch(0.22, 0.009, 65),
        cell: oklch(0.245, 0.008, 65),
        cellBeat: oklch(0.275, 0.009, 65),
        line: oklch(0.30, 0.01, 65),
        text: oklch(0.93, 0.012, 85),
        dim: oklch(0.63, 0.015, 75),
        faint: oklch(0.45, 0.012, 70),
        accent: oklch(0.70, 0.185, 45),
        accentHover: oklch(0.74, 0.185, 45),
        onAccent: oklch(0.16, 0.02, 45),
        ring: oklch(0.9, 0.02, 85, 0.55),
        cellRadius: 6, hasGloss: false, isDark: true,
        vl: 0.76, vc: 0.135, vl3: 0.78, vc3: 0.145,
        a1: 0.38, a2: 0.75, glowAlpha: 0.35)

    /// Long daytime sessions, lowest stimulus: warm gray-green paper.
    static let linen = Theme(
        id: .linen,
        bg: oklch(0.885, 0.008, 100),
        surface: oklch(0.945, 0.006, 95),
        raised: oklch(0.92, 0.007, 95),
        cell: oklch(0.88, 0.007, 95),
        cellBeat: oklch(0.855, 0.009, 95),
        line: oklch(0.82, 0.009, 95),
        text: oklch(0.33, 0.015, 80),
        dim: oklch(0.47, 0.015, 80),
        faint: oklch(0.60, 0.012, 85),
        accent: oklch(0.56, 0.115, 42),
        accentHover: oklch(0.60, 0.115, 42),
        onAccent: oklch(0.97, 0.01, 90),
        ring: oklch(0.30, 0.01, 80, 0.5),
        cellRadius: 6, hasGloss: false, isDark: false,
        vl: 0.66, vc: 0.085, vl3: 0.56, vc3: 0.10,
        a1: 0.45, a2: 0.80, glowAlpha: 0.18)
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}
