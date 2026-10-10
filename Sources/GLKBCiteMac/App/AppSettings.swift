import Combine
import Foundation
import GLKBCiteCore

@MainActor
public final class AppSettings: ObservableObject {
    private enum Key {
        static let includeEvidence = "literature.includeEvidence"
        static let cacheDuration = "literature.cacheDurationMinutes"
        static let automaticSelection = "selection.automaticEnabled"
        static let compatibilityCapture = "selection.compatibilityCaptureEnabled"
        static let onboardingCompleted = "onboarding.completed"
    }

    /// The citation endpoint's `max_references`. Not user-configurable: the
    /// product design exposes no control for it.
    public var maxArticles: Int { 5 }

    @Published public var includeEvidence: Bool {
        didSet { defaults.set(includeEvidence, forKey: Key.includeEvidence) }
    }

    @Published public var cacheDurationMinutes: Int {
        didSet {
            if ![0, 5, 15, 60].contains(cacheDurationMinutes) {
                cacheDurationMinutes = 15
            }
            defaults.set(cacheDurationMinutes, forKey: Key.cacheDuration)
        }
    }

    /// Whether the selection badge is offered after selection gestures.
    /// Off until the user chooses; see `hasExplicitAutomaticSelectionChoice`.
    @Published public var automaticSelectionEnabled: Bool {
        didSet {
            defaults.set(automaticSelectionEnabled, forKey: Key.automaticSelection)
            hasExplicitAutomaticSelectionChoice = true
        }
    }

    /// Whether the temporary-Copy fallback may run on explicit invocations.
    /// Off until the user chooses; see `hasExplicitCompatibilityCaptureChoice`.
    @Published public var compatibilityCaptureEnabled: Bool {
        didSet {
            defaults.set(compatibilityCaptureEnabled, forKey: Key.compatibilityCapture)
            hasExplicitCompatibilityCaptureChoice = true
        }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
    }

    /// True once the user (or the setup wizard, with the control visible) has
    /// set the value at least once. Setup applies its recommended defaults only
    /// while these are false, so an explicit "off" is never overridden.
    public private(set) var hasExplicitAutomaticSelectionChoice: Bool
    public private(set) var hasExplicitCompatibilityCaptureChoice: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Older builds persisted a user-chosen maximum; the setting no longer exists.
        defaults.removeObject(forKey: "literature.maxArticles")

        includeEvidence = defaults.object(forKey: Key.includeEvidence) == nil
            ? true
            : defaults.bool(forKey: Key.includeEvidence)

        if defaults.object(forKey: Key.cacheDuration) == nil {
            cacheDurationMinutes = 15
        } else {
            let storedCache = defaults.integer(forKey: Key.cacheDuration)
            cacheDurationMinutes = [0, 5, 15, 60].contains(storedCache) ? storedCache : 15
        }

        hasExplicitAutomaticSelectionChoice = defaults.object(forKey: Key.automaticSelection) != nil
        hasExplicitCompatibilityCaptureChoice = defaults.object(forKey: Key.compatibilityCapture) != nil
        automaticSelectionEnabled = defaults.bool(forKey: Key.automaticSelection)
        compatibilityCaptureEnabled = defaults.bool(forKey: Key.compatibilityCapture)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
    }

    /// The recommended first-run configuration, applied only to settings the
    /// user has never touched. Called when the setup wizard shows its privacy
    /// step, where both controls are visible and can be turned off before
    /// finishing.
    public func applyRecommendedPrivacyDefaultsIfUnset() {
        if !hasExplicitAutomaticSelectionChoice { automaticSelectionEnabled = true }
        if !hasExplicitCompatibilityCaptureChoice { compatibilityCaptureEnabled = true }
    }

    public var queryOptions: LiteratureQueryOptions {
        LiteratureQueryOptions(
            maxArticles: maxArticles,
            includeEvidence: includeEvidence,
            cacheDurationMinutes: cacheDurationMinutes
        )
    }
}
