import NIOHTTP1
import NIO
import Foundation
import Libmailer

struct AuthSubmit {
    // TODO: Maybe we don't want to be hardcodig my email
    private static let adminEmail = "personal@jelius.dev"

    static func handler(req: HTTPRequest) -> APIRouter.Response {
        return APIRouter.runSync {
            // Parse request body (assume JSON for now)
            guard let body = req.body,
                let payload = parseAuthPayload(from: body)
            else {
                return .Error(.badRequest("Bad Request"))
            }

            switch payload {
            case let .emailPassword(email, password):
                // Email + password flow
                guard validatePassword(email: email, password: password) else {
                    return .Error(.unauthorized)
                }

                // Second step: create OTP after password validation
                let otp = await OTPStore.shared.createOTP()
                guard sendOTPMail(otp) else {
                    await OTPStore.shared.invalidateOTP(otp)
                    return .Error(.internalError)
                }

                return .Success(
                    HTTPResponse(
                        status: .ok,
                        headers: HTTPHeaders(),
                        body: nil
                    )
                )

            case let .otp(code):
                // OTP flow
                guard await OTPStore.shared.validateOTP(otp: code) else {
                    return .Error(.unauthorized)
                }

                // Create auth token after successful authentication
                let token = await TokenStore.shared.createToken()

                return .Success(
                    HTTPResponse(
                        status: .ok,
                        headers: HTTPHeaders([
                            ("Set-Cookie", "auth_token=\(token); HttpOnly; Path=/; SameSite=Strict")
                        ]),
                        body: nil
                    )
                )
            }
        }
    }

    private enum AuthPayload {
        case emailPassword(email: String, password: String)
        case otp(String)
    }

    // TODO (Security): Replace with a context-aware parser.
    // TODO (Security): Bind issued OTPs to the browser/IP/client that requested them
    //                  to prevent cross-client OTP reuse.
    // TODO (Security): Enforce authentication flow ordering by rejecting OTP
    //                  verification attempts that are not preceded by a successful
    //                  email + password validation.
    private static func parseAuthPayload(from buffer: ByteBuffer) -> AuthPayload? {
        guard
            let string = buffer.getString(
                at: buffer.readerIndex,
                length: buffer.readableBytes
            ),
            let data = string.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let email = json["email"] as? String
        let password = json["password"] as? String
        let otp = json["otp"] as? String

        switch (email, password, otp) {
        case let (.some(email), .some(password), nil):
            return .emailPassword(email: email, password: password)

        case let (nil, nil, .some(otp)):
            return .otp(otp)

        default:
            // any other combination is invalid
            return nil
        }
    }

    private static func validatePassword(email: String, password: String) -> Bool {
        // TODO: Move this to external variables and don't use plain text passwords
        return email == adminEmail && password == "123456789"
    }

    private static func sendOTPMail(_ otp: String) -> Bool {
        var config: UnsafeMutablePointer<MailerConfig>? = nil
        var error: UnsafeMutablePointer<CChar>? = nil

        // Load configuration from default location (~/.config/mailer/config.json)
        // Make sure that the server process runs as casual user otherwise use `LoadConfigFromPath` function.
        let status = LoadConfig(&config, &error)
        if status != 0 {
            if let error = error {
                let errorString = String(cString: error)
                print("error: \(errorString)")
                FreeCString(error)
            }

            return false
        }

        if let config = config {
            let receiver = strdup(adminEmail)
            let subject = strdup("Your OTP")
            let body = strdup("\(otp)")
            var ret = true

            defer {
                free(receiver)
                free(subject)
                free(body)
            }

            let status = SendMail(
                config.pointee.Host,
                config.pointee.Port,
                config.pointee.Username,
                config.pointee.Password,
                config.pointee.From,
                receiver,
                subject,
                body,
                nil,
                nil,
                nil,
                &error
            )

            if status != 0 {
                if let error = error {
                    let errorString = String(cString: error)
                    print("Failed to send OTP Email: \(errorString)")
                    FreeCString(error)

                    ret = false
                }
            }

            FreeMailerConfig(config)
            return ret
        }

        return false
    }
}
