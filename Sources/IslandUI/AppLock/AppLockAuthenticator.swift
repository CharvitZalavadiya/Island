import Foundation
import LocalAuthentication

enum LockAuthResult: Equatable {
    case success
    /// The person dismissed it, or it was stopped because they went elsewhere: nothing to say.
    case cancelled
    /// It did not recognise them. Say so: the password is still there.
    case failed(String)
    /// It cannot be used right now (no Touch ID, too many tries). Say why: the password is still there.
    case unavailable(String)
}

/// What App lock asks of the Mac to know who is there, so it can be tried without a finger or a password dialog.
@MainActor
protocol LockAuthenticating: AnyObject {
    /// Whether this Mac has Touch ID set up. Never shows anything.
    var touchIDAvailable: Bool { get }
    /// Asks for a finger on the sensor.
    func authenticateWithTouchID(reason: String) async -> LockAuthResult
    /// Asks for the Mac's own login password (or Touch ID): the way back in for someone who forgot the App lock password.
    func authenticateWithMacPassword(reason: String) async -> LockAuthResult
    /// Stops whatever is being asked, and closes its dialog.
    func cancel()
}

@MainActor
final class SystemLockAuthenticator: LockAuthenticating {
    private var context: LAContext?

    var touchIDAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithTouchID(reason: String) async -> LockAuthResult {
        await evaluate(.deviceOwnerAuthenticationWithBiometrics, reason: reason, touchOnly: true)
    }

    func authenticateWithMacPassword(reason: String) async -> LockAuthResult {
        await evaluate(.deviceOwnerAuthentication, reason: reason, touchOnly: false)
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }

    private func evaluate(_ policy: LAPolicy, reason: String, touchOnly: Bool) async -> LockAuthResult {
        cancel()
        let context = LAContext()
        if touchOnly {
            // Island has its own password box, so the dialog needs no "Enter Password" button of its own.
            context.localizedFallbackTitle = ""
            context.localizedCancelTitle = "Use password"
        }
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else { return Self.result(for: error) }
        self.context = context
        defer { if self.context === context { self.context = nil } }
        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason) ? .success : .failed("That did not work.")
        } catch {
            return Self.result(for: error)
        }
    }

    /// What an error from the Mac means for the person.
    nonisolated static func result(for error: Error?) -> LockAuthResult {
        guard let code = (error as? LAError)?.code else { return .failed(error?.localizedDescription ?? "That did not work.") }
        switch code {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return .cancelled
        case .authenticationFailed:
            return .failed("Touch ID did not recognise you. Try again, or use the password.")
        case .biometryLockout:
            return .unavailable("Touch ID is locked after too many tries. Use the password.")
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .unavailable("Touch ID is not available on this Mac. Use the password.")
        default:
            return .failed(error?.localizedDescription ?? "That did not work.")
        }
    }
}
