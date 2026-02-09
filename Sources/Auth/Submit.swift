import NIOHTTP1
import NIO
import Foundation
import Libmailer

struct AuthSubmit {
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
        return email == Environment.ADMIN_EMAIL && Environment.verifyPassword(password)
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
            let receiver = strdup(Environment.ADMIN_EMAIL)
            let subject = strdup("Your SelfAuth OTP")
            let htmlBody = """
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Your One-Time Password</title>
                </head>
                <body style="margin: 0; padding: 0; font-family: 'Courier New', Courier, monospace; background-color: #0a0e14; color: #e6e6e6;">
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #0a0e14; padding: 40px 20px;">
                        <tr>
                            <td align="center">
                                <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="max-width: 600px; background-color: #131820; border: 2px solid #2d3541; box-shadow: 0 0 30px rgba(0, 255, 136, 0.1);">
                                    <!-- Top accent line -->
                                    <tr>
                                        <td style="height: 2px; background: linear-gradient(90deg, transparent, #00ff88 30%, #00ddff 70%, transparent);"></td>
                                    </tr>
                                    
                                    <!-- Header -->
                                    <tr>
                                        <td style="padding: 40px 40px 20px 40px;">
                                            <h1 style="margin: 0; font-family: 'Courier New', Courier, monospace; font-size: 32px; font-weight: bold; color: #00ff88; letter-spacing: 3px; text-shadow: 0 0 10px rgba(0, 255, 136, 0.3);">
                                                AUTHENTICATION
                                            </h1>
                                            <p style="margin: 10px 0 0 0; font-size: 13px; color: #5c6370; letter-spacing: 1px;">
                                                <span style="color: #00ddff;">▸</span> SECURITY CODE REQUESTED
                                            </p>
                                        </td>
                                    </tr>
                                    
                                    <!-- Body -->
                                    <tr>
                                        <td style="padding: 20px 40px;">
                                            <p style="margin: 0 0 20px 0; font-size: 14px; color: #8a93a5; line-height: 1.6;">
                                                A one-time password has been requested for your account. Use the code below to complete your authentication:
                                            </p>
                                            
                                            <!-- OTP Code Box -->
                                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin: 30px 0;">
                                                <tr>
                                                    <td align="center">
                                                        <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="background-color: #1a1f28; border: 2px solid #00ff88; box-shadow: 0 0 20px rgba(0, 255, 136, 0.2);">
                                                            <tr>
                                                                <td style="padding: 25px 50px;">
                                                                    <p style="margin: 0; font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: bold; color: #00ff88; letter-spacing: 8px; text-align: center;">
                                                                        \(otp)
                                                                    </p>
                                                                </td>
                                                            </tr>
                                                        </table>
                                                    </td>
                                                </tr>
                                            </table>
                                            
                                            <p style="margin: 20px 0 0 0; font-size: 14px; color: #8a93a5; line-height: 1.6;">
                                                This code will expire in <strong style="color: #00ddff;">2 minutes</strong>. If you didn't request this code, please ignore this email.
                                            </p>
                                        </td>
                                    </tr>
                                    
                                    <!-- Security Notice -->
                                    <tr>
                                        <td style="padding: 0 40px 40px 40px;">
                                            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: rgba(255, 68, 102, 0.1); border-left: 3px solid #ff4466;">
                                                <tr>
                                                    <td style="padding: 15px 20px;">
                                                        <p style="margin: 0; font-size: 12px; color: #ff4466;">
                                                            <strong>✕ SECURITY NOTICE</strong>
                                                        </p>
                                                        <p style="margin: 5px 0 0 0; font-size: 12px; color: #8a93a5; line-height: 1.5;">
                                                            Never share this code with anyone. Our team will never ask for your OTP.
                                                        </p>
                                                    </td>
                                                </tr>
                                            </table>
                                        </td>
                                    </tr>
                                    
                                    <!-- Footer -->
                                    <tr>
                                        <td style="padding: 20px 40px 40px 40px; border-top: 1px solid #2d3541;">
                                            <p style="margin: 0; font-size: 11px; color: #5c6370; text-align: center; line-height: 1.5;">
                                                This is an automated message. Please do not reply to this email.<br>
                                                If you have any questions, contact your system administrator.
                                            </p>
                                        </td>
                                    </tr>
                                </table>
                            </td>
                        </tr>
                    </table>
                </body>
                </html>
                """

            let body = strdup("\(htmlBody)")
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
