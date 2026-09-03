import ServiceManagement

public enum LaunchAtLoginStatus: Hashable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
public protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openLoginItemsSettings()
}

@MainActor
public final class LaunchAtLoginManager: LaunchAtLoginManaging {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch service.status {
            case .enabled, .requiresApproval:
                return
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
