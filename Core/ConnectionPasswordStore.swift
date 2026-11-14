import Foundation
import Security

public struct ConnectionPasswordStore {
    private let read: () throws -> Data?
    private let write: (Data) throws -> Void
    public init() {
        read = Self.readKeychain
        write = Self.writeKeychain
    }
    // Tests use disposable storage, never the host's Keychain.
    init(read: @escaping () throws -> Data?, write: @escaping (Data) throws -> Void) {
        self.read = read; self.write = write
    }
    public func loadOrCreate() throws -> String {
        if let data = try read() {
            guard let value = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "QueryShare.Password", code: 1, userInfo: [NSLocalizedDescriptionKey: "Saved password cannot be decoded"])
            }
            return value
        }
        let password = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try save(password)
        return password
    }
    public func save(_ password: String) throws { try write(Data(password.utf8)) }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "dev.queryshare.QueryShare") + ".sftp",
         kSecAttrAccount as String: "connection-password",
         kSecAttrSynchronizable as String: false]
    }
    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: (SecCopyErrorMessageString(status, nil) as String?) ?? "Password storage failed (\(status))"])
    }
    private static func readKeychain() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        guard let data = result as? Data else { throw failure(errSecDecode) }
        return data
    }
    private static func writeKeychain(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
}
