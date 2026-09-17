import AppKit
import GLKBCiteCore
import SwiftUI
import XCTest
@testable import GLKBCiteMac

/// Opt-in visual QA: renders each redesigned surface to PNG files so the
/// design can be reviewed without launching the full app.
///
/// Skipped unless `RENDER_UI_SNAPSHOTS=1` (and `SNAPSHOT_DIR` optionally
/// points at an output directory), so CI stays headless-safe.
@MainActor
final class UISnapshotRenderTests: XCTestCase {
    private var outputDirectory: URL!

    func testRenderAllSurfaces() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RENDER_UI_SNAPSHOTS"] == "1",
            "Set RENDER_UI_SNAPSHOTS=1 to render UI snapshots."
        )
        let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]
            ?? NSTemporaryDirectory().appending("glkb-cite-snapshots")
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )
        let coordinator = makeCoordinator()

        coordinator.seedPreviewState(
            phase: .completed,
            result: sampleResult,
            selection: sampleSelection
        )
        try render(panel(coordinator), name: "result-panel-results", appearance: .aqua)
        try render(panel(coordinator), name: "result-panel-results-dark", appearance: .darkAqua)

        coordinator.seedPreviewState(phase: .loading, progressStep: "Searching GLKB")
        try render(panel(coordinator), name: "result-panel-loading", appearance: .aqua)

        coordinator.seedPreviewState(
            phase: .completed,
            result: LiteratureResult(answer: "", references: [])
        )
        try render(panel(coordinator), name: "result-panel-empty", appearance: .aqua)

        coordinator.seedPreviewState(
            phase: .failed,
            errorMessage: "GLKB rejected this API key. Replace it with an active glkb_ key in Settings.",
            failureKind: .invalidKey
        )
        try render(panel(coordinator), name: "result-panel-badkey", appearance: .aqua)

        coordinator.seedPreviewState(
            phase: .completed,
            result: sampleResult,
            citeReference: sampleResult.references[0],
            toastMessage: "MLA citation copied to clipboard"
        )
        try render(
            CitePanelView().environmentObject(coordinator).padding(30),
            name: "cite-panel",
            appearance: .aqua
        )
        try render(panel(coordinator), name: "result-panel-dimmed-for-cite", appearance: .aqua)

        try render(
            SelectionBadgeView(onFindCitations: {}).padding(24),
            name: "selection-badge",
            appearance: .aqua
        )

        try render(
            OnboardingView()
                .environmentObject(coordinator),
            name: "onboarding",
            appearance: .aqua
        )

        try render(
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .frame(width: 640, height: 480),
            name: "settings",
            appearance: .aqua
        )
    }

    // MARK: Fixtures

    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            settings: AppSettings(defaults: UserDefaults(suiteName: "ui-snapshots")!),
            keyStore: SnapshotKeyStore()
        )
    }

    private func panel(_ coordinator: AppCoordinator) -> some View {
        ResultPanelView()
            .environmentObject(coordinator)
            .environmentObject(coordinator.settings)
            .padding(30)
    }

    private var sampleSelection: SelectionContext {
        SelectionContext(
            selectedText: "Type I interferon signaling in pancreatic β-cells precedes measurable islet autoimmunity in genetically at-risk individuals.",
            sourceApplicationName: "Preview"
        )
    }

    private var sampleResult: LiteratureResult {
        LiteratureResult(
            answer: "",
            references: [
                LiteratureReference(
                    pmid: "38291045",
                    title: "Type I interferon signaling precedes islet autoimmunity in early-stage type 1 diabetes",
                    authors: ["Chen J", "Rodriguez M", "Patel S"],
                    journal: "Cell Reports Medicine",
                    date: "2024",
                    citationCount: 87,
                    relevanceReason: "Direct evidence",
                    evidence: [LiteratureEvidence(quote: "elevated ISG expression in pancreatic β-cells was detected months before seroconversion to islet autoantibodies, supporting a role for early IFN-I signaling in disease initiation.")]
                ),
                LiteratureReference(
                    pmid: "37012298",
                    title: "ADCY3 variants modulate β-cell cAMP signaling and interferon-stimulated gene expression",
                    authors: ["Okafor T", "Lindqvist A"],
                    journal: "Diabetes",
                    date: "2023",
                    citationCount: 34,
                    evidence: [LiteratureEvidence(quote: "rs2033654 in ADCY3 was associated with reduced glucose-stimulated insulin secretion and altered interferon-stimulated gene induction in human islet organoids.")]
                ),
                LiteratureReference(
                    pmid: "35789012",
                    title: "Interferon pathways in autoimmune diabetes: a systematic review",
                    authors: ["Fischer K", "Wang L"],
                    journal: "Nature Reviews Endocrinology",
                    date: "2022",
                    citationCount: 210,
                    evidence: [LiteratureEvidence(quote: "across the reviewed cohorts, type I interferon activation was a recurring but not universal feature preceding clinical onset.")]
                ),
            ]
        )
    }

    // MARK: Rendering

    private func render(
        _ view: some View,
        name: String,
        appearance: NSAppearance.Name
    ) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(size.width, 10), height: max(size.height, 10))
        )

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let onAppear-driven entrance animations settle before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return XCTFail("Could not create bitmap for \(name)")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode PNG for \(name)")
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("snapshot: \(url.path)")
    }
}

private final class SnapshotKeyStore: GLKBAPIKeyStoring, @unchecked Sendable {
    var key: String? = "glkb_snapshot"
    func saveAPIKey(_ value: String) throws { key = value }
    func loadAPIKey() throws -> String? { key }
    func deleteAPIKey() throws { key = nil }
}
