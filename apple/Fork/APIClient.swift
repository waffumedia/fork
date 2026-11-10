import Foundation
import Observation
import Security

private enum TokenKeychain {
    static let service = "com.waffu.fork"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "api-token"]
    }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) throws {
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain(status) }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.keychain(status) }
    }
}

enum APIError: LocalizedError {
    case invalidURL, http(Int), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid http or https server URL in Settings."
        case .http(401): "Check token in Settings"
        case .http(let status): "Server returned HTTP \(status). Try again."
        case .keychain(let status): "Couldn't save the token in Keychain (\(status))."
        }
    }
}

@MainActor @Observable final class APIClient {
    var server: String
    var token: String
    var unauthorized = false
    var revision = 0
    init() {
        server = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3300"
        token = TokenKeychain.read()
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["FORK_URL"] { server = value }
        if let value = ProcessInfo.processInfo.environment["FORK_TOKEN"] { token = value }
        #endif
    }
    func save(server: String, token: String) throws {
        let value = server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.host != nil else { throw APIError.invalidURL }
        try TokenKeychain.save(token)
        self.server = value
        self.token = token
        UserDefaults.standard.set(value, forKey: "serverURL")
        unauthorized = false
        revision += 1
    }
    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let base = URL(string: server), ["http", "https"].contains(base.scheme), base.host != nil,
              var parts = URLComponents(url: base.appendingPathComponent("api").appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw APIError.invalidURL }
        return url
    }
    func request<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: try url(path, query: query))
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(0) }
        if http.statusCode == 401 { unauthorized = true }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func swipe(_ id: String, _ verdict: String) async throws {
        let _: SwipeResponse = try await request("swipe", body: ["id": id, "verdict": verdict])
        revision += 1
    }
    func imageRequest(_ path: String) -> URLRequest? {
        guard let base = URL(string: server), let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
        var request = URLRequest(url: url)
        if url.host == base.host && url.port == base.port && url.scheme == base.scheme {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

@MainActor @Observable final class LoadStore<Value: Sendable> {
    var value: Value?
    var error: String?
    var loading = false
    private var generation = 0
    func load(_ action: @MainActor () async throws -> Value) async {
        generation += 1
        let current = generation
        loading = true
        error = nil
        do {
            let result = try await action()
            guard current == generation, !Task.isCancelled else { return }
            value = result
        } catch {
            guard current == generation else { return }
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        if current == generation { loading = false }
    }
}
