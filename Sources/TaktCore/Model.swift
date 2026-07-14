import Foundation

public struct Voice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var hueDegrees: Double
    public var sampleFile: String
    public var gmNote: UInt8
    public var chokeGroup: Int?

    public init(id: String, name: String, hueDegrees: Double, sampleFile: String,
                gmNote: UInt8, chokeGroup: Int? = nil) {
        self.id = id
        self.name = name
        self.hueDegrees = hueDegrees
        self.sampleFile = sampleFile
        self.gmNote = gmNote
        self.chokeGroup = chokeGroup
    }
}

public struct Kit: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var voices: [Voice]

    public init(id: String, name: String, voices: [Voice]) {
        self.id = id
        self.name = name
        self.voices = voices
    }

    public func voice(id: String) -> Voice? {
        voices.first { $0.id == id }
    }

    public func voice(gmNote: UInt8) -> Voice? {
        voices.first { $0.gmNote == gmNote }
    }
}

public extension Kit {
    /// The built-in synth-rendered kit. Samples live in TaktAudio resources.
    static let takt1 = Kit(id: "takt-1", name: "TAKT-1", voices: [
        Voice(id: "kick",  name: "Kick",       hueDegrees: 40,  sampleFile: "kick.wav",  gmNote: 36),
        Voice(id: "snare", name: "Snare",      hueDegrees: 20,  sampleFile: "snare.wav", gmNote: 38),
        Voice(id: "clap",  name: "Clap",       hueDegrees: 345, sampleFile: "clap.wav",  gmNote: 39),
        Voice(id: "rim",   name: "Rim",        hueDegrees: 300, sampleFile: "rim.wav",   gmNote: 37),
        Voice(id: "chat",  name: "Hat closed", hueDegrees: 95,  sampleFile: "chat.wav",  gmNote: 42, chokeGroup: 1),
        Voice(id: "ohat",  name: "Hat open",   hueDegrees: 150, sampleFile: "ohat.wav",  gmNote: 46, chokeGroup: 1),
        Voice(id: "tom",   name: "Tom low",    hueDegrees: 250, sampleFile: "tom.wav",   gmNote: 45),
        Voice(id: "cow",   name: "Cowbell",    hueDegrees: 200, sampleFile: "cow.wav",   gmNote: 56),
    ])
}

/// One step in a track. Velocity is MIDI-native 0...127; 0 means off.
public struct Step: Codable, Equatable, Sendable {
    public var velocity: UInt8

    public init(velocity: UInt8 = 0) {
        self.velocity = velocity
    }

    public var isOn: Bool { velocity > 0 }
    public var gain: Float { Float(velocity) / 127 }
}

/// The three UI velocity levels plus off. Storage stays 0...127.
public enum VelocityLevel: Int, CaseIterable, Sendable {
    case off = 0, soft, normal, accent

    public var midi: UInt8 {
        switch self {
        case .off: 0
        case .soft: 54
        case .normal: 96
        case .accent: 127
        }
    }

    /// Nearest UI level for an arbitrary stored velocity (e.g. recorded MIDI).
    public init(nearest velocity: UInt8) {
        switch velocity {
        case 0: self = .off
        case 1...74: self = .soft
        case 75...111: self = .normal
        default: self = .accent
        }
    }
}

public struct Track: Codable, Equatable, Sendable {
    public var voiceID: String
    public var steps: [Step]
    public var isMuted: Bool
    public var isSoloed: Bool
    public var level: Float

    public init(voiceID: String, steps: [Step], isMuted: Bool = false,
                isSoloed: Bool = false, level: Float = 1) {
        self.voiceID = voiceID
        self.steps = steps
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.level = level
    }

    public init(voiceID: String, stepCount: Int) {
        self.init(voiceID: voiceID, steps: Array(repeating: Step(), count: stepCount))
    }
}

public struct Pattern: Codable, Equatable, Sendable {
    public var name: String
    public var stepCount: Int
    public var tracks: [Track]

    public init(name: String, stepCount: Int, tracks: [Track]) {
        self.name = name
        self.stepCount = stepCount
        self.tracks = tracks
    }

    /// An empty pattern with one track per kit voice.
    public init(name: String = "Pattern", stepCount: Int = 16, kit: Kit) {
        self.init(name: name, stepCount: stepCount,
                  tracks: kit.voices.map { Track(voiceID: $0.id, stepCount: stepCount) })
    }

    /// Solo-aware audibility: if any track is soloed, only soloed tracks play.
    public func isAudible(trackIndex: Int) -> Bool {
        let anySolo = tracks.contains { $0.isSoloed }
        let track = tracks[trackIndex]
        return anySolo ? track.isSoloed : !track.isMuted
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var kitID: String
    public var tempoBPM: Double
    public var swingPercent: Double
    public var patterns: [Pattern]
    public var currentPatternIndex: Int
    /// MIDI note → voice ID remaps (learn mode, v1.1). Empty in v1.
    public var midiOverrides: [UInt8: String]

    public static let tempoRange: ClosedRange<Double> = 50...200
    public static let swingRange: ClosedRange<Double> = 50...75

    public init(schemaVersion: Int = 1, kitID: String = Kit.takt1.id,
                tempoBPM: Double = 120, swingPercent: Double = 50,
                patterns: [Pattern], currentPatternIndex: Int = 0,
                midiOverrides: [UInt8: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.kitID = kitID
        self.tempoBPM = tempoBPM.clamped(to: Self.tempoRange)
        self.swingPercent = swingPercent.clamped(to: Self.swingRange)
        self.patterns = patterns
        self.currentPatternIndex = currentPatternIndex
        self.midiOverrides = midiOverrides
    }

    public var currentPattern: Pattern {
        get { patterns[currentPatternIndex] }
        set { patterns[currentPatternIndex] = newValue }
    }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
