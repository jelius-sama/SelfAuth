import Foundation

struct AuthLogin {
    static func handler(req: HTTPRequest) -> HTTPResponse {
        do {
            guard
                let url = Bundle.module.url(
                    forResource: "login",
                    withExtension: "html",
                )
            else {
                throw APIError.internalError
            }

            let html = try String(contentsOf: url, encoding: .utf8)
            return HTTPResponse.html(html)
        } catch {
            return HTTPResponse.text(
                "Internal Server Error",
                status: .internalServerError
            )
        }
    }
}
