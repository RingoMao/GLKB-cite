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

    @Published public var automaticSelectionEnabled: Bool {
        didSet { defaults.set(automaticSelectionEnabled, forKey: Key.automaticSelection) }
    }

    @Published public var compatibilityCaptureEnabled: Bool {
        didSet { defaults.set(compatibilityCaptureEnabled, forKey: Key.compatibilityCapture) }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
    }

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

        automaticSelectionEnabled = defaults.bool(forKey: Key.automaticSelection)
        compatibilityCaptureEnabled = defaults.bool(forKey: Key.compatibilityCapture)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
    }

    public var queryOptions: LiteratureQueryOptions {
        LiteratureQueryOptions(
            maxArticles: maxArticles,
            includeEvidence: includeEvidence,
            cacheDurationMinutes: cacheDurationMinutes
        )
    }

}
