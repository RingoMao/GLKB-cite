import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var apiKey = ""
    @State private var message: String?
    @State private var accessibilityTrusted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to GLKB Cite")
                        .font(.largeTitle.weight(.semibold))
                    Text("Literature evidence for the text you select")
                        .foregroundStyle(.secondary)
                }
            }

            SetupStep(
                number: 1,
                title: "Allow selected-text access",
                detail: "Accessibility lets GLKB Cite read only the selection you invoke and position its result panel. Secure fields are always rejected."
            ) {
                HStack {
                    Label(
                        accessibilityTrusted ? "Enabled" : "Not enabled",
                        systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "circle"
                    )
                    Spacer()
                    Button(accessibilityTrusted ? "Open Settings" : "Request Access") {
                        if accessibilityTrusted {
                            coordinator.openAccessibilitySettings()
                        } else {
                            _ = coordinator.requestAccessibilityPermission()
                            accessibilityTrusted = coordinator.isAccessibilityTrusted
                        }
                    }
                }
            }

            SetupStep(
                number: 2,
                title: "Store your GLKB key",
                detail: "The glkb_ key remains in the new GLKB Cite macOS Keychain identity and is required to finish setup."
            ) {
                HStack {
                    SecureField(
                        coordinator.hasStoredAPIKey ? "GLKB key is already stored" : "glkb_…",
                        text: $apiKey
                    )
                    Button("Save") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            SetupStep(
                number: 3,
                title: "Understand Compatibility Capture",
                detail: "If Accessibility cannot read selected text, GLKB Cite may temporarily send Copy, read the clipboard, and restore it. Clipboard-history tools may record the transient text, and newer clipboard data is never overwritten. You can disable this later in Privacy Settings."
            ) {
                EmptyView()
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("After you click the badge or invoke ⌥⌘G, selected text is sent to GLKB. Badge appearance alone never contacts GLKB. GLKB Cite has no analytics or persistent query history.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Privacy Settings") { coordinator.showSettings() }
                Spacer()
                Button("Finish Setup") { coordinator.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!accessibilityTrusted || !coordinator.hasStoredAPIKey)
            }
        }
        .padding(26)
        .frame(width: 560, height: 620)
        .onAppear {
            coordinator.refreshCredentialStatus()
            accessibilityTrusted = coordinator.isAccessibilityTrusted
        }
    }

    private func saveKey() {
        do {
            try coordinator.saveAPIKey(apiKey)
            apiKey = ""
            message = "GLKB API key saved securely."
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(.tint, in: Circle())
                .foregroundStyle(Color(nsColor: .selectedMenuItemTextColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
