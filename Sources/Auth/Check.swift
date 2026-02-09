import Foundation

struct AuthCheck {
    static func handler(req: HTTPRequest) -> APIRouter.Response {
        return APIRouter.runSync {
            guard
                let token = findCookie(named: "auth_token", in: req.headers["Cookie"]),
                await TokenStore.shared.isValid(token)
            else {
                // Get the original request path from Caddy's forwarded header
                let originalPath = req.headers["X-SelfAuth-Original-URI"].first ?? "/"

                // Prevent redirect loop if somehow /_auth/check is the path
                let redirectPath =
                    originalPath.starts(with: "/_auth/check")
                    ? "/"
                    : !originalPath.hasPrefix("/") || originalPath.hasPrefix("//")
                        ? "/" : originalPath

                let redirectURL = "/_auth/login?redirect=\(redirectPath)"

                // Return 302 redirect
                return .Success(
                    HTTPResponse(
                        status: .temporaryRedirect,
                        headers: ["Location": redirectURL],
                        body: nil
                    )
                )
            }

            do {
                guard
                    let url = Bundle.module.url(
                        forResource: "authorized",
                        withExtension: "html",
                    )
                else {
                    return .Success(.html("Authorized", status: .ok))
                }

                let html = try String(contentsOf: url, encoding: .utf8)
                return .Success(HTTPResponse.html(html, status: .ok))
            } catch {
                return .Success(.html("Authorized", status: .ok))
            }
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
