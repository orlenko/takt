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
                Button("Open…") { model.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
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
