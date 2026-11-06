import AVFoundation
import UIKit

enum ExportError: Error { case failed }

enum TimelapseExporter {
    struct Frame: Sendable {
        let url: URL
        let label: String
    }

    private static let size = CGSize(width: 1080, height: 1440)
    private static let secondsPerFrame = 0.6
    private static let finalHoldSeconds = 1.6

    nonisolated static func video(frames: [Frame], watermark: Bool) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "Gainlapse-timelapse-\(UUID().uuidString.prefix(6)).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        guard writer.canAdd(input) else { throw ExportError.failed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.failed }
        writer.startSession(atSourceTime: .zero)

        var time = 0.0
        var lastBuffer: CVPixelBuffer?
        for frame in frames {
            let rendered = autoreleasepool { render(frame: frame, watermark: watermark) }
            guard let buffer = pixelBuffer(from: rendered, adaptor: adaptor) else { throw ExportError.failed }
            try await append(buffer, at: time, input: input, adaptor: adaptor)
            lastBuffer = buffer
            time += secondsPerFrame
        }
        // Hold the latest photo so the video ends on it.
        if let lastBuffer {
            time += finalHoldSeconds
            try await append(lastBuffer, at: time - secondsPerFrame, input: input, adaptor: adaptor)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.failed }
        return url
    }

    nonisolated static func sideBySide(first: Frame, latest: Frame, watermark: Bool) throws -> URL {
        let panel = CGSize(width: 810, height: 1080)
        let gap: CGFloat = 12
        let canvas = CGSize(width: panel.width * 2 + gap, height: panel.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            draw(frame: first, in: CGRect(origin: .zero, size: panel))
            draw(frame: latest, in: CGRect(x: panel.width + gap, y: 0, width: panel.width, height: panel.height))
            if watermark { drawWatermark(in: canvas) }
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw ExportError.failed }
        let url = URL.temporaryDirectory.appending(path: "Gainlapse-comparison-\(UUID().uuidString.prefix(6)).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    private nonisolated static func render(frame: Frame, watermark: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(frame: frame, in: CGRect(origin: .zero, size: size))
            if watermark { drawWatermark(in: size) }
        }
    }

    private nonisolated static func draw(frame: Frame, in rect: CGRect) {
        guard let image = ImageLoader.load(url: frame.url, maxPixels: 1600) else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(rect: rect).addClip()
        image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
        UIGraphicsGetCurrentContext()?.restoreGState()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: rect.width * 0.05, weight: .heavy),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black.withAlphaComponent(0.45),
            .strokeWidth: -2,
        ]
        (frame.label as NSString).draw(at: CGPoint(x: rect.minX + rect.width * 0.045, y: rect.minY + rect.width * 0.045),
                                       withAttributes: attributes)
    }

    private nonisolated static func drawWatermark(in canvas: CGSize) {
        let text = "made with Gainlapse" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .strokeColor: UIColor.black.withAlphaComponent(0.35),
            .strokeWidth: -1.5,
        ]
        let measured = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: canvas.width - measured.width - 32, y: canvas.height - measured.height - 28),
                  withAttributes: attributes)
    }

    private nonisolated static func pixelBuffer(from image: UIImage, adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool, let cg = image.cgImage else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    private nonisolated static func append(_ buffer: CVPixelBuffer, at seconds: Double, input: AVAssetWriterInput,
                                           adaptor: AVAssetWriterInputPixelBufferAdaptor) async throws {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600)) else {
            throw ExportError.failed
        }
    }
}
