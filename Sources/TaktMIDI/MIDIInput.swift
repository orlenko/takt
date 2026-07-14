import CoreMIDI
import Foundation

public enum MIDIError: Error, CustomStringConvertible {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)

    public var description: String {
        switch self {
        case .clientCreate(let s): "MIDI client creation failed (\(s))"
        case .portCreate(let s): "MIDI input port creation failed (\(s))"
        }
    }
}

/// CoreMIDI input: connects every source, follows hot-plug, and forwards
/// note-ons. Mapping notes to kit voices is the caller's job (GM map +
/// project overrides live above this layer).
public final class MIDIInput {
    /// Called on a CoreMIDI thread with (note, velocity), velocity > 0.
    public var onNoteOn: (@Sendable (UInt8, UInt8) -> Void)?
    /// Called after (re)connecting sources, with their display names.
    public var onSourcesChanged: (([String]) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected = Set<MIDIEndpointRef>()

    public init() {}

    deinit {
        if client != 0 { MIDIClientDispose(client) }
    }

    public func start() throws {
        let clientStatus = MIDIClientCreateWithBlock("takt" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                self?.connectAllSources()
            }
        }
        guard clientStatus == noErr else { throw MIDIError.clientCreate(clientStatus) }

        let portStatus = MIDIInputPortCreateWithProtocol(client, "takt-in" as CFString, ._1_0, &port) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
        guard portStatus == noErr else { throw MIDIError.portCreate(portStatus) }
        connectAllSources()
    }

    private func connectAllSources() {
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard source != 0, !connected.contains(source) else { continue }
            if MIDIPortConnectSource(port, source, nil) == noErr {
                connected.insert(source)
            }
        }
        onSourcesChanged?(sourceNames())
    }

    private func sourceNames() -> [String] {
        (0..<MIDIGetNumberOfSources()).compactMap { i in
            let source = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr else {
                return nil
            }
            return name?.takeRetainedValue() as String?
        }
    }

    /// Parse Universal MIDI Packets (MIDI 1.0 protocol). Message word counts
    /// follow the UMP message type so multi-word packets (sysex) never get
    /// misread as channel voice messages.
    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        for packet in eventList.unsafeSequence() {
            let wordCount = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < min(wordCount, words.count) {
                    let word = words[i]
                    let messageType = (word >> 28) & 0xF
                    switch messageType {
                    case 0x2: // MIDI 1.0 channel voice, 1 word
                        let status = (word >> 20) & 0xF
                        let note = UInt8((word >> 8) & 0x7F)
                        let velocity = UInt8(word & 0x7F)
                        if status == 0x9, velocity > 0 {
                            onNoteOn?(note, velocity)
                        }
                        i += 1
                    case 0x0, 0x1: i += 1 // utility, system real-time
                    case 0x3, 0x4: i += 2 // sysex7, MIDI 2.0 channel voice
                    case 0x5: i += 4      // data 128
                    default: i += 1
                    }
                }
            }
        }
    }
}
