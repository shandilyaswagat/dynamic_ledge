import AVFoundation
import SwiftUI

/// Camera permission, asked only when the user opens Mirror.
@MainActor
@Observable
final class CameraAccess {
    enum State: Equatable {
        case notAsked
        case granted
        case denied
        case noCamera
    }

    private(set) var state: State = CameraAccess.current()

    func refresh() {
        state = Self.current()
    }

    func request() {
        // Come forward so the permission dialog appears (see CalendarService.requestAccess).
        NSApp.activate()
        Task { [weak self] in
            _ = await AVCaptureDevice.requestAccess(for: .video)
            self?.refresh()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func current() -> State {
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }
}

/// Live, mirrored camera preview. The camera runs only while this view is on screen.
struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView()
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ view: CameraPreviewView, coordinator: ()) {
        view.stop()
    }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    /// AVCaptureSession start/stop block, so they run on their own queue.
    private let queue = DispatchQueue(label: "notch.mirror.camera")

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { startRunning() }
    }

    func stop() {
        // AVCaptureSession is thread-safe for start/stop; it just isn't marked Sendable.
        nonisolated(unsafe) let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func startRunning() {
        nonisolated(unsafe) let session = session
        queue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
