import AppKit
import SwiftUI
import TaktUI

@main
struct TaktApp: App {
    @NSApplicationDelegateAdaptor(ActivationDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("takt") {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save As…") { model.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { model.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .importExport) {
                Button("Export MIDI…") { model.exportMIDI() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.isExporting)
                Menu("Export WAV") {
                    Button("1 Pass…") { model.exportWAV(passes: 1) }
                        .keyboardShortcut("e", modifiers: .command)
                    Button("2 Passes…") { model.exportWAV(passes: 2) }
                    Button("4 Passes…") { model.exportWAV(passes: 4) }
                }
                .disabled(model.isExporting)
                Menu("Export Jog Mix (m4a)") {
                    ForEach([5, 10, 20, 30], id: \.self) { minutes in
                        Button("\(minutes) Minutes…") { model.exportJogMix(minutes: Double(minutes)) }
                    }
                }
                .disabled(model.isExporting)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
        }
    }
}

final class ActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
