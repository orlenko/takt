import Foundation

/// A genre starting point. Row strings are per-voice step digits in kit voice
/// order; 0 = off, 1 = soft, 2 = normal, 3 = accent (see VelocityLevel).
public struct Seed: Equatable, Sendable {
    public let name: String
    public let tempoBPM: Double
    public let swingPercent: Double
    public let rows: [String]

    public init(name: String, tempoBPM: Double, swingPercent: Double, rows: [String]) {
        self.name = name
        self.tempoBPM = tempoBPM
        self.swingPercent = swingPercent
        self.rows = rows
    }

    public func pattern(kit: Kit) -> Pattern {
        let tracks = zip(kit.voices, rows).map { voice, row in
            Track(voiceID: voice.id, steps: row.map { digit in
                let level = VelocityLevel(rawValue: digit.wholeNumberValue ?? 0) ?? .off
                return Step(velocity: level.midi)
            })
        }
        return Pattern(name: name, stepCount: rows.first?.count ?? 16, tracks: tracks)
    }
}

public enum Seeds {
    // Voice order: kick, snare, clap, rim, chat, ohat, tom, cow

    public static let house = Seed(name: "House", tempoBPM: 122, swingPercent: 54, rows: [
        "3000300030003000",
        "0000000000000000",
        "0000200000002000",
        "0001000000100000",
        "2000200020002000",
        "0020002000200020",
        "0000000000000000",
        "0000000000000000",
    ])

    public static let breaks = Seed(name: "Breaks", tempoBPM: 108, swingPercent: 60, rows: [
        "3000002000200000",
        "0000300101003001",
        "0000000000000000",
        "0000000000000000",
        "2020202020202000",
        "0000000000000020",
        "0000000000000000",
        "0000000000000000",
    ])

    public static let hipHop = Seed(name: "Hip-Hop", tempoBPM: 92, swingPercent: 58, rows: [
        "3000000200200000",
        "0000300001003000",
        "0000000000000000",
        "0000000000000000",
        "2010201020102000",
        "0000000000000010",
        "0000000000000000",
        "0000000000000000",
    ])

    public static let techno = Seed(name: "Techno", tempoBPM: 132, swingPercent: 50, rows: [
        "3000300030003000",
        "0000000000000000",
        "0000200000002000",
        "0002000000020000",
        "0020002000200020",
        "0000000000000000",
        "0000000000000201",
        "0000000000000000",
    ])

    public static let all: [Seed] = [house, breaks, hipHop, techno]
}
