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
