import Combine
import Foundation
import Sparkle

@MainActor
public final class UpdateController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController?

    public init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if let feed, URL(string: feed)?.scheme == "https", !(publicKey ?? "").isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
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
