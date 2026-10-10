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

/// What the app knows about the stored GLKB key. `unreadable` is distinct
/// from `missing`: a key may exist that the Keychain refused to hand over
/// (locked keychain, denied access prompt), and the UI should say so rather
/// than pretend no key was saved.
public enum CredentialStatus: Equatable, Sendable {
    case missing
    case stored
    case unreadable(String)
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
    @Published public private(set) var credentialStatus: CredentialStatus = .missing
    /// Placeholder shown in the key field when a key is stored. Reveals only
    /// the prefix, never any part of the secret.
    @Published public private(set) var maskedStoredAPIKey: String?
    @Published public private(set) var citeReference: LiteratureReference?
    @Published public private(set) var toastMessage: String?
    /// Whether the results panel is on screen. Cards drop transient hover
    /// state when it goes away, so a hover does not stick until the next show.
    @Published public private(set) var isResultPanelVisible = false
    /// The tallest the results panel may grow on the display it is shown on.
    @Published public private(set) var resultPanelMaxHeight: CGFloat = AppCoordinator.preferredResultPanelHeight
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unavailable
    @Published public private(set) var shortcutRegistrationReport = GlobalHotKeyRegistrationReport()
    @Published public private(set) var shortcutStatusMessage: String?
    /// Set while setup is complete but Accessibility trust is missing (revoked
    /// by the user, or invalidated by macOS after the binary changed).
    @Published public private(set) var accessibilityWarning: String?
    /// Mirrors `UpdateController.pendingUpdateVersion` so menu views that
    /// observe only the coordinator re-render.
    @Published public private(set) var pendingUpdateVersion: String?

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
    /// The one capture in flight, whether started by the hot key, the menu,
    /// or a badge click. Starting a new one cancels it.
    private var selectionCaptureTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var activeQueryID: UUID?
    private var activeQuery: LiteratureQuery?
    private var lastQuery: LiteratureQuery?
    private var hasStarted = false
    private var activationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// Built once per credential and reused across queries so the URLSession
    /// (and its connections) survive between searches.
    private var cachedBackend: (credentialScope: String, backend: any LiteratureBackend)?
    private var credentialScope = "missing"

    /// Non-singleton instances exist for tests. They must not touch the panel
    /// controllers (which retain the coordinator through their hosting views).
    init(
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
        self.updateController.$pendingUpdateVersion
            .sink { [weak self] version in self?.pendingUpdateVersion = version }
            .store(in: &cancellables)
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
        refreshAccessibilityStatus()
        // Trust can also disappear while running; re-check whenever the user
        // switches apps (cheap) so the menu can say so instead of the badge
        // silently never appearing again.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAccessibilityStatus() }
        }
    }

    public func stop() {
        invalidateCurrentQuery()
        selectionCaptureTask?.cancel()
        selectionCaptureTask = nil
        candidateExpiryTask?.cancel()
        automaticSelectionMonitor.stop()
        automaticCandidate = nil
        hotKeyManager.unregister()
        servicesProvider.uninstall()
        badgePanelController.dismiss()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        // A Copy fallback interrupted by termination must not leave the
        // user's clipboard holding the selection instead of their content.
        selectionProvider.restorePendingClipboardIfNeeded()
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
                let captured = try await selectionProvider.captureSelection(
                    SelectionCaptureOptions(allowCompatibility: true, descendantSearch: .thorough)
                )
                try Task.checkCancellation()
                dispatch(systemSelection: captured)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleSelectionCaptureFailure(error)
            }
        }
    }

    public func handleAutomaticAction() {
        guard let candidate = automaticCandidate else { return }
        automaticCandidate = nil
        candidateExpiryTask?.cancel()
        badgePanelController.dismiss()
        // Tracked like every other capture, so a hot key pressed while this is
        // in flight supersedes it instead of racing it for the panel.
        selectionCaptureTask?.cancel()
        selectionCaptureTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch candidate {
                case .captured(let selection):
                    let stillValid = await selectionProvider.isStillValid(selection)
                    try Task.checkCancellation()
                    guard stillValid else { throw SelectionCaptureError.staleSelection }
                    dispatch(systemSelection: selection)
                case .provisional(let source):
                    // The badge click is the explicit request; only now may the
                    // guarded temporary-Copy fallback read the selection — and
                    // only from the app the gesture happened in.
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                        throw SelectionCaptureError.staleSelection
                    }
                    let captured = try await selectionProvider.captureSelection(
                        SelectionCaptureOptions(
                            allowCompatibility: true,
                            expectedProcess: source.processIdentifier,
                            descendantSearch: .thorough
                        )
                    )
                    try Task.checkCancellation()
                    dispatch(systemSelection: captured)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleSelectionCaptureFailure(error)
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
            if let licenseURL = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") {
                credits.append(NSAttributedString(string: "  ·  ", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
                credits.append(NSAttributedString(
                    string: "License",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .link: licenseURL]
                ))
            }
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

    static let preferredResultPanelHeight: CGFloat = 560
    static let minimumResultPanelHeight: CGFloat = 180

    func setResultPanelVisible(_ visible: Bool) {
        if isResultPanelVisible != visible { isResultPanelVisible = visible }
    }

    /// Clamps the panel's height to the usable height of its display, so a
    /// small or mirrored screen never pushes the header off the top.
    func limitResultPanelHeight(toAvailable available: CGFloat) {
        let limit = max(Self.minimumResultPanelHeight, min(Self.preferredResultPanelHeight, available))
        if resultPanelMaxHeight != limit { resultPanelMaxHeight = limit }
    }

    public func showSettings() {
        settingsWindowController.show()
    }

    public func showOnboarding() { onboardingWindowController.show() }

    /// Called when the setup wizard shows its privacy step, where both consent
    /// controls are visible: pre-selects the recommended configuration for a
    /// user who has never chosen, and leaves any earlier choice alone.
    public func prepareOnboardingPrivacyStep() {
        settings.applyRecommendedPrivacyDefaultsIfUnset()
    }

    /// Returns false when setup cannot finish yet (no Accessibility trust or
    /// no stored key) so the caller can say so instead of failing silently.
    /// Finishing setup changes no privacy setting: the wizard's privacy step
    /// shows the controls and whatever they say stands.
    @discardableResult
    public func completeOnboarding() -> Bool {
        refreshCredentialStatus()
        guard permissionManager.isTrusted, hasStoredAPIKey else { return false }
        settings.hasCompletedOnboarding = true
        synchronizeAutomaticSelectionMonitor()
        refreshAccessibilityStatus()
        onboardingWindowController.close()
        return true
    }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        let trusted = permissionManager.checkTrust(promptIfNeeded: true)
        refreshAccessibilityStatus()
        return trusted
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
        let key: String?
        do {
            key = try keyStore.loadAPIKey()
            credentialStatus = key == nil ? .missing : .stored
        } catch {
            key = nil
            credentialStatus = .unreadable(error.localizedDescription)
        }
        hasStoredAPIKey = key != nil
        maskedStoredAPIKey = key == nil ? nil : "glkb_•••••••••••••••• (saved)"
        let scope = Self.credentialScope(for: key)
        if scope != credentialScope {
            credentialScope = scope
            cachedBackend = nil
        }
    }

    public func setAutomaticSelectionEnabled(_ enabled: Bool) {
        // Until setup is complete the monitor cannot run, so do not persist a
        // choice that would show as an inert checked item; bring setup back
        // (its privacy step has the same control) instead.
        guard settings.hasCompletedOnboarding else {
            if enabled { onboardingWindowController.show() }
            return
        }
        settings.automaticSelectionEnabled = enabled
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

        let backend = makeBackend()
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
    }

    private func invalidateCurrentQuery() {
        activeQueryID = nil
        activeQuery = nil
        queryTask?.cancel()
        queryTask = nil
    }

    /// One backend (and URLSession) per credential. The key itself is read
    /// by the backend at request time, off the main actor.
    private func makeBackend() -> any LiteratureBackend {
        if let cachedBackend, cachedBackend.credentialScope == credentialScope {
            return cachedBackend.backend
        }
        let keyStore = self.keyStore
        let backend = GLKBBackend {
            guard let key = try keyStore.loadAPIKey() else { throw LiteratureError.missingCredential }
            return key
        }
        let caching = CachingLiteratureBackend(
            backend: backend,
            cache: glkbCache,
            inFlight: glkbInFlight,
            endpointScope: GLKBBackend.defaultEndpoint.absoluteString,
            credentialScope: credentialScope
        )
        cachedBackend = (credentialScope, caching)
        return caching
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

    private func refreshAccessibilityStatus() {
        guard settings.hasCompletedOnboarding else {
            accessibilityWarning = nil
            return
        }
        if permissionManager.isTrusted {
            if accessibilityWarning != nil { CaptureDiagnostics.log("accessibility: trust restored") }
            accessibilityWarning = nil
        } else if accessibilityWarning == nil {
            CaptureDiagnostics.log("accessibility: trust lost while running")
            accessibilityWarning = "GLKB Cite lost Accessibility access. Re-enable it in System Settings › Privacy & Security › Accessibility."
        }
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
            case .emptySelection, .staleSelection, .secureField, .selectionTooLong:
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
        case .requestFailed(statusCode: 429, let message):
            "GLKB declined this request because usage or rate limits were reached."
                + (message.map { " \($0)" } ?? " Check the account before retrying.")
        case .requestFailed(statusCode: 422, let message):
            message.map { "GLKB rejected the selected sentence: \($0)" }
                ?? "GLKB rejected the selected sentence."
        case .requestFailed(statusCode: 502, _), .requestFailed(statusCode: 503, _):
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

    private static func credentialScope(for key: String?) -> String {
        guard let key else { return "missing" }
        return SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
