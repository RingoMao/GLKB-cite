import AppKit
import SwiftUI

/// Menu-bar menu, matching the design: Find Citations, the badge toggle,
/// Settings, About, Quit. Everything else lives in Settings or the About panel.
struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button("Find Citations") {
            coordinator.captureCitations()
        }
        .keyboardShortcut("g", modifiers: [.command, .option])

        Divider()

        Toggle(
            "Show Selection Badge",
            isOn: Binding(
                get: { settings.automaticSelectionEnabled },
                set: { coordinator.setAutomaticSelectionEnabled($0) }
            )
        )

        Divider()

        Button("Settings…") {
            coordinator.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("About GLKB Cite") {
            coordinator.showAbout()
        }

        Divider()

        Button("Quit GLKB Cite") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
