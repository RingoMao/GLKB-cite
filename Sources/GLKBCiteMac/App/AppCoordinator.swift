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

@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public private(set) var phase: ResultPanelPhase = .idle
    @Published public private(set) var selection: SelectionContext?
    @Published public private(set) var result: LiteratureResult?
    @Published public private(set) var progressStep = ""
    @Published public private(set) var progressContent: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasStoredAPIKey = false
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

    private lazy var resultPanelController = ResultPanelController(coordinator: self)
    private lazy var badgePanelController = SelectionBadgePanelController(coordinator: self)
    private lazy var onboardingWindowController = OnboardingWindowController(coordinator: self)
    private lazy var settingsWindowController = CiteSettingsWindowController(coordinator: self)
    private var automaticCandidateSelection: SystemSelection?
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
            selectionProvider: resolvedSelectionProvider
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
        if !settings.hasCompletedOnboarding { onboardingWindowController.show() }
    }

    public func stop() {
        invalidateCurrentQuery()
        selectionCaptureTask?.cancel()
        candidateExpiryTask?.cancel()
        automaticSelectionMonitor.stop()
        automaticCandidateSelection = nil
        hotKeyManager.unregister()
        servicesProvider.uninstall()
        badgePanelController.dismiss()
        hasStarted = false
        Task { await glkbCache.removeAll() }
    }

    public func captureCitations() {
        automaticCandidateSelection = nil
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
        guard let candidate = automaticCandidateSelection else { return }
        automaticCandidateSelection = nil
        candidateExpiryTask?.cancel()
        badgePanelController.dismiss()
        Task { [weak self] in
            guard let self else { return }
            guard await selectionProvider.isStillValid(candidate) else {
                handleSelectionCaptureFailure(SelectionCaptureError.staleSelection)
                return
            }
            dispatch(systemSelection: candidate)
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
        }
    }

    public func showLastResult() {
        guard result != nil || phase == .loading || phase == .failed else {
            showError("No citation result is available yet.")
            return
        }
        resultPanelController.show(anchor: selection?.bounds)
    }

    public func showSettings() {
        settingsWindowController.show()
    }

    public func showOnboarding() { onboardingWindowController.show() }

    public func completeOnboarding() {
        refreshCredentialStatus()
        guard permissionManager.isTrusted, hasStoredAPIKey else { return }
        settings.compatibilityCaptureEnabled = true
        settings.automaticSelectionEnabled = true
        settings.hasCompletedOnboarding = true
        synchronizeAutomaticSelectionMonitor()
        onboardingWindowController.close()
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
        hasStoredAPIKey = ((try? keyStore.loadAPIKey()) ?? nil) != nil
    }

    public func setAutomaticSelectionEnabled(_ enabled: Bool) {
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

    public func openAllReferencesInPubMed() {
        guard let result, let url = PubMed.searchURL(for: result.references) else { return }
        NSWorkspace.shared.open(url)
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
            showError(error.localizedDescription)
        }
    }

    private func handleSelectionCaptureFailure(_ error: Error) {
        invalidateCurrentQuery()
        selection = nil
        result = nil
        lastQuery = nil
        showError(error.localizedDescription)
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
                    } else {
                        showError(friendlyMessage(for: error))
                    }
                }
            }
        } catch {
            activeQueryID = nil
            activeQuery = nil
            showError(friendlyMessage(for: error))
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
        automaticCandidateSelection = event.selection
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
        automaticCandidateSelection = nil
        badgePanelController.dismiss()
    }

    private func showError(_ message: String) {
        phase = .failed
        errorMessage = message
        progressStep = ""
        progressContent = nil
        resultPanelController.show(anchor: selection?.bounds)
    }

    private func friendlyMessage(for error: Error) -> String {
        guard let literatureError = error as? LiteratureError else { return error.localizedDescription }
        return switch literatureError {
        case .requestFailed(statusCode: 401, _), .requestFailed(statusCode: 403, _):
            "GLKB rejected this API key. Replace it with an active glkb_ key in Settings."
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

    private func credentialScope(for key: String?) -> String {
        guard let key else { return "missing" }
        return SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
