import Foundation

enum APIRouter {
    private static let router = Router()

    static var shared: Router {
        return router
    }

    public enum Response {
        case Success(HTTPResponse)
        case Error(APIError)
    }

    private final class SendableBox<T>: @unchecked Sendable {
        var value: T?

        init(_ value: T? = nil) {
            self.value = value
        }
    }

    @inline(__always)
    static func runSync<T>(_ operation: @escaping @Sendable () async -> T) -> T {
        let box = SendableBox<T>()
        let semaphore = DispatchSemaphore(value: 0)

        Task { @Sendable in
            box.value = await operation()
            semaphore.signal()
        }

        semaphore.wait()
        return box.value!
    }

    static func registerRoutes() {
        router.get("/_auth/check") { req in
            let resp = AuthCheck.handler(req: req)

            switch resp {
            case .Success(let response):
                return response

            case .Error(let error):
                throw error
            }
        }

        router.get("/_auth/login") { req in
            return AuthLogin.handler(req: req)
        }

        router.post("/_auth/submit") { req in
            let resp = AuthSubmit.handler(req: req)

            switch resp {
            case .Success(let response):
                return response

            case .Error(let error):
                throw error
            }
        }

        router.get("/version") { _ in
            .text(VERSION)
        }

        // Health check
        router.get("/health") { _ in
            struct HealthResponse: Codable {
                let status: String
                let timestamp: Double
            }

            let response = HealthResponse(
                status: "ok",
                timestamp: Date().timeIntervalSince1970
            )

            return .json(response)
        }
    }

    // Must be called once at startup
    static func InitRouter() {
        registerRoutes()
        router.freeze()
    }
}
