import GLKBCiteCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsPane()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            LiteratureSettingsPane()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .tabItem { Label("Literature", systemImage: "books.vertical") }

            PrivacySettingsPane()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .padding(16)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var keyEntry = ""
    @State private var keyMessage: String?
    @State private var accessibilityTrusted = false

    var body: some View {
        Form {
            Section("GLKB API key") {
                HStack {
                    SecureField(
                        coordinator.hasStoredAPIKey
                            ? "Enter a replacement glkb_ key"
                            : "glkb_…",
                        text: $keyEntry
                    )
                    Button("Save") { saveKey() }
                        .disabled(keyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if coordinator.hasStoredAPIKey {
                        Button("Remove", role: .destructive) { removeKey() }
                    }
                }
                Label(
                    coordinator.hasStoredAPIKey ? "Stored securely in macOS Keychain" : "No key stored",
                    systemImage: coordinator.hasStoredAPIKey ? "checkmark.shield.fill" : "key"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let keyMessage {
                    Text(keyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Selection access") {
                HStack {
                    Label(
                        accessibilityTrusted ? "Accessibility enabled" : "Accessibility required",
                        systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Request Access") {
                            _ = coordinator.requestAccessibilityPermission()
                            refreshAccessibility()
                        }
                        Button("Open System Settings") {
                            coordinator.openAccessibilitySettings()
                        }
                    }
                }

                Toggle(
                    "Show automatic selection badge (Beta)",
                    isOn: Binding(
                        get: { settings.automaticSelectionEnabled },
                        set: { coordinator.setAutomaticSelectionEnabled($0) }
                    )
                )
                Text("Automatic mode observes selection gestures locally and never starts a GLKB request until you click the badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                LabeledContent("Find citations") {
                    HStack(spacing: 8) {
                        Text("⌥⌘G")
                        shortcutAvailability
                    }
                }
                Text("Quit GLKB Lens while using GLKB Cite because both apps register ⌥⌘G.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let status = coordinator.shortcutStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Startup and updates") {
                Toggle(
                    "Launch GLKB Cite at login",
                    isOn: Binding(
                        get: { coordinator.launchAtLoginStatus == .enabled },
                        set: { enabled in
                            do {
                                try coordinator.setLaunchAtLoginEnabled(enabled)
                            } catch {
                                keyMessage = error.localizedDescription
                            }
                        }
                    )
                )
                .disabled(coordinator.launchAtLoginStatus == .unavailable)

                if coordinator.launchAtLoginStatus == .requiresApproval {
                    Button("Approve in Login Items Settings") {
                        coordinator.openLoginItemsSettings()
                    }
                }

                if coordinator.updateController.isConfigured {
                    Button("Check for Updates…") { coordinator.checkForUpdates() }
                        .disabled(!coordinator.updateController.canCheckForUpdates)
                } else {
                    Text("Automatic updates will be enabled in signed public builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            coordinator.refreshCredentialStatus()
            coordinator.refreshLaunchAtLoginStatus()
            refreshAccessibility()
        }
    }

    private func saveKey() {
        do {
            try coordinator.saveAPIKey(keyEntry)
            keyEntry = ""
            keyMessage = "API key saved."
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try coordinator.deleteAPIKey()
            keyEntry = ""
            keyMessage = "API key removed."
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    private func refreshAccessibility() {
        accessibilityTrusted = coordinator.isAccessibilityTrusted
    }

    @ViewBuilder
    private var shortcutAvailability: some View {
        Group {
        if let availability = coordinator.shortcutRegistrationReport.availability {
            switch availability {
            case .registered:
                Text("Available")
                    .foregroundStyle(.green)
            case .unavailable:
                Text("Unavailable")
                    .foregroundStyle(.orange)
            }
        }
        }
    }
}

private struct LiteratureSettingsPane: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Citation recommendations") {
                Picker("Maximum references", selection: $settings.maxArticles) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("10").tag(10)
                }
                Toggle("Include evidence excerpts", isOn: $settings.includeEvidence)
                Text("The citation endpoint returns references in its own order and does not support ranking or review-only filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cost control") {
                Picker("Repeat-selection cache", selection: $settings.cacheDurationMinutes) {
                    Text("Off").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                }
                Text("The cache exists only in memory and is cleared when GLKB Cite exits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("What leaves this Mac") {
                PrivacyRow(
                    icon: "text.quote",
                    title: "Selected scientific text",
                    detail: "Sent only after you click Find Citations or invoke an explicit command."
                )
                PrivacyRow(
                    icon: "key.fill",
                    title: "Your GLKB key",
                    detail: "Stored in macOS Keychain and sent only to the GLKB endpoint."
                )
            }

            Section("Compatibility Capture") {
                Toggle(
                    "Allow temporary Copy fallback",
                    isOn: Binding(
                        get: { settings.compatibilityCaptureEnabled },
                        set: { coordinator.setCompatibilityCaptureEnabled($0) }
                    )
                )
                Text("When Accessibility cannot read a selection, GLKB Cite can briefly use Copy, read the text, and restore the clipboard. Clipboard history tools may still record the temporary content, and restoration cannot be guaranteed if another app changes the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What GLKB Cite does not collect") {
                Label("No analytics or advertising identifiers", systemImage: "checkmark.circle")
                Label("No selected-text, answer, or credential logs", systemImage: "checkmark.circle")
                Label("No persistent literature-result history", systemImage: "checkmark.circle")
            }

            Section("Research use") {
                Text("GLKB Cite is a literature research assistant, not a clinical decision system. Verify every source before citation, publication, or clinical use.")
                    .foregroundStyle(.secondary)
                Button("Review Setup and Privacy") { coordinator.showOnboarding() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
