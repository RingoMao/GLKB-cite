import AppKit
import Combine
import CryptoKit
import Foundation
import GLKBCiteCore

public enum ResultPanelPhase: Equatable, Sendable {
    case idle
    case loading
    case completed
    case failed
}

/// Machine-readable classification of the last failure, so the UI can offer
/// the right recovery action without matching English substrings.
public enum FailureKind: Equatable, Sendable {
    case invalidKey
    case missingKey
    case accessibility
    case rateLimited
    case invalidSelection
    case other
}

@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public private(set) var phase: ResultPanelPhase = .idle
    @Published public private(set) var selection: SelectionContext?
    @Published public private(set) var result: LiteratureResult?
    @Published public private(set) var progressStep = ""
    @Published public private(set) var progressContent: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var failureKind: FailureKind?
    @Published public private(set) var hasStoredAPIKey = false
    /// The stored key masked for display (prefix and last four characters),
    /// cached so views never hit the Keychain per render.
    @Published public private(set) var maskedStoredAPIKey: String?
    @Published public private(set) var citeReference: LiteratureReference?
    @Published public private(set) var toastMessage: String?
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unavailable
    @Published public private(set) var shortcutRegistrationReport = GlobalHotKeyRegistrationReport()
    @Published public private(set) var shortcutStatusMessage: String?

    public let settings: AppSettings
    public let updateController: UpdateController
    public var canRetryLastQuery: Bool { lastQuery != nil && phase != .loading }

    private let permissionManager: any AccessibilityPermissionManaging
    private let selectionProvider: any AsyncSystemSelectionCapturing
    private let hotKeyManager: any GlobalHotKeyProviding
    private let keyStore: any GLKBAPIKeyStoring
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let servicesProvider: any GLKBCiteServicesProviding
    private let automaticSelectionMonitor: any AutomaticSelectionMonitoring
    private let glkbCache = InMemoryLiteratureCache(maximumEntries: 20)
    // Shared across queries so simultaneous identical requests are actually
    // deduplicated (a per-query instance can never see a concurrent caller).
    private let glkbInFlight = InFlightLiteratureRequests()

    private lazy var resultPanelController = ResultPanelController(coordinator: self)
    private lazy var badgePanelController = SelectionBadgePanelController(coordinator: self)
    private lazy var onboardingWindowController = OnboardingWindowController(coordinator: self)
    private lazy var settingsWindowController = CiteSettingsWindowController(coordinator: self)
    private lazy var citePanelController = CitePanelController(coordinator: self)
    private var toastTask: Task<Void, Never>?
    private var automaticCandidate: AutomaticSelectionCandidate?
    private var candidateExpiryTask: Task<Void, Never>?
    private var selectionCaptureTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var activeQueryID: UUID?
    private var activeQuery: LiteratureQuery?
    private var lastQuery: LiteratureQuery?
    private var hasStarted = false

    public init(
        settings: AppSettings? = nil,
        permissionManager: (any AccessibilityPermissionManaging)? = nil,
        selectionProvider: (any AsyncSystemSelectionCapturing)? = nil,
        hotKeyManager: (any GlobalHotKeyProviding)? = nil,
        keyStore: any GLKBAPIKeyStoring = KeychainGLKBAPIKeyStore(),
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil,
        servicesProvider: (any GLKBCiteServicesProviding)? = nil,
        updateController: UpdateController? = nil
    ) {
        let resolvedSettings = settings ?? AppSettings()
        let resolvedPermissionManager = permissionManager ?? AccessibilityPermissionManager()
        let resolvedSelectionProvider: any AsyncSystemSelectionCapturing
        if let selectionProvider {
            resolvedSelectionProvider = selectionProvider
        } else {
            let accessibility = AccessibilitySelectionProvider(
                permissionManager: resolvedPermissionManager
            )
            resolvedSelectionProvider = CompositeSelectionProvider(
                accessibility: accessibility,
                compatibilityEnabled: { resolvedSettings.compatibilityCaptureEnabled }
            )
        }

        self.settings = resolvedSettings
        self.permissionManager = resolvedPermissionManager
        self.selectionProvider = resolvedSelectionProvider
        self.hotKeyManager = hotKeyManager ?? GlobalHotKeyManager()
        self.keyStore = keyStore
        self.launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        self.servicesProvider = servicesProvider ?? GLKBCiteServicesProvider()
        self.updateController = updateController ?? UpdateController()
        automaticSelectionMonitor = AutomaticSelectionMonitor(
            selectionProvider: resolvedSelectionProvider,
            // A badge may be offered for apps with no Accessibility text only
            // when the user has consented to the temporary-Copy fallback,
            // because clicking that badge is what runs it.
            provisionalBadgeEnabled: { resolvedSettings.compatibilityCaptureEnabled }
        )
        refreshCredentialStatus()
        refreshLaunchAtLoginStatus()
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        servicesProvider.install { [weak self] event in
            self?.dispatch(context: event.selection)
        }
        do {
            let report = try hotKeyManager.register { [weak self] in self?.captureCitations() }
            shortcutRegistrationReport = report
            if case .unavailable(let status) = report.availability {
                shortcutStatusMessage = GlobalHotKeyError.shortcutUnavailable(status).localizedDescription
            } else {
                shortcutStatusMessage = nil
            }
        } catch {
            shortcutRegistrationReport = .init()
            shortcutStatusMessage = error.localizedDescription
        }
        synchronizeAutomaticSelectionMonitor()
        refreshCredentialStatus()
        refreshLaunchAtLoginStatus()
        if !settings.hasCompletedOnboarding {
            onboardingWindowController.show()
        } else if !permissionManager.isTrusted {
            // Setup is already complete, so nothing else would ever ask again.
            // Trust can be revoked by the user or invalidated by macOS when the
            // app binary changes, and without it every capture fails silently —
            // so prompt instead of appearing broken.
            CaptureDiagnostics.log("start: accessibility not trusted, prompting")
            _ = permissionManager.checkTrust(promptIfNeeded: true)
        }
    }

    public func stop() {
        invalidateCurrentQuery()
        selectionCaptureTask?.cancel()
        candidateExpiryTask?.cancel()
        automaticSelectionMonitor.stop()
        automaticCandidate = nil
        hotKeyManager.unregister()
        servicesProvider.uninstall()
        badgePanelController.dismiss()
        hasStarted = false
        Task { await glkbCache.removeAll() }
    }

    public func captureCitations() {
        automaticCandidate = nil
        badgePanelController.dismiss()
        selectionCaptureTask?.cancel()
        selectionCaptureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let captured = try await selectionProvider.captureSelection(allowCompatibility: true)
                try Task.checkCancellation()
                dispatch(systemSelection: captured)
            } catch is CancellationError {
                return
            } catch {
                handleSelectionCaptureFailure(error)
            }
        }
    }

    public func handleAutomaticAction() {
        guard let candidate = automaticCandidate else { return }
        automaticCandidate = nil
        candidateExpiryTask?.cancel()
        badgePanelController.dismiss()
        Task { [weak self] in
            guard let self else { return }
            switch candidate {
            case .captured(let selection):
                guard await selectionProvider.isStillValid(selection) else {
                    handleSelectionCaptureFailure(SelectionCaptureError.staleSelection)
                    return
                }
                dispatch(systemSelection: selection)
            case .provisional(let source):
                // The badge click is the explicit request; only now may the
                // guarded temporary-Copy fallback read the selection — and
                // only from the app the gesture happened in.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                    handleSelectionCaptureFailure(SelectionCaptureError.staleSelection)
                    return
                }
                do {
                    let captured = try await selectionProvider.captureSelection(
                        allowCompatibility: true,
                        expectedProcess: source.processIdentifier
                    )
                    dispatch(systemSelection: captured)
                } catch {
                    handleSelectionCaptureFailure(error)
                }
            }
        }
    }

    /// Standard About panel; the credits carry a link to the bundled
    /// third-party notices so they stay one click away without a menu item.
    public func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let noticesURL = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt") {
            let credits = NSMutableAttributedString(
                string: "Literature evidence for the text you select.\n",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            )
            credits.append(NSAttributedString(
                string: "Third-party notices",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .link: noticesURL]
            ))
            options[.credits] = credits
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: Cite modal and toast

    public func presentCite(_ reference: LiteratureReference) {
        citeReference = reference
        citePanelController.show(over: resultPanelController.frame)
    }

    public func dismissCite() {
        citeReference = nil
        citePanelController.hide()
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    public func retryLastQuery() {
        guard let lastQuery else { return }
        run(lastQuery, anchoredTo: selection?.bounds)
    }

    public func cancelQuery() {
        let wasLoading = phase == .loading
        invalidateCurrentQuery()
        if wasLoading {
            phase = .failed
            errorMessage = LiteratureError.cancelled.localizedDescription
            failureKind = .other
        }
    }

    public func hideResultPanel() {
        dismissCite()
        resultPanelController.hide()
    }

    public func showSettings() {
        settingsWindowController.show()
    }

    public func showOnboarding() { onboardingWindowController.show() }

    /// Returns false when setup cannot finish yet (no Accessibility trust or
    /// no stored key) so the caller can say so instead of failing silently.
    @discardableResult
    public func completeOnboarding() -> Bool {
        refreshCredentialStatus()
        guard permissionManager.isTrusted, hasStoredAPIKey else { return false }
        // Apply the recommended defaults only on the first completion so a
        // later pass through Setup never silently re-enables features the
        // user explicitly turned off.
        if !settings.hasCompletedOnboarding {
            settings.compatibilityCaptureEnabled = true
            settings.automaticSelectionEnabled = true
            settings.hasCompletedOnboarding = true
        }
        synchronizeAutomaticSelectionMonitor()
        onboardingWindowController.close()
        return true
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        permissionManager.checkTrust(promptIfNeeded: true)
    }

    public func openAccessibilitySettings() { permissionManager.openAccessibilitySettings() }
    public var isAccessibilityTrusted: Bool { permissionManager.isTrusted }

    public func saveAPIKey(_ value: String) throws {
        try keyStore.saveAPIKey(value)
        refreshCredentialStatus()
    }

    public func deleteAPIKey() throws {
        try keyStore.deleteAPIKey()
        refreshCredentialStatus()
    }

    public func refreshCredentialStatus() {
        let key = (try? keyStore.loadAPIKey()) ?? nil
        hasStoredAPIKey = key != nil
        if let key, key.count > 9 {
            let prefix = key.hasPrefix("glkb_") ? "glkb_" : ""
            maskedStoredAPIKey = prefix + String(repeating: "\u{2022}", count: 12) + String(key.suffix(4))
        } else {
            maskedStoredAPIKey = nil
        }
    }

    public func setAutomaticSelectionEnabled(_ enabled: Bool) {
        settings.automaticSelectionEnabled = enabled
        // The monitor only runs after setup; if the user turned the badge on
        // before finishing, bring setup back rather than silently doing nothing.
        if enabled, !settings.hasCompletedOnboarding {
            onboardingWindowController.show()
        }
        synchronizeAutomaticSelectionMonitor()
    }

    public func setCompatibilityCaptureEnabled(_ enabled: Bool) {
        settings.compatibilityCaptureEnabled = enabled
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        try launchAtLoginManager.setEnabled(enabled)
        refreshLaunchAtLoginStatus()
    }

    public func refreshLaunchAtLoginStatus() { launchAtLoginStatus = launchAtLoginManager.status }
    public func openLoginItemsSettings() { launchAtLoginManager.openLoginItemsSettings() }

    public func copyPlainReport() {
        guard let result else { return }
        let plain = LiteratureReportFormatter.plainText(result, includeEvidence: settings.includeEvidence)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain, forType: .string)
    }

    public func copyRichReport() {
        guard let result else { return }
        let plain = LiteratureReportFormatter.plainText(result, includeEvidence: settings.includeEvidence)
        let html = LiteratureReportFormatter.html(result, includeEvidence: settings.includeEvidence)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.html, .string], owner: nil)
        NSPasteboard.general.setString(html, forType: .html)
        NSPasteboard.general.setString(plain, forType: .string)
    }

    public func openReference(_ reference: LiteratureReference) {
        guard let url = PubMed.url(for: reference.pmid) ?? reference.url else { return }
        NSWorkspace.shared.open(url)
    }

    public func checkForUpdates() { updateController.checkForUpdates() }

    private func dispatch(systemSelection: SystemSelection) {
        dispatch(context: systemSelection.context)
    }

    private func dispatch(context: SelectionContext) {
        do {
            let normalized = try LiteratureInputValidator.normalize(context.selectedText)
            var normalizedContext = context
            normalizedContext.selectedText = normalized
            selection = normalizedContext
            result = nil
            errorMessage = nil
            run(
                LiteratureQuery(text: normalized, options: settings.queryOptions),
                anchoredTo: normalizedContext.bounds
            )
        } catch {
            selection = nil
            result = nil
            lastQuery = nil
            showError(error.localizedDescription, kind: .invalidSelection)
        }
    }

    private func handleSelectionCaptureFailure(_ error: Error) {
        invalidateCurrentQuery()
        selection = nil
        result = nil
        lastQuery = nil
        showError(error.localizedDescription, kind: classify(error))
    }

    private func run(_ query: LiteratureQuery, anchoredTo anchor: ScreenRect?) {
        if phase == .loading, activeQuery == query {
            resultPanelController.show(anchor: anchor)
            return
        }
        invalidateCurrentQuery()
        let queryID = UUID()
        activeQueryID = queryID
        activeQuery = query
        lastQuery = query
        phase = .loading
        result = nil
        errorMessage = nil
        failureKind = nil
        progressStep = "Searching GLKB"
        progressContent = nil
        resultPanelController.show(anchor: anchor)

        do {
            let backend = try makeBackend()
            queryTask = Task { [weak self] in
                guard let self else { return }
                do {
                    var receivedCompletion = false
                    for try await event in backend.query(query) {
                        try Task.checkCancellation()
                        guard activeQueryID == queryID else { return }
                        switch event {
                        case let .progress(step, content):
                            progressStep = step
                            progressContent = content
                        case .completed(let completedResult):
                            receivedCompletion = true
                            result = completedResult
                            phase = .completed
                            progressStep = ""
                            progressContent = nil
                        }
                    }
                    guard activeQueryID == queryID else { return }
                    activeQueryID = nil
                    activeQuery = nil
                    queryTask = nil
                    if !receivedCompletion { showError("GLKB finished without usable citations.") }
                } catch {
                    guard activeQueryID == queryID else { return }
                    activeQueryID = nil
                    activeQuery = nil
                    queryTask = nil
                    let cancelled = error is CancellationError || (error as? LiteratureError) == .cancelled
                    if cancelled {
                        phase = .failed
                        errorMessage = LiteratureError.cancelled.localizedDescription
                        failureKind = .other
                    } else {
                        showError(friendlyMessage(for: error), kind: classify(error))
                    }
                }
            }
        } catch {
            activeQueryID = nil
            activeQuery = nil
            showError(friendlyMessage(for: error), kind: classify(error))
        }
    }

    private func invalidateCurrentQuery() {
        activeQueryID = nil
        activeQuery = nil
        queryTask?.cancel()
        queryTask = nil
    }

    private func makeBackend() throws -> any LiteratureBackend {
        let storedKey = try keyStore.loadAPIKey()
        let keyStore = self.keyStore
        let backend = GLKBBackend {
            guard let key = try keyStore.loadAPIKey() else { throw LiteratureError.missingCredential }
            return key
        }
        return CachingLiteratureBackend(
            backend: backend,
            cache: glkbCache,
            inFlight: glkbInFlight,
            endpointScope: GLKBBackend.defaultEndpoint.absoluteString,
            credentialScope: credentialScope(for: storedKey)
        )
    }

    private func synchronizeAutomaticSelectionMonitor() {
        guard settings.hasCompletedOnboarding, settings.automaticSelectionEnabled else {
            automaticSelectionMonitor.stop()
            invalidateAutomaticCandidate()
            return
        }
        automaticSelectionMonitor.start(
            handler: { [weak self] event in self?.presentAutomaticCandidate(event) },
            invalidationHandler: { [weak self] in self?.invalidateAutomaticCandidate() }
        )
    }

    private func presentAutomaticCandidate(_ event: AutomaticSelectionEvent) {
        automaticCandidate = event.candidate
        badgePanelController.show(event: event)
        candidateExpiryTask?.cancel()
        candidateExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.invalidateAutomaticCandidate()
        }
    }

    private func invalidateAutomaticCandidate() {
        candidateExpiryTask?.cancel()
        candidateExpiryTask = nil
        automaticCandidate = nil
        badgePanelController.dismiss()
    }

    private func showError(_ message: String, kind: FailureKind = .other) {
        phase = .failed
        errorMessage = message
        failureKind = kind
        progressStep = ""
        progressContent = nil
        resultPanelController.show(anchor: selection?.bounds)
    }

    private func classify(_ error: Error) -> FailureKind {
        if let captureError = error as? SelectionCaptureError {
            switch captureError {
            case .accessibilityPermissionRequired, .accessibilityFailure:
                return .accessibility
            case .emptySelection, .staleSelection, .secureField:
                return .invalidSelection
            case .selectionUnavailable, .focusedElementUnavailable:
                return .other
            }
        }
        guard let literatureError = error as? LiteratureError else { return .other }
        switch literatureError {
        case .missingCredential:
            return .missingKey
        case .requestFailed(statusCode: 401, _), .requestFailed(statusCode: 403, _):
            return .invalidKey
        case .requestFailed(statusCode: 429, _):
            return .rateLimited
        case .requestFailed(statusCode: 422, _):
            return .invalidSelection
        default:
            return .other
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        guard let literatureError = error as? LiteratureError else { return error.localizedDescription }
        return switch literatureError {
        case .requestFailed(statusCode: 401, _), .requestFailed(statusCode: 403, _):
            "GLKB rejected this API key. Replace it with an active glkb_ key in Settings."
        case .requestFailed(statusCode: 429, _):
            "GLKB declined this request because usage or rate limits were reached. Check the account before retrying."
        case .requestFailed(statusCode: 422, let message):
            message.map { "GLKB rejected the selected sentence: \($0)" }
                ?? "GLKB rejected the selected sentence."
        case .requestFailed(statusCode: 502, _):
            "The GLKB citation service is temporarily unavailable. Try once more in a moment."
        case .requestFailed(statusCode: 504, _):
            "The GLKB citation search exceeded its server timeout. Try once more."
        default:
            literatureError.localizedDescription
        }
    }

#if DEBUG
    /// Preview/test support: seed panel state without any capture or network
    /// activity so SwiftUI previews and snapshot tests can render each state.
    func seedPreviewState(
        phase: ResultPanelPhase,
        result: LiteratureResult? = nil,
        selection: SelectionContext? = nil,
        errorMessage: String? = nil,
        failureKind: FailureKind? = nil,
        progressStep: String = "",
        citeReference: LiteratureReference? = nil,
        toastMessage: String? = nil
    ) {
        self.phase = phase
        self.result = result
        self.selection = selection
        self.errorMessage = errorMessage
        self.failureKind = failureKind
        self.progressStep = progressStep
        self.citeReference = citeReference
        self.toastMessage = toastMessage
    }
#endif

    private func credentialScope(for key: String?) -> String {
        guard let key else { return "missing" }
        return SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
