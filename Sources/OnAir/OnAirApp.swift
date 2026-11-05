import SwiftUI

@main
struct OnAirApp: App {
    @State private var store = Store()
    @State private var updates = UpdateChecker()

    init() { Brand.registerFonts() }

    var body: some Scene {
        Window(Brand.name, id: "main") {
            ContentView()
                .environment(store)
                .environment(updates)
                .frame(minWidth: 960, minHeight: 560)
                .tint(Brand.signal)
                .preferredColorScheme(.dark)
                .task { await updates.checkIfDue() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 720)
        .commands { AppCommands(store: store, updates: updates) }

        Window("About ONAIR", id: "about") {
            AboutView().environment(updates)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct AppCommands: Commands {
    let store: Store
    let updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About ONAIR") { openWindow(id: "about") }
            Button("Check for Updates…") {
                openWindow(id: "about")
                Task { await updates.check() }
            }
        }
        CommandGroup(after: .newItem) {
            Button("Reload playlist") { Task { await store.reload() } }
                .keyboardShortcut("r")
        }
        CommandMenu("Channel") {
            Button("Next channel") { NotificationCenter.default.post(name: .nextChannel, object: nil) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Previous channel") { NotificationCenter.default.post(name: .previousChannel, object: nil) }
                .keyboardShortcut(.upArrow, modifiers: .command)
        }
    }
}
