import NIO
import NIOHTTP1
import Foundation

enum ServerConfig {
    static let host = "0.0.0.0"
    static let port = 5001
    static let backlog = 256
    static let maxMessagesPerRead = 16
}

enum APIError: Error {
    case notFound
    case methodNotAllowed
    case badRequest(String)
    case internalError
    case unauthorized
}

func makeBootstrap(group: EventLoopGroup) -> ServerBootstrap {
    ServerBootstrap(group: group)
        .serverChannelOption(
            ChannelOptions.backlog,
            value: Int32(ServerConfig.backlog)
        )
        .serverChannelOption(
            ChannelOptions.socketOption(.so_reuseaddr),
            value: 1
        )
        .childChannelInitializer { channel in
            channel.pipeline
                .configureHTTPServerPipeline()
                .flatMap {
                    channel.pipeline.addHandler(HTTPHandler())
                }
        }
        .childChannelOption(
            ChannelOptions.socketOption(.so_reuseaddr),
            value: 1
        )
        .childChannelOption(
            ChannelOptions.maxMessagesPerRead,
            value: UInt(ServerConfig.maxMessagesPerRead)
        )
}

func bindServer(bootstrap: ServerBootstrap) throws -> Channel {
    try bootstrap
        .bind(host: ServerConfig.host, port: ServerConfig.port)
        .wait()
}

struct HTTPRequest {
    let method: HTTPMethod
    let path: String
    let headers: HTTPHeaders
    let body: ByteBuffer?
    var pathParams: [String: String] = [:]
    var queryParams: [String: String] = [:]

    init(method: HTTPMethod, uri: String, headers: HTTPHeaders, body: ByteBuffer?) {
        self.method = method
        self.headers = headers
        self.body = body

        // Parse URI into path and query parameters
        if let queryStartIndex = uri.firstIndex(of: "?") {
            self.path = String(uri[..<queryStartIndex])
            let queryString = String(uri[uri.index(after: queryStartIndex)...])
            self.queryParams = Self.parseQueryString(queryString)
        } else {
            self.path = uri
        }
    }

    private static func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]

        for pair in query.split(separator: "&") {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let value =
                    String(components[1])
                    .removingPercentEncoding ?? String(components[1])
                params[key] = value
            }
        }

        return params
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard var body = body else {
            throw APIError.badRequest("Missing request body")
        }

        let length = body.readableBytes
        guard let bytes = body.readBytes(length: length) else {
            throw APIError.badRequest("Invalid request body")
        }

        let data = Data(bytes)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct HTTPResponse {
    let status: HTTPResponseStatus
    let headers: HTTPHeaders
    let body: ByteBuffer?

    static func json<T: Encodable>(
        _ value: T,
        status: HTTPResponseStatus = .ok
    ) -> HTTPResponse {
        let data = try! JSONEncoder().encode(value)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: "\(data.count)")
        headers.add(name: "Connection", value: "close")

        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)

        return HTTPResponse(status: status, headers: headers, body: buffer)
    }

    static func html(
        _ html: String,
        status: HTTPResponseStatus = .ok
    ) -> HTTPResponse {
        let byteCount = html.utf8.count

        var buffer = ByteBufferAllocator().buffer(capacity: byteCount)
        buffer.writeString(html)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(byteCount)")
        headers.add(name: "Connection", value: "close")

        return HTTPResponse(
            status: status,
            headers: headers,
            body: buffer
        )
    }

    static func text(
        _ text: String,
        status: HTTPResponseStatus = .ok
    ) -> HTTPResponse {
        var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
        buffer.writeString(text)

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        headers.add(name: "Content-Length", value: "\(text.utf8.count)")
        headers.add(name: "Connection", value: "close")

        return HTTPResponse(status: status, headers: headers, body: buffer)
    }
}

final class Router: @unchecked Sendable {
    typealias Handler = (HTTPRequest) throws -> HTTPResponse

    private struct Route {
        let pattern: String
        let pathSegments: [PathSegment]
        let handler: Handler

        enum PathSegment {
            case literal(String)
            case parameter(String)
        }
    }

    private var routes: [String: [Route]] = [:]
    private var frozen = false

    func on(_ method: HTTPMethod, _ pattern: String, handler: @escaping Handler) {
        precondition(!frozen, "Router is frozen; no more routes can be added")

        let segments = parsePathPattern(pattern)
        let route = Route(pattern: pattern, pathSegments: segments, handler: handler)
        routes[method.rawValue, default: []].append(route)
    }

    func get(_ pattern: String, handler: @escaping Handler) {
        on(.GET, pattern, handler: handler)
    }

    func post(_ pattern: String, handler: @escaping Handler) {
        on(.POST, pattern, handler: handler)
    }

    func patch(_ pattern: String, handler: @escaping Handler) {
        on(.PATCH, pattern, handler: handler)
    }

    func delete(_ pattern: String, handler: @escaping Handler) {
        on(.DELETE, pattern, handler: handler)
    }

    func freeze() {
        frozen = true
    }

    func route(_ request: HTTPRequest) throws -> HTTPResponse {
        guard let methodRoutes = routes[request.method.rawValue] else {
            throw APIError.methodNotAllowed
        }

        // Try to match routes
        for route in methodRoutes {
            if let pathParams = matchPath(request.path, against: route.pathSegments) {
                var modifiedRequest = request
                modifiedRequest.pathParams = pathParams
                return try route.handler(modifiedRequest)
            }
        }

        throw APIError.notFound
    }

    private func parsePathPattern(_ pattern: String) -> [Route.PathSegment] {
        let components = pattern.split(separator: "/")
        return components.map { component in
            if component.hasPrefix(":") {
                let paramName = String(component.dropFirst())
                return .parameter(paramName)
            } else {
                return .literal(String(component))
            }
        }
    }

    private func matchPath(_ path: String, against segments: [Route.PathSegment]) -> [String:
        String]?
    {
        let pathComponents = path.split(separator: "/")

        guard pathComponents.count == segments.count else {
            return nil
        }

        var params: [String: String] = [:]

        for (component, segment) in zip(pathComponents, segments) {
            switch segment {
            case .literal(let literal):
                if component != literal {
                    return nil
                }
            case .parameter(let name):
                params[name] = String(component)
            }
        }

        return params
    }
}

final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?

    func channelRead(
        context: ChannelHandlerContext,
        data: NIOAny
    ) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)

        case .body(var body):
            requestBody?.writeBuffer(&body)

        case .end:
            handleRequest(context: context)
            requestHead = nil
            requestBody = nil
        }
    }

    private func handleRequest(context: ChannelHandlerContext) {
        guard let head = requestHead else { return }

        let request = HTTPRequest(
            method: head.method,
            uri: head.uri,
            headers: head.headers,
            body: requestBody
        )

        let response: HTTPResponse

        do {
            response = try APIRouter.shared.route(request)
        } catch APIError.notFound {
            response = .text("Not Found", status: .notFound)
        } catch APIError.methodNotAllowed {
            response = .text("Method Not Allowed", status: .methodNotAllowed)
        } catch APIError.badRequest(let msg) {
            response = .text(msg, status: .badRequest)
        } catch APIError.unauthorized {
            response = .text("Unauthorized", status: .unauthorized)
        } catch {
            response = .text("Internal Server Error", status: .internalServerError)
        }

        writeResponse(response, context: context)
    }

    private func writeResponse(
        _ response: HTTPResponse,
        context: ChannelHandlerContext
    ) {
        let head = HTTPResponseHead(
            version: .http1_1,
            status: response.status,
            headers: response.headers
        )

        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if let body = response.body {
            context.write(
                wrapOutboundOut(.body(.byteBuffer(body))),
                promise: nil
            )
        }

        context.writeAndFlush(
            wrapOutboundOut(.end(nil)),
            promise: nil
        )
    }

    func errorCaught(
        context: ChannelHandlerContext,
        error: Error
    ) {
        print("Connection error:", error)
        context.close(promise: nil)
    }
}
