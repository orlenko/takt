import XCTest
@testable import TaktCore

final class ModelTests: XCTestCase {
    func testKitRegistry() {
        XCTAssertEqual(Kit.all.count, 3)
        XCTAssertEqual(Set(Kit.all.map(\.id)).count, 3, "kit ids must be unique")
        XCTAssertEqual(Kit.kit(id: "takt-2")?.name, "Nine-Oh")
        XCTAssertNil(Kit.kit(id: "bogus"))
        for kit in Kit.all {
            XCTAssertEqual(kit.voices, Kit.takt1.voices,
                           "\(kit.name): all kits must share the same voice roles")
        }
    }

    func testKitIntegrity() {
        let kit = Kit.takt1
        XCTAssertEqual(kit.voices.count, 8)
        XCTAssertEqual(Set(kit.voices.map(\.id)).count, 8, "voice ids must be unique")
        XCTAssertEqual(Set(kit.voices.map(\.gmNote)).count, 8, "GM notes must be unique")
        XCTAssertEqual(kit.voice(id: "chat")?.chokeGroup, kit.voice(id: "ohat")?.chokeGroup)
        XCTAssertNotNil(kit.voice(id: "chat")?.chokeGroup)
        XCTAssertEqual(kit.voice(gmNote: 36)?.id, "kick")
    }

    func testVelocityLevels() {
        XCTAssertEqual(VelocityLevel.off.midi, 0)
        XCTAssertEqual(VelocityLevel(nearest: 0), .off)
        XCTAssertEqual(VelocityLevel(nearest: 54), .soft)
        XCTAssertEqual(VelocityLevel(nearest: 74), .soft)
        XCTAssertEqual(VelocityLevel(nearest: 75), .normal)
        XCTAssertEqual(VelocityLevel(nearest: 96), .normal)
        XCTAssertEqual(VelocityLevel(nearest: 112), .accent)
        XCTAssertEqual(VelocityLevel(nearest: 127), .accent)
    }

    func testSeedsAreWellFormed() {
        let kit = Kit.takt1
        let validVelocities = Set(VelocityLevel.allCases.map(\.midi))
        for seed in Seeds.all {
            XCTAssertEqual(seed.rows.count, kit.voices.count, "\(seed.name) row count")
            for row in seed.rows {
                XCTAssertEqual(row.count, 16, "\(seed.name) step count")
            }
            let pattern = seed.pattern(kit: kit)
            XCTAssertEqual(pattern.stepCount, 16)
            XCTAssertEqual(pattern.tracks.map(\.voiceID), kit.voices.map(\.id))
            for track in pattern.tracks {
                for step in track.steps {
                    XCTAssertTrue(validVelocities.contains(step.velocity),
                                  "\(seed.name) invalid velocity \(step.velocity)")
                }
            }
            XCTAssertTrue(pattern.tracks.contains { $0.steps.contains(where: \.isOn) },
                          "\(seed.name) must not be empty")
            XCTAssertTrue(Project.tempoRange.contains(seed.tempoBPM))
            XCTAssertTrue(Project.swingRange.contains(seed.swingPercent))
        }
    }

    func testProjectRoundTrip() throws {
        var project = Project(patterns: [Seeds.breaks.pattern(kit: .takt1)])
        project.tempoBPM = 108
        project.swingPercent = 60
        project.currentPattern.tracks[0].steps[3] = Step(velocity: 127)
        project.currentPattern.tracks[1].isMuted = true
        project.midiOverrides = [60: "kick"]

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded, project)
    }

    func testProjectClampsRanges() {
        let project = Project(tempoBPM: 999, swingPercent: 10,
                              patterns: [Pattern(kit: .takt1)])
        XCTAssertEqual(project.tempoBPM, 200)
        XCTAssertEqual(project.swingPercent, 50)
    }

    func testSongOrderExpansion() {
        var project = Project(patterns: [Pattern(kit: .takt1), Pattern(kit: .takt1)])
        XCTAssertEqual(project.songOrder, [], "no song, no order")
        project.song = [SongEntry(slot: 0, repeats: 2),
                        SongEntry(slot: 1),
                        SongEntry(slot: 5, repeats: 3), // deleted slot: dropped
                        SongEntry(slot: 0)]
        XCTAssertEqual(project.songOrder, [0, 0, 1, 0])
    }

    func testSongEntryClampsRepeats() {
        XCTAssertEqual(SongEntry(slot: 0, repeats: 99).repeats, 16)
        XCTAssertEqual(SongEntry(slot: 0, repeats: 0).repeats, 1)
    }

    func testProjectWithSongRoundTrips() throws {
        var project = Project(patterns: [Pattern(kit: .takt1)])
        project.song = [SongEntry(slot: 0, repeats: 4), SongEntry(slot: 0)]
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data), project)
    }

    func testPreSongDocumentStillOpens() throws {
        // .takt files written before song mode have no "song" key.
        let project = Project(patterns: [Pattern(kit: .takt1)])
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)) as! [String: Any]
        json.removeValue(forKey: "song")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Project.self, from: legacy)
        XCTAssertEqual(decoded.song, [])
        XCTAssertEqual(decoded, project)
    }

    func testSetStepCountResizesTracks() {
        var pattern = Pattern(kit: .takt1)
        pattern.tracks[0].steps[15] = Step(velocity: 127)
        pattern.setStepCount(20) // 5/4: pads with silence
        XCTAssertEqual(pattern.stepCount, 20)
        XCTAssertTrue(pattern.tracks.allSatisfy { $0.steps.count == 20 })
        XCTAssertEqual(pattern.tracks[0].steps[15].velocity, 127, "existing hits survive")
        XCTAssertFalse(pattern.tracks[0].steps[16...].contains(where: \.isOn))
        pattern.setStepCount(12) // 3/4: truncates
        XCTAssertTrue(pattern.tracks.allSatisfy { $0.steps.count == 12 })
        XCTAssertFalse(pattern.tracks[0].steps.contains(where: \.isOn), "hit at 15 truncated")
    }

    func testSoloBeatsMute() {
        var pattern = Pattern(kit: .takt1)
        // No solo: mute decides.
        pattern.tracks[0].isMuted = true
        XCTAssertFalse(pattern.isAudible(trackIndex: 0))
        XCTAssertTrue(pattern.isAudible(trackIndex: 1))
        // Any solo: only soloed tracks play, even muted-and-soloed.
        pattern.tracks[2].isSoloed = true
        XCTAssertFalse(pattern.isAudible(trackIndex: 0))
        XCTAssertFalse(pattern.isAudible(trackIndex: 1))
        XCTAssertTrue(pattern.isAudible(trackIndex: 2))
    }
}
