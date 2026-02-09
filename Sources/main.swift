import NIO

@main
struct Entry {
    static func main() {
        if CommandLine.arguments.count > 1 {
            switch CommandLine.arguments[1] {
            case "-h", "--h", "-help", "--help":
                printHelp()

            case "-v", "--v", "-version", "--version":
                printVersion()

            case "server", "s", "--server", "-server", "-s", "--s":
                checkEnv()

            case "config", "c", "--config", "-config", "-c", "--c":
                Environment.generateEnv()

            default:
                printHelp()
            }
        } else {
            checkEnv()
        }
    }

    private static func printVersion() {
        print("\(Color.cyan)\(Color.bold)SelfAuth v\(Environment.VERSION)\(Color.reset)")
        print("\(Color.cyan)A self-hosted authentication server\(Color.reset)\n")
    }

    private static func printHelp() {
        printVersion()

        print("\(Color.bold)USAGE:\(Color.reset)")
        print("    selfauth [COMMAND]\n")

        print("\(Color.bold)COMMANDS:\(Color.reset)")
        print("    \(Color.green)server, s\(Color.reset)")
        print("        Start the authentication server")
        print("        If not configured, will prompt for setup (requires interactive terminal)\n")

        print("    \(Color.green)config, c\(Color.reset)")
        print("        Configure or reconfigure the environment")
        print("        Sets up admin credentials and creates /etc/SelfAuth/env\n")

        print("    \(Color.green)help, h\(Color.reset)")
        print("        Display this help message\n")

        print("\(Color.bold)EXAMPLES:\(Color.reset)")
        print("    \(Color.yellow)# Start the server (default command)\(Color.reset)")
        print("    selfauth")
        print("    selfauth server\n")

        print("    \(Color.yellow)# Configure environment\(Color.reset)")
        print("    selfauth config\n")

        print("    \(Color.yellow)# Run as systemd service\(Color.reset)")
        print("    sudo systemctl start selfauth\n")

        print("\(Color.bold)CONFIGURATION:\(Color.reset)")
        print("    Config file: /etc/SelfAuth/env")
        print("    Required fields: ADMIN_EMAIL, SALTED_PASS\n")

        print("\(Color.bold)NOTES:\(Color.reset)")
        print("    • Server requires /etc/SelfAuth/env to be configured")
        print("    • Running without config in non-interactive mode will fail")
        print("    • Use 'selfauth config' to set up credentials\n")
    }

    private static func checkEnv() {
        if !Environment.configureEnv() {
            // Check if stdin is a terminal (interactive)
            if isatty(STDIN_FILENO) != 1 {
                let messages = [
                    "\(Color.red)\(Color.bold)ERROR: Server not configured\(Color.reset)\n",
                    "\(Color.red)Cannot prompt for configuration in non-interactive mode\(Color.reset)\n",
                    "\(Color.red)Please run 'selfauth config' in an interactive terminal first\(Color.reset)\n",
                ]

                for msg in messages {
                    msg.withCString { ptr in
                        let _ = write(2, ptr, strlen(ptr))
                    }
                }

                exit(1)
            }

            // Interactive mode - proceed with generation
            if !Environment.generateEnv() {
                fatalError("Failed to configure environment")
            }
        }

        startServer()
    }

    private static func startServer() {
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
