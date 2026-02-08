import Foundation

actor OTPStore {
    static let shared = OTPStore()

    private struct Entry {
        let expiresAt: Date
    }

    // otp → entry
    private var storage: [String: Entry] = [:]

    func createOTP() -> String {
        let otp = String(format: "%06d", Int.random(in: 0..<1_000_000))
        let entry = Entry(
            expiresAt: Date().addingTimeInterval(120)  // 2 minutes
        )

        storage[otp] = entry
        scheduleRemoval(for: otp, at: entry.expiresAt)

        return otp
    }

    func validateOTP(otp: String) -> Bool {
        guard let entry = storage[otp] else { return false }

        guard entry.expiresAt > Date() else {
            storage[otp] = nil
            return false
        }

        // OTP is single-use
        storage[otp] = nil
        return true
    }

    func invalidateOTP(_ otp: String) {
        storage[otp] = nil
    }

    private func scheduleRemoval(for otp: String, at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            storage[otp] = nil
            return
        }

        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            self.removeIfExpired(otp: otp)
        }
    }

    private func removeIfExpired(otp: String) {
        guard let entry = storage[otp] else { return }
        if entry.expiresAt <= Date() {
            storage[otp] = nil
        }
    }
}
