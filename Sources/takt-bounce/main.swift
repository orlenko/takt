// Renders every seed pattern to a WAV for quick listening without the UI:
//   swift run takt-bounce [output-dir] [kit-id]   (defaults: preview/, takt-1)

import Foundation
import TaktAudio
import TaktCore

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "preview")
let kit = Kit.kit(id: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : Kit.takt1.id) ?? .takt1
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for seed in Seeds.all {
    let name = seed.name.lowercased().replacingOccurrences(of: "-", with: "")
    let suffix = kit.id == Kit.takt1.id ? "" : "-\(kit.id)"
    let url = outDir.appendingPathComponent("\(name)\(suffix).wav")
    let seconds = try Bounce.render(pattern: seed.pattern(kit: kit), kit: kit,
                                    tempoBPM: seed.tempoBPM,
                                    swingPercent: seed.swingPercent,
                                    loops: 4, to: url)
    print("\(url.lastPathComponent): \(String(format: "%.2f", seconds)) s @ \(Int(seed.tempoBPM)) BPM, swing \(Int(seed.swingPercent))%, kit \(kit.name)")
}
print("previews in \(outDir.path)")
