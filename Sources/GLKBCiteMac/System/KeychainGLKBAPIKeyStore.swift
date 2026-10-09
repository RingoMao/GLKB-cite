import Foundation
import GLKBCiteCore
import Security

public enum GLKBAPIKeyStoreError: Error, LocalizedError {
    case invalidKey
    case invalidStoredValue
    case keychainFailure(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Enter a GLKB API key beginning with glkb_ (letters, digits, - and _ only, on one line)."
        case .invalidStoredValue:
            return "The saved GLKB API key could not be read. Save a new glkb_ key in Settings to replace it."
        case let .keychainFailure(status):
            let description = SecCopyErrorMessageString(status, nil) as String?
            return description.map { "Keychain error: \($0)" }
                ?? "Keychain returned error \(status)."
        }
    }
}

public protocol GLKBAPIKeyStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

/// Stores only the user-provided GLKB credential. The value is never exposed in
/// errors, logs, defaults, diagnostics, or the application bundle.
///
/// The item lives in the login keychain (the data-protection keychain would
/// orphan keys saved by earlier builds). Items are created with
/// "after first unlock, this device only" accessibility and are never synced.
public struct KeychainGLKBAPIKeyStore: GLKBAPIKeyStoring, Sendable {
    public let service: String
    public let account: String

    public init(
        service: String = "org.glkb.cite",
        account: String = "GLKB API Key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[key(kSecReturnData)] = true
        query[key(kSecMatchLimit)] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let storedKey = String(data: data, encoding: .utf8) else {
                throw GLKBAPIKeyStoreError.invalidStoredValue
            }
            return storedKey
        case errSecItemNotFound:
            return nil
        default:
            throw GLKBAPIKeyStoreError.keychainFailure(status)
        }
    }

    public func saveAPIKey(_ keyValue: String) throws {
        guard let normalizedKey = GLKBAPIKeyFormat.normalize(keyValue),
              let data = normalizedKey.data(using: .utf8) else {
            throw GLKBAPIKeyStoreError.invalidKey
        }

        let updateAttributes: [String: Any] = [
            key(kSecValueData): data
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            updateAttributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try add(data)
        case errSecAuthFailed, errSecInteractionNotAllowed:
            // The existing item's access list no longer matches this binary
            // (typical after a rebuild) or the user denied the prompt once.
            // Replacing the item is the only way to recover without Keychain
            // Access; `add` then creates it with this binary's access.
            let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw GLKBAPIKeyStoreError.keychainFailure(updateStatus)
            }
            try add(data)
        default:
            throw GLKBAPIKeyStoreError.keychainFailure(updateStatus)
        }
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GLKBAPIKeyStoreError.keychainFailure(status)
        }
    }

    private func add(_ data: Data) throws {
        var newItem = baseQuery
        newItem[key(kSecValueData)] = data
        newItem[key(kSecAttrAccessible)] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        newItem[key(kSecAttrSynchronizable)] = kCFBooleanFalse
        newItem[key(kSecAttrLabel)] = "GLKB Cite API Key"
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GLKBAPIKeyStoreError.keychainFailure(addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            key(kSecClass): kSecClassGenericPassword,
            key(kSecAttrService): service,
            key(kSecAttrAccount): account
        ]
    }

    private func key(_ value: CFString) -> String {
        value as String
    }
}
