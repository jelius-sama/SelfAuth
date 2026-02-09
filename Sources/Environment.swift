import Foundation
import Crypto

struct Environment {
    public let ADMIN_EMAIL: String
    public let SALTED_PASS: String
    public static let VERSION = "1.0.0"

    private static let ENV_DIR = "/etc/SelfAuth"
    private static let ENV_FILE = "/etc/SelfAuth/env"

    private static let shared: Environment = {
        guard let env = loadEnvironment() else {
            fatalError("Environment not configured. Call configureEnv() or generateEnv() first.")
        }
        return env
    }()

    public static var ADMIN_EMAIL: String {
        shared.ADMIN_EMAIL
    }

    public static var SALTED_PASS: String {
        shared.SALTED_PASS
    }

    /// Configure environment by reading from /etc/SelfAuth/env
    /// Returns true if the file is valid and readable
    static func configureEnv() -> Bool {
        guard loadEnvironment() != nil else {
            print(
                "\(Color.red)Invalid environment file: missing ADMIN_EMAIL or SALTED_PASS\(Color.reset)"
            )
            return false
        }

        print("\(Color.green)Environment configured successfully\(Color.reset)")
        return true
    }

    /// Pure loader used by the lazy singleton
    private static func loadEnvironment() -> Environment? {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: ENV_FILE),
            let contents = try? String(contentsOfFile: ENV_FILE, encoding: .utf8)
        else {
            return nil
        }

        var email: String?
        var saltedPass: String?

        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "ADMIN_EMAIL":
                email = value
            case "SALTED_PASS":
                saltedPass = value
            default:
                break
            }
        }

        guard let email, let saltedPass else {
            return nil
        }

        return Environment(
            ADMIN_EMAIL: email,
            SALTED_PASS: saltedPass
        )
    }

    @discardableResult
    static func generateEnv() -> Bool {
        print("\(Color.cyan)\(Color.bold)╔════════════════════════════════════════╗\(Color.reset)")
        print("\(Color.cyan)\(Color.bold)║   SelfAuth Environment Configuration   ║\(Color.reset)")
        print(
            "\(Color.cyan)\(Color.bold)╚════════════════════════════════════════╝\(Color.reset)\n")

        print("\(Color.blue)Enter admin email:\(Color.reset) ", terminator: "")
        guard let email = readLine()?.trimmingCharacters(in: .whitespaces), !email.isEmpty else {
            print("\(Color.red)Email cannot be empty\(Color.reset)")
            exit(1)
        }

        print("\(Color.blue)Enter admin password:\(Color.reset) ", terminator: "")
        guard let password = readLine()?.trimmingCharacters(in: .whitespaces), !password.isEmpty
        else {
            print("\(Color.red)Password cannot be empty\(Color.reset)")
            exit(1)
        }

        let saltedPassword = saltPassword(password)

        let envContent = """
            # SelfAuth Environment Configuration
            # Generated on \(Date())

            ADMIN_EMAIL=\(email)
            SALTED_PASS=\(saltedPassword)
            """

        let fileManager = FileManager.default

        do {
            if !fileManager.fileExists(atPath: ENV_DIR) {
                try fileManager.createDirectory(
                    atPath: ENV_DIR,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            try envContent.write(toFile: ENV_FILE, atomically: true, encoding: .utf8)

            print(
                "\n\(Color.green)\(Color.bold)Environment file created successfully!\(Color.reset)"
            )
            print("\(Color.green)  Location: \(ENV_FILE)\(Color.reset)\n")

            return true
        } catch {
            print("\n\(Color.yellow)\(Color.bold)Permission Denied\(Color.reset)")
            print("\(Color.yellow)Unable to write to \(ENV_FILE)\(Color.reset)\n")

            printManualInstructions(envContent: envContent)
            exit(0)
        }
    }

    private static func printManualInstructions(envContent: String) {
        print(
            "\(Color.cyan)\(Color.bold)╔════════════════════════════════════════════════════════════╗\(Color.reset)"
        )
        print(
            "\(Color.cyan)\(Color.bold)║          Manual Configuration Required                     ║\(Color.reset)"
        )
        print(
            "\(Color.cyan)\(Color.bold)╚════════════════════════════════════════════════════════════╝\(Color.reset)\n"
        )

        print("\(Color.magenta)Please run the following commands as root/sudo:\(Color.reset)\n")

        print("\(Color.yellow)# Create the directory\(Color.reset)")
        print("\(Color.bold)sudo mkdir -p \(ENV_DIR)\(Color.reset)\n")

        print("\(Color.yellow)# Create the environment file\(Color.reset)")
        print("\(Color.bold)sudo tee \(ENV_FILE) > /dev/null << 'EOF'\(Color.reset)")
        print(envContent)
        print("\(Color.bold)EOF\(Color.reset)\n")

        print("\(Color.yellow)# Set proper permissions\(Color.reset)")
        print("\(Color.bold)sudo chmod 600 \(ENV_FILE)\(Color.reset)")
        print("\(Color.bold)sudo chown $(whoami):$(whoami) \(ENV_FILE)\(Color.reset)\n")

        print("\(Color.green)After running these commands, restart the server.\(Color.reset)\n")
    }

    private static func saltPassword(_ password: String) -> String {
        let salt = UUID().uuidString
        let combined = password + salt
        let hashed = SHA256.hash(data: Data(combined.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined() + ":" + salt
    }

    static func verifyPassword(_ password: String) -> Bool {
        let parts = SALTED_PASS.split(separator: ":")
        guard parts.count == 2 else { return false }

        let storedHash = String(parts[0])
        let salt = String(parts[1])

        let combined = password + salt
        let hashed = SHA256.hash(data: Data(combined.utf8))
        let computedHash = hashed.map { String(format: "%02x", $0) }.joined()

        return computedHash == storedHash
    }
}
