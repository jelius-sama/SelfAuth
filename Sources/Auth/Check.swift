struct AuthCheck {
    static func handler(req: HTTPRequest) -> APIRouter.Response {
        return APIRouter.runSync {
            guard
                let token = findCookie(named: "auth_token", in: req.headers["Cookie"]),
                await TokenStore.shared.isValid(token)
            else {
                return .Error(APIError.unauthorized)
            }

            return .Success(.text("authorized"))
        }
    }

    /// Searches all Cookie headers for a specific cookie name
    private static func findCookie(named name: String, in headers: [String]) -> String? {
        for header in headers {
            if let value = parseCookie(named: name, from: header) {
                return value
            }
        }
        return nil
    }

    /// Parses a single Cookie header line
    private static func parseCookie(named name: String, from header: String) -> String? {
        header
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }
}
