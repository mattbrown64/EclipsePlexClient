//
//  KeychainStore.swift
//  EclipsePlexClient
//

import Foundation
import Security

/// Secure storage for Plex credentials. Server list metadata stays in UserDefaults without tokens.
enum KeychainStore {
    private static let service = "com.eclipseplex.client.credentials"

    private enum Account: String {
        case plexAccountToken = "plexAccountAuthToken.v1"
        case serverTokens = "plexServerAccessTokens.v1"
    }

    // MARK: - Plex.tv account token

    static func loadPlexAccountToken() -> String? {
        loadString(account: Account.plexAccountToken.rawValue)
    }

    static func savePlexAccountToken(_ token: String?) {
        if let token, !token.isEmpty {
            saveString(token, account: Account.plexAccountToken.rawValue)
        } else {
            delete(account: Account.plexAccountToken.rawValue)
        }
    }

    // MARK: - Per-server access tokens (UUID string → token)

    static func loadServerTokens() -> [UUID: String] {
        guard let data = loadData(account: Account.serverTokens.rawValue),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var result: [UUID: String] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key), !value.isEmpty else { continue }
            result[id] = value
        }
        return result
    }

    static func saveServerTokens(_ tokens: [UUID: String]) {
        let raw = Dictionary(uniqueKeysWithValues: tokens.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        saveData(data, account: Account.serverTokens.rawValue)
    }

    static func token(forServerID id: UUID) -> String? {
        loadServerTokens()[id]
    }

    static func setToken(_ token: String?, forServerID id: UUID) {
        var map = loadServerTokens()
        if let token, !token.isEmpty {
            map[id] = token
        } else {
            map.removeValue(forKey: id)
        }
        if map.isEmpty {
            delete(account: Account.serverTokens.rawValue)
        } else {
            saveServerTokens(map)
        }
    }

    // MARK: - Migration from UserDefaults

    private static let migrationDoneKey = "keychainCredentialsMigration.v1"
    private static let legacyAccountTokenKey = "plexAccountAuthToken.v1"
    private static let legacyServersKey = "plexCustomServers.v1"

    /// Moves tokens from UserDefaults / embedded server JSON into Keychain once.
    static func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }

        if loadPlexAccountToken() == nil,
           let legacy = UserDefaults.standard.string(forKey: legacyAccountTokenKey),
           !legacy.isEmpty {
            savePlexAccountToken(legacy)
        }
        UserDefaults.standard.removeObject(forKey: legacyAccountTokenKey)

        if loadServerTokens().isEmpty,
           let data = UserDefaults.standard.data(forKey: legacyServersKey),
           let servers = try? JSONDecoder().decode([PlexServer].self, from: data) {
            var tokens: [UUID: String] = [:]
            for server in servers {
                if let t = server.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    tokens[server.id] = t
                }
            }
            if !tokens.isEmpty {
                saveServerTokens(tokens)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationDoneKey)
    }

    /// Test-only reset.
    static func resetAllForTesting() {
        delete(account: Account.plexAccountToken.rawValue)
        delete(account: Account.serverTokens.rawValue)
        UserDefaults.standard.removeObject(forKey: migrationDoneKey)
        UserDefaults.standard.removeObject(forKey: legacyAccountTokenKey)
    }

    // MARK: - Keychain primitives

    private static func saveString(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(data, account: account)
    }

    private static func loadString(account: String) -> String? {
        guard let data = loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveData(_ data: Data, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return }
        delete(account: account)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
