import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Button {
            coordinator.captureCitations()
        } label: {
            Label("Find Citations", systemImage: "text.book.closed")
        }
        .keyboardShortcut("g", modifiers: [.command, .option])

        Button {
            coordinator.showLastResult()
        } label: {
            Label("Show Last Result", systemImage: "rectangle.stack")
        }

        Divider()

        Toggle(
            "Automatic Selection Badge (Beta)",
            isOn: Binding(
                get: { settings.automaticSelectionEnabled },
                set: { coordinator.setAutomaticSelectionEnabled($0) }
            )
        )

        Button {
            coordinator.showOnboarding()
        } label: {
            Label("Setup…", systemImage: "checklist")
        }

        Button {
            coordinator.showSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        if coordinator.updateController.isConfigured {
            Button {
                coordinator.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!coordinator.updateController.canCheckForUpdates)
        }

        Button {
            if let noticesURL {
                NSWorkspace.shared.open(noticesURL)
            }
        } label: {
            Label("Third-Party Notices…", systemImage: "doc.text")
        }
        .disabled(noticesURL == nil)

        Divider()

        Button("Quit GLKB Cite") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var noticesURL: URL? {
        Bundle.main.url(
            forResource: "THIRD-PARTY-NOTICES",
            withExtension: "txt"
        )
    }
}
