import GLKBCiteCore
import SwiftUI

/// Settings window: sidebar with General / Literature / Privacy, row-based
/// panes. Sections and rows follow the product mockup.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    private enum Pane: String, CaseIterable {
        case general = "General"
        case literature = "Literature"
        case privacy = "Privacy"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .literature: return "text.book.closed"
            case .privacy: return "hand.raised"
            }
        }
    }

    @State private var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            ScrollView {
                Group {
                    switch pane {
                    case .general:
                        GeneralSettingsPane()
                    case .literature:
                        LiteratureSettingsPane()
                    case .privacy:
                        PrivacySettingsPane()
                    }
                }
                .padding(EdgeInsets(top: 22, leading: 26, bottom: 22, trailing: 26))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.cardSurface)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases, id: \.rawValue) { item in
                Button {
                    pane = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .background(
                                pane == item ? Color.white.opacity(0.22) : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        Text(item.rawValue)
                            .font(.system(size: 12.5))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .foregroundStyle(pane == item ? Color.white : Color.secondary)
                    .background(
                        pane == item ? Theme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        .frame(width: 158)
        .background(Theme.insetSurface)
    }
}

// MARK: - Shared building blocks

private struct SettingsGroup<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
            content
        }
        .padding(.bottom, 22)
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    var description: String?
    var showDivider = true
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .medium))
                    if let description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .frame(maxWidth: 340, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                control
            }
            .padding(.vertical, 10)
            if showDivider {
                Divider().overlay(Theme.hairline)
            }
        }
    }
}

private struct AccentToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)
    }
}

private struct SelectPill<SelectionValue: Hashable, Options: View>: View {
    @Binding var selection: SelectionValue
    @ViewBuilder let options: Options

    var body: some View {
        Picker("", selection: $selection) { options }
            .labelsHidden()
            .fixedSize()
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var launchMessage: String?

    var body: some View {
        SettingsGroup(label: "Selection") {
            SettingsRow(
                label: "Show automatic selection badge (Beta)",
                description: "Automatic mode observes selection gestures locally and never starts a GLKB request until you click the badge."
            ) {
                AccentToggle(isOn: Binding(
                    get: { settings.automaticSelectionEnabled },
                    set: { coordinator.setAutomaticSelectionEnabled($0) }
                ))
            }

            SettingsRow(label: "Hot key", description: shortcutDescription) {
                Text("⌥⌘G")
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Theme.insetSurface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))
            }

            SettingsRow(label: "Launch at login", description: launchMessage, showDivider: false) {
                VStack(alignment: .trailing, spacing: 6) {
                    AccentToggle(isOn: Binding(
                        get: { coordinator.launchAtLoginStatus == .enabled },
                        set: { enabled in
                            do {
                                try coordinator.setLaunchAtLoginEnabled(enabled)
                                launchMessage = nil
                            } catch {
                                launchMessage = error.localizedDescription
                            }
                        }
                    ))
                    .disabled(coordinator.launchAtLoginStatus == .unavailable)
                    if coordinator.launchAtLoginStatus == .requiresApproval {
                        Button("Approve in Login Items") {
                            coordinator.openLoginItemsSettings()
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
            }
        }
        .onAppear { coordinator.refreshLaunchAtLoginStatus() }
    }

    private var shortcutDescription: String {
        var text = "Press ⌥⌘G to find citations."
        if case .unavailable = coordinator.shortcutRegistrationReport.availability {
            text += " The shortcut is currently unavailable — quit other apps that register ⌥⌘G."
        }
        return text
    }
}

// MARK: - Literature

private struct LiteratureSettingsPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var keyEntry = ""
    @State private var keyMessage: String?

    var body: some View {
        SettingsGroup(label: "API key") {
            VStack(alignment: .leading, spacing: 3) {
                Text("GLKB API key")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Stored in macOS Keychain and sent only to the GLKB endpoint.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    SecureField(coordinator.maskedStoredAPIKey ?? "glkb_…", text: $keyEntry)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 220)
                        .background(Theme.insetSurface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline))

                    Button("Save") { saveKey() }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .disabled(keyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 5)
                if let keyMessage {
                    Text(keyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        }

        SettingsGroup(label: "Results") {
            SettingsRow(label: "Include evidence excerpts") {
                AccentToggle(isOn: $settings.includeEvidence)
            }

            SettingsRow(
                label: "Cache duration",
                description: "The cache exists only in memory and is cleared when GLKB Cite exits.",
                showDivider: false
            ) {
                SelectPill(selection: $settings.cacheDurationMinutes) {
                    Text("Off").tag(0)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("1 hour").tag(60)
                }
            }
        }
        .onAppear { coordinator.refreshCredentialStatus() }
    }

    private func saveKey() {
        do {
            try coordinator.saveAPIKey(keyEntry)
            keyEntry = ""
            keyMessage = nil
        } catch {
            keyMessage = error.localizedDescription
        }
    }
}

// MARK: - Privacy

private struct PrivacySettingsPane: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsGroup(label: "Compatibility capture") {
            SettingsRow(
                label: "Allow temporary Copy fallback",
                description: "If Accessibility cannot read a selection, GLKB Cite may temporarily send Copy and then restore the previous clipboard content. Clipboard-history utilities can still observe that temporary value.",
                showDivider: false
            ) {
                AccentToggle(isOn: Binding(
                    get: { settings.compatibilityCaptureEnabled },
                    set: { coordinator.setCompatibilityCaptureEnabled($0) }
                ))
            }
        }

        SettingsGroup(label: "Data") {
            SettingsRow(
                label: "Sent only after you click Find Citations or invoke an explicit command.",
                description: "Badge appearance alone never contacts GLKB. GLKB Cite has no analytics or persistent query history.",
                showDivider: false
            ) {
                EmptyView()
            }
        }
    }
}
