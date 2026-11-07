import AVFoundation
import Observation

enum CameraAccess {
    case notDetermined, authorized, denied, restricted
}

/// Asks macOS whether Island may use the camera. The real one is `SystemCameraAuthorizer`; tests use a fake.
protocol CameraAuthorizing {
    func currentAccess() -> CameraAccess
    func requestAccess() async -> Bool
}

/// Turns the camera on and off. The real one is `SystemCameraCapture`; tests use a fake.
protocol CameraCapturing: AnyObject {
    var hasCamera: Bool { get }
    func start()
    func stop()
}

enum CameraState: Equatable {
    /// Not running (or still waiting for permission).
    case stopped
    case running
    case denied
    case restricted
    case noCamera
}

/// Runs the camera only while the Camera tab is visible, and never when permission has not been given.
@Observable
@MainActor
final class CameraController {
    private(set) var state: CameraState = .stopped

    @ObservationIgnored private let authorizer: CameraAuthorizing
    @ObservationIgnored private let capture: CameraCapturing
    /// True from `start()` until `stop()`: lets a permission prompt that is answered after the tab was left do nothing.
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var isStarting = false

    init(authorizer: CameraAuthorizing, capture: CameraCapturing) {
        self.authorizer = authorizer
        self.capture = capture
    }

    /// Called when the tab appears. Permission is checked every time, so granting it later in System Settings works.
    func start() async {
        wantsRunning = true
        guard state != .running, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        var access = authorizer.currentAccess()
        if access == .notDetermined {
            access = await authorizer.requestAccess() ? .authorized : .denied
            guard wantsRunning else {
                state = .stopped
                return
            }
        }
        switch access {
        case .authorized:
            guard capture.hasCamera else {
                state = .noCamera
                return
            }
            capture.start()
            state = .running
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .stopped
        }
    }

    /// Called when the tab goes away or the island collapses. Turns the camera (and its light) off.
    func stop() {
        wantsRunning = false
        if state == .running { capture.stop() }
        state = .stopped
    }
}

struct SystemCameraAuthorizer: CameraAuthorizing {
    func currentAccess() -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// The real capture session. Starting and stopping a session blocks, so both happen on a private queue.
final class SystemCameraCapture: CameraCapturing, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.island.camera")
    private var configured = false

    var hasCamera: Bool { Self.device() != nil }

    // `isRunning` can still read true for a moment after `stopRunning()`, so checking it before restarting could skip the
    // restart when the tab is left and re-entered quickly, leaving a dead preview. `startRunning()` and `stopRunning()`
    // do nothing when the session is already in that state, so they are simply called every time, in order, on one queue.
    func start() {
        queue.async { [self] in
            configureIfNeeded()
            if configured { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            session.stopRunning()
        }
    }

    private func configureIfNeeded() {
        guard !configured, let device = Self.device(),
            let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
        else { return }
        session.beginConfiguration()
        if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        session.addInput(input)
        session.commitConfiguration()
        configured = true
    }

    private static func device() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified
            ).devices.first
    }
}
