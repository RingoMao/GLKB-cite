import Carbon.HIToolbox
import Foundation

public enum GlobalHotKeyError: Error, LocalizedError {
    case couldNotInstallHandler(OSStatus)
    case shortcutUnavailable(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .couldNotInstallHandler(status):
            "GLKB Cite could not install its shortcut handler (error \(status))."
        case let .shortcutUnavailable(status):
            "Option-Command-G is already in use or unavailable (error \(status)). Quit GLKB Lens or change its shortcut."
        }
    }
}

public enum GlobalHotKeyAvailability: Equatable, Sendable {
    case registered
    case unavailable(status: OSStatus)
    public var isRegistered: Bool { self == .registered }
}

public struct GlobalHotKeyRegistrationReport: Equatable, Sendable {
    public var availability: GlobalHotKeyAvailability?
    public init(availability: GlobalHotKeyAvailability? = nil) {
        self.availability = availability
    }
}

@MainActor
public protocol GlobalHotKeyProviding: AnyObject {
    var isRegistered: Bool { get }
    var registrationReport: GlobalHotKeyRegistrationReport { get }
    @discardableResult
    func register(handler: @escaping @MainActor @Sendable () -> Void) throws
        -> GlobalHotKeyRegistrationReport
    func unregister()
}

@MainActor
public final class GlobalHotKeyManager: GlobalHotKeyProviding {
    nonisolated fileprivate static let signature: OSType = 0x474C4B43 // "GLKC"
    private static let identifier: UInt32 = 1
    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var handler: (@MainActor @Sendable () -> Void)?
    public private(set) var registrationReport = GlobalHotKeyRegistrationReport()

    public init() {}
    public var isRegistered: Bool { hotKeyReference != nil }

    public func register(handler: @escaping @MainActor @Sendable () -> Void) throws
        -> GlobalHotKeyRegistrationReport {
        unregister()
        self.handler = handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(), glkbCiteHotKeyEventHandler,
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard installStatus == noErr else {
            self.handler = nil
            throw GlobalHotKeyError.couldNotInstallHandler(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyReference
        )
        let availability: GlobalHotKeyAvailability = status == noErr && hotKeyReference != nil
            ? .registered : .unavailable(status: status)
        let report = GlobalHotKeyRegistrationReport(availability: availability)
        registrationReport = report
        return report
    }

    public func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        hotKeyReference = nil
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        eventHandlerReference = nil
        handler = nil
        registrationReport = GlobalHotKeyRegistrationReport()
    }

    fileprivate func receive(identifier: UInt32) {
        guard identifier == Self.identifier else { return }
        handler?()
    }
}

private func glkbCiteHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &identifier
    )
    guard status == noErr, identifier.signature == GlobalHotKeyManager.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in manager.receive(identifier: identifier.id) }
    return noErr
}
