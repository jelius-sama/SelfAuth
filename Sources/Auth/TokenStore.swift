import Foundation

actor TokenStore {
    static let shared = TokenStore()

    private var validTokens: Set<String> = []

    // Generate and store a new token
    func createToken() -> String {
        let token = UUID().uuidString
        validTokens.insert(token)
        return token
    }

    // Check if a token is valid
    func isValid(_ token: String) -> Bool {
        validTokens.contains(token)
    }

    // Remove a token (logout / expiry)
    func revoke(_ token: String) {
        validTokens.remove(token)
    }

    // Optional: clear all tokens (debug / shutdown)
    func clear() {
        validTokens.removeAll()
    }
}
