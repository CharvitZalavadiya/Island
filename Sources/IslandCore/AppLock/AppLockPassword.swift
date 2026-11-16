import CommonCrypto
import Foundation

/// What is kept of App lock's password: never the password, only a salted hash that is deliberately slow to compute, so a copy of
/// the file cannot be turned back into the password by trying words quickly.
public struct AppLockPasswordRecord: Codable, Equatable, Sendable {
    public var version = 1
    public var rounds: Int
    public var salt: Data
    public var hash: Data

    /// Whether this is a record this version of Island can check a password against. A record that was cut short or changed by
    /// hand is NOT valid, and App lock then treats the password as not set (it never keeps a person out because of a damaged
    /// file); a huge `rounds` could otherwise freeze the island while it was being checked.
    public var isValid: Bool {
        version == 1 && AppLockPassword.roundsRange.contains(rounds) && salt.count == AppLockPassword.saltLength
            && hash.count == AppLockPassword.hashLength
    }
}

public enum AppLockPassword {
    public static let minimumLength = 4
    /// About 30 ms on an M-series Mac: unnoticeable for one try, slow for a program trying millions.
    public static let rounds = 200_000
    public static let roundsRange = 10_000...5_000_000
    static let saltLength = 16
    static let hashLength = 32

    public enum Problem: Equatable, Sendable {
        case tooShort
        case doesNotMatch
    }

    /// What is wrong with a new password and its repeat, if anything.
    public static func problem(newPassword: String, repeated: String) -> Problem? {
        guard newPassword.count >= minimumLength else { return .tooShort }
        guard newPassword == repeated else { return .doesNotMatch }
        return nil
    }

    /// The record for `password`, with a fresh random salt (`salt` and `rounds` are only for tests).
    public static func makeRecord(for password: String, rounds: Int = AppLockPassword.rounds, salt: Data? = nil) -> AppLockPasswordRecord? {
        let salt = salt ?? Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
        guard let hash = derive(password, salt: salt, rounds: rounds) else { return nil }
        return AppLockPasswordRecord(rounds: rounds, salt: salt, hash: hash)
    }

    public static func matches(_ password: String, record: AppLockPasswordRecord) -> Bool {
        guard record.isValid, let hash = derive(password, salt: record.salt, rounds: record.rounds) else { return false }
        // Every byte is compared whatever the first ones were, so the time taken says nothing about how close the guess was.
        var difference: UInt8 = 0
        for (a, b) in zip(hash, record.hash) { difference |= a ^ b }
        return difference == 0
    }

    private static func derive(_ password: String, salt: Data, rounds: Int) -> Data? {
        // The same letters typed on another keyboard (é as one character or as e and an accent) must be the same password.
        let bytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        var output = Data(count: hashLength)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                bytes.withUnsafeBufferPointer { pass in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                        bytes.count, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                        out.bindMemory(to: UInt8.self).baseAddress, hashLength)
                }
            }
        }
        return status == kCCSuccess ? output : nil
    }
}
