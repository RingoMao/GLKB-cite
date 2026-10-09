import Combine
import Foundation
import Sparkle

/// Wraps Sparkle for a menu-bar app.
///
/// Background apps get no attention when Sparkle shows a scheduled update
/// alert behind other windows, so this controller opts into Sparkle's gentle
/// reminders: a scheduled update that arrives while the app is not in focus
/// is surfaced as `pendingUpdateVersion` (shown in the menu) instead of an
/// alert, and the user opens it with Check for Updates.
@MainActor
public final class UpdateController: NSObject, ObservableObject {
    /// A version Sparkle found during a scheduled check that has not been
    /// shown to the user yet.
    @Published public private(set) var pendingUpdateVersion: String?

    private var updaterController: SPUStandardUpdaterController?

    public init(bundle: Bundle = .main) {
        super.init()
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if let feed, URL(string: feed)?.scheme == "https", !(publicKey ?? "").isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: self
            )
        } else {
            updaterController = nil
        }
    }

    public var isConfigured: Bool {
        updaterController != nil
    }

    public var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    public func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    public var supportsGentleScheduledUpdateReminders: Bool { true }

    public func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // When the app happens to be in focus let Sparkle present normally;
        // otherwise we remind through the menu bar.
        immediateFocus
    }

    public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            pendingUpdateVersion = update.displayVersionString
        }
    }

    public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingUpdateVersion = nil
    }

    public func standardUserDriverWillFinishUpdateSession() {
        pendingUpdateVersion = nil
    }
}
