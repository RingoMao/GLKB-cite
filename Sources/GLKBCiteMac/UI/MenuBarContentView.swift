import AppKit
import SwiftUI

/// Menu-bar menu, following the design: Find Citations, the badge toggle,
/// Settings, About, Quit. Two items appear only when they are actionable:
/// an update check (a background app has no other way to surface updates)
/// and an Accessibility warning when the grant has been lost.
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
                get: { settings.automaticSelectionEnabled && settings.hasCompletedOnboarding },
                set: { coordinator.setAutomaticSelectionEnabled($0) }
            )
        )

        if coordinator.accessibilityWarning != nil {
            Button("Accessibility Access Needed…") {
                coordinator.openAccessibilitySettings()
            }
        }

        Divider()

        Button("Settings…") {
            coordinator.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        if coordinator.updateController.isConfigured {
            Button(updateTitle) {
                coordinator.checkForUpdates()
            }
            .disabled(!coordinator.updateController.canCheckForUpdates)
        }

        Button("About GLKB Cite") {
            coordinator.showAbout()
        }

        Divider()

        Button("Quit GLKB Cite") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var updateTitle: String {
        if let version = coordinator.pendingUpdateVersion {
            return "Update Available: \(version)…"
        }
        return "Check for Updates…"
    }
}
