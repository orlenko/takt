// Renders every seed pattern to a WAV for quick listening without the UI:
//   swift run takt-bounce [output-dir]   (default: preview/)

import Foundation
import TaktAudio
import TaktCore

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "preview")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for seed in Seeds.all {
    let name = seed.name.lowercased().replacingOccurrences(of: "-", with: "")
    let url = outDir.appendingPathComponent("\(name).wav")
    let seconds = try Bounce.render(pattern: seed.pattern(kit: .takt1), kit: .takt1,
                                    tempoBPM: seed.tempoBPM,
                                    swingPercent: seed.swingPercent,
                                    loops: 4, to: url)
    print("\(url.lastPathComponent): \(String(format: "%.2f", seconds)) s @ \(Int(seed.tempoBPM)) BPM, swing \(Int(seed.swingPercent))%")
}
print("previews in \(outDir.path)")
