@preconcurrency import AVFoundation
import SwiftUI
import UIKit

#if targetEnvironment(simulator)
let hasRealCamera = false
#else
let hasRealCamera = true
#endif

/// Runs the capture session on its own queue and hands photos back upright, 3:4, and sized for storage.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Access { case unknown, granted, denied }

    @Published var access: Access = hasRealCamera ? .unknown : .granted
    @Published var position: AVCaptureDevice.Position = .front

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "gainlapse.camera")
    private var isConfigured = false
    private var completion: ((UIImage?) -> Void)?

    func start() async {
        guard hasRealCamera else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            granted = status == .authorized
        }
        await MainActor.run { access = granted ? .granted : .denied }
        guard granted else { return }
        queue.async { [self] in
            if !isConfigured { configure(position: .front) }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flip() {
        guard hasRealCamera else { return }
        let next: AVCaptureDevice.Position = position == .front ? .back : .front
        position = next
        queue.async { [self] in configure(position: next) }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
        isConfigured = true
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            self.completion = completion
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:)).map(Self.prepare)
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async { completion?(image) }
    }

    /// Draws the photo upright, center-cropped to 3:4, at most 1600 pixels tall.
    static func prepare(_ image: UIImage) -> UIImage {
        let target = CGSize(width: 1200, height: 1600)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
