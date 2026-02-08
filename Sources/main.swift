import NIO

let VERSION = "1.0.0"

@main
struct Entry {
    static func main() {
        APIRouter.InitRouter()

        let group = MultiThreadedEventLoopGroup(
            numberOfThreads: System.coreCount
        )

        defer {
            // SwiftNIO 2 requires blocking shutdown
            try? group.syncShutdownGracefully()
        }

        do {
            let bootstrap = makeBootstrap(group: group)
            let channel = try bindServer(bootstrap: bootstrap)

            print("HTTP server listening on http://\(ServerConfig.host):\(ServerConfig.port)")

            // Block the main thread until shutdown
            try channel.closeFuture.wait()

        } catch {
            print("Fatal server error:", error)
            exit(1)
        }
    }
}
