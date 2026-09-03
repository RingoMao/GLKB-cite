import SwiftUI

@main
struct GLKBCiteApp: App {
    @NSApplicationDelegateAdaptor(GLKBCiteAppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        } label: {
            MenuBarTemplateIcon()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .frame(width: 560, height: 570)
        }
    }
}

private struct MenuBarTemplateIcon: View {
    var body: some View {
        if let image = Self.templateImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "books.vertical.fill")
        }
    }

    private static let templateImage: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "MenuBarIconTemplate",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
