import Foundation

enum AudioCaptureStatus: Equatable {
    case granted
    case denied
    /// macOS has not asked yet.
    case unknown
}

/// Whether Island may listen to another app's sound, which turning that app down needs (the app's sound is taken
/// over and played again at the new volume). macOS asks the user once.
protocol AudioCapturePermissionChecking: AnyObject {
    func status() -> AudioCaptureStatus
    /// Shows the system's question. `completion` is told the answer, on the main thread.
    func request(_ completion: @escaping @MainActor (Bool) -> Void)
}

/// The system's own record of the permission, read the way other apps that record system sound read it.
final class SystemAudioCapturePermission: AudioCapturePermissionChecking {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString

    private let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    func status() -> AudioCaptureStatus {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .denied }   // cannot tell: do not tap
        switch unsafeBitCast(symbol, to: Preflight.self)(Self.service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else {
            Task { @MainActor in completion(false) }
            return
        }
        unsafeBitCast(symbol, to: Request.self)(Self.service, nil) { granted in
            Task { @MainActor in completion(granted) }
        }
    }
}
