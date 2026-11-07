import SwiftUI
import AVFoundation

struct CameraTab: View {
    let controller: CameraController
    /// The one preview view for the whole run of the app (see `CameraPreview`).
    let preview: PreviewView

    var body: some View {
        ZStack {
            switch controller.state {
            case .running:
                // The preview is clear until the first picture arrives, so the spinner behind it shows while the
                // camera warms up (a second or so) instead of an empty black box.
                ZStack {
                    ProgressView().controlSize(.small)
                    CameraPreview(view: preview)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            case .stopped:
                ProgressView().controlSize(.small)
            case .denied:
                message(
                    "Camera access is off for Island.",
                    detail: "Turn it on in System Settings to use the mirror.",
                    systemImage: "camera.fill")
                    {
                        PillButton(title: "Open Privacy Settings", prominent: true) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
            case .restricted:
                message(
                    "Camera access is restricted on this Mac.",
                    detail: "A profile or Screen Time setting is blocking it.",
                    systemImage: "lock.fill") { EmptyView() }
            case .noCamera:
                message("No camera found.", detail: "Connect a camera and open this tab again.", systemImage: "video.slash") {
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The camera runs only while this tab is on screen: leaving the tab or collapsing the island removes it.
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }

    private func message<Action: View>(
        _ title: String, detail: String, systemImage: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(.white.opacity(0.5))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6))
            action()
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }
}

/// Shows the app's single preview view. It is created once and attached to the camera session once; the tab only puts
/// that same view on screen and takes it off again. Making a new preview layer on every visit meant attaching it to the
/// session on the main thread at the very moment the camera thread was starting the session, and AVFoundation crashes
/// ("collection was mutated while being enumerated") when those two overlap.
struct CameraPreview: NSViewRepresentable {
    let view: PreviewView

    func makeNSView(context: Context) -> PreviewView { view }

    func updateNSView(_ nsView: PreviewView, context: Context) {}
}

final class PreviewView: NSView {
    override func makeBackingLayer() -> CALayer { AVCaptureVideoPreviewLayer() }

    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var startObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        mirror()
        // The preview's connection to the camera only exists once the session has its input and is running, which
        // happens a moment after this view is made, so mirroring is set again when it starts.
        startObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirror() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("PreviewView is created in code")
    }

    deinit {
        if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
    }

    /// Mirrors the picture explicitly instead of trusting macOS's default, which mirrors a built-in camera but not an
    /// external one. (An earlier version also flipped the layer itself, which undid the system's own mirroring and
    /// made the picture move the wrong way.)
    private func mirror() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
        if !connection.isVideoMirrored { connection.isVideoMirrored = true }
    }
}
