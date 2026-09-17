import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var step = 0
    @State private var apiKey = ""
    @State private var message: String?
    @State private var accessibilityTrusted = false

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 46, leading: 46, bottom: 26, trailing: 46))

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 520, height: 500)
        .background(Theme.cardSurface)
        .onAppear {
            coordinator.refreshCredentialStatus()
            refreshAccessibility()
        }
        .task(id: step) {
            // While the Accessibility step is visible, poll trust so the
            // state flips as soon as the user grants access in System
            // Settings and returns.
            guard step == 1 || step == stepCount - 1 else { return }
            while !Task.isCancelled {
                refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: accessibilityStep
        case 2: keyStep
        default: privacyStep
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        StepLayout(
            title: "Welcome to GLKB Cite",
            description: "Select scientific text in any app, press ⌥⌘G or click the badge, and GLKB returns PubMed literature evidence you can cite."
        ) {
            InfoCard {
                InfoRow(bold: "Select", rest: "a sentence with a scientific claim.")
                InfoRow(bold: "Invoke", rest: "the hot key, the badge, or the Services menu.")
                InfoRow(bold: "Cite", rest: "the returned PubMed references in one click.")
            }
        }
    }

    private var accessibilityStep: some View {
        StepLayout(
            title: "Allow selected-text access",
            description: "Accessibility lets GLKB Cite read only the selection you invoke and position its result panel. Secure fields are always rejected."
        ) {
            InfoCard {
                InfoRow(bold: "Step 2 of 4", rest: "— Accessibility required")
                InfoRow(rest: "macOS Settings ▸ Privacy & Security ▸ Accessibility")
                if accessibilityTrusted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        Text("Access granted — you're all set.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                } else {
                    InfoRow(prefix: "Enable ", bold: "GLKB Cite", rest: " in the list, then return here.")
                }
            }
        }
    }

    private var keyStep: some View {
        StepLayout(
            title: "Store your GLKB key",
            description: "The glkb_ key is stored in the macOS Keychain and sent only to the GLKB endpoint."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.hasStoredAPIKey ? "GLKB API key — stored securely" : "GLKB API key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    SecureField(
                        coordinator.hasStoredAPIKey ? "Enter a replacement key (optional)" : "glkb_…",
                        text: $apiKey
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.insetSurface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))

                    Button("Save") { saveKey() }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 380)
        }
    }

    private var privacyStep: some View {
        StepLayout(
            title: "Compatibility Capture and privacy",
            description: "If Accessibility cannot read a selection, GLKB Cite may briefly send Copy, read the text, and restore the clipboard. You can disable this in Privacy Settings."
        ) {
            InfoCard {
                InfoRow(bold: "Sends text only when you ask", rest: "— badge appearance alone never contacts GLKB.")
                InfoRow(bold: "No analytics", rest: "and no persistent query history.")
                InfoRow(bold: "Clipboard note", rest: "— clipboard-history utilities may observe the temporary Copy value.")
            }
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Theme.accent : Theme.hairline)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                switch step {
                case 1 where !accessibilityTrusted:
                    Button("Open System Settings") { coordinator.openAccessibilitySettings() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Request Access") {
                        _ = coordinator.requestAccessibilityPermission()
                        refreshAccessibility()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                case stepCount - 1:
                    Button("Finish Setup") {
                        if !coordinator.completeOnboarding() {
                            refreshAccessibility()
                            message = "Grant Accessibility access and save a GLKB key before finishing setup."
                        }
                    }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!accessibilityTrusted || !coordinator.hasStoredAPIKey)
                default:
                    Button("Continue") { advance() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(step == 2 && !coordinator.hasStoredAPIKey)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 46, bottom: 26, trailing: 46))
    }

    private func advance() {
        message = nil
        step = min(step + 1, stepCount - 1)
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

    private func refreshAccessibility() {
        accessibilityTrusted = coordinator.isAccessibilityTrusted
    }
}

// MARK: - Layout pieces

private struct StepLayout<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            GLKBMark()
                .fill(Theme.accent)
                .frame(width: 30, height: 30)
                .frame(width: 52, height: 52)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .padding(.bottom, 10)

            Text(description)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)
                .padding(.bottom, 22)

            content
        }
    }
}

private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: 380, alignment: .leading)
        .background(Theme.insetSurface, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.hairline)
        )
    }
}

private struct InfoRow: View {
    var prefix: String = ""
    var bold: String?
    let rest: String

    var body: some View {
        (Text(prefix).font(.system(size: 11.5))
         + Text(bold.map { prefix.isEmpty ? "\($0) " : $0 } ?? "")
            .font(.system(size: 11.5, weight: .bold)).foregroundColor(.primary)
         + Text(rest).font(.system(size: 11.5)))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
