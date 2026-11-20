import AVFoundation
import UIKit

enum ExportError: Error { case failed }

/// Makes shareable 9:16 videos and images sized for TikTok, Reels and Stories.
/// Everything important sits inside the area those apps leave clear of their captions and buttons.
enum TimelapseExporter {
    struct Frame: Sendable {
        let url: URL
        let week: Int
    }

    static let canvas = CGSize(width: 1080, height: 1920)
    private static let fps: Int32 = 30
    private static let fadeFrames = 6
    private static let endCardSeconds = 2.2

    private nonisolated static let accent = UIColor(red: 1.0, green: 0.353, blue: 0.122, alpha: 1)
    private nonisolated static let background = UIColor(red: 0.055, green: 0.047, blue: 0.043, alpha: 1)
    private nonisolated static let secondary = UIColor.white.withAlphaComponent(0.68)
    private nonisolated static let margin: CGFloat = 96

    // MARK: Video

    nonisolated static func video(frames: [Frame], branded: Bool) async throws -> URL {
        guard !frames.isEmpty else { throw ExportError.failed }
        let url = URL.temporaryDirectory.appending(path: "Gainlapse-timelapse-\(UUID().uuidString.prefix(6)).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: canvas.width,
            AVVideoHeightKey: canvas.height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: canvas.width,
            kCVPixelBufferHeightKey as String: canvas.height,
        ])
        guard writer.canAdd(input) else { throw ExportError.failed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.failed }
        writer.startSession(atSourceTime: .zero)

        // A short timelapse plays slower so each week can still be seen.
        let holdFrames = Int(Double(fps) * (frames.count <= 4 ? 0.9 : frames.count <= 12 ? 0.6 : 0.4))
        let first = frames[0].week
        let last = frames[frames.count - 1].week
        var frameIndex = 0
        var previous: UIImage?

        func write(_ image: UIImage) async throws {
            guard let buffer = pixelBuffer(from: image, adaptor: adaptor) else { throw ExportError.failed }
            try await append(buffer, frame: frameIndex, input: input, adaptor: adaptor)
        }

        for (position, frame) in frames.enumerated() {
            let progress = frames.count > 1 ? CGFloat(position) / CGFloat(frames.count - 1) : 1
            let current = autoreleasepool {
                timelapseFrame(frame, progress: progress, range: (first, last), branded: branded)
            }
            if let previous {
                for step in 1...fadeFrames {
                    let blended = autoreleasepool { blend(previous, current, amount: CGFloat(step) / CGFloat(fadeFrames)) }
                    try await write(blended)
                    frameIndex += 1
                }
            }
            try await write(current)
            frameIndex += holdFrames
            previous = current
        }
        // Hold the latest week a little longer, then end on the card that says where it was made.
        frameIndex += holdFrames
        if branded, let previous {
            let card = autoreleasepool { endCard(range: (first, last), weeks: frames.count) }
            for step in 1...fadeFrames {
                let blended = autoreleasepool { blend(previous, card, amount: CGFloat(step) / CGFloat(fadeFrames)) }
                try await write(blended)
                frameIndex += 1
            }
            try await write(card)
            frameIndex += Int(Double(fps) * endCardSeconds)
        } else if let previous {
            try await write(previous)
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameIndex), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.failed }
        return url
    }

    // MARK: Still image

    /// One photo becomes a week-one card. Two or more become the first week against the latest.
    nonisolated static func still(frames: [Frame], branded: Bool) throws -> URL {
        let image = stillImage(frames: frames, branded: branded)
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw ExportError.failed }
        let name = frames.count > 1 ? "comparison" : "week-1"
        let url = URL.temporaryDirectory.appending(path: "Gainlapse-\(name)-\(UUID().uuidString.prefix(6)).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// A small rendering of what the export will look like, for the share screen.
    nonisolated static func preview(frames: [Frame], video: Bool, branded: Bool) -> UIImage? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if video {
            return timelapseFrame(last, progress: 1, range: (first.week, last.week), branded: branded)
        }
        return stillImage(frames: frames, branded: branded)
    }

    private nonisolated static func stillImage(frames: [Frame], branded: Bool) -> UIImage {
        render { _ in
            fillBackground(glow: true)
            guard let first = frames.first, let last = frames.last else { return }
            let isComparison = frames.count > 1
            // Photos are sized so the whole layout fits between the top bar and the caption area of TikTok and Reels.
            let edge: CGFloat = isComparison ? 60 : 150
            let gap: CGFloat = 18
            let photoWidth = isComparison ? (canvas.width - edge * 2 - gap) / 2 : canvas.width - edge * 2
            let photoHeight = isComparison ? photoWidth * 1.5 : photoWidth * 4 / 3
            let blockHeight = (branded ? 96 : 0) + 50 + 210 + photoHeight + (branded ? 90 : 0)
            var y = max(150, 150 + (1600 - 150 - blockHeight) / 2)
            if branded {
                drawBrandRow(at: y, left: edge)
                y += 96
            }
            if isComparison {
                drawStamp("\(last.week - first.week) \(last.week - first.week == 1 ? "WEEK" : "WEEKS") APART",
                          at: CGPoint(x: edge, y: y), color: accent)
                y += 50
                drawWeekRange(first: first.week, last: last.week, at: CGPoint(x: edge, y: y), size: 170)
                y += 210
                let left = CGRect(x: edge, y: y, width: photoWidth, height: photoHeight)
                let right = CGRect(x: edge + photoWidth + gap, y: y, width: photoWidth, height: photoHeight)
                drawPhoto(first.url, in: left, cornerRadius: 30)
                drawPhoto(last.url, in: right, cornerRadius: 30)
                drawPhotoTag("WEEK \(first.week)", in: left)
                drawPhotoTag("WEEK \(last.week)", in: right, highlighted: true)
                y = left.maxY + 34
            } else {
                drawStamp("DAY ONE", at: CGPoint(x: edge, y: y), color: accent)
                y += 50
                drawHeadline("WEEK \(first.week)", at: CGPoint(x: edge, y: y), size: 190, color: .white)
                y += 220
                let rect = CGRect(x: edge, y: y, width: photoWidth, height: photoHeight)
                drawPhoto(first.url, in: rect, cornerRadius: 36)
                y = rect.maxY + 34
            }
            if branded {
                drawCaption("One photo a week. Watch it add up.", at: CGPoint(x: edge, y: y))
            }
        }
    }

    // MARK: Frames

    private nonisolated static func timelapseFrame(_ frame: Frame, progress: CGFloat, range: (Int, Int),
                                                   branded: Bool) -> UIImage {
        render { _ in
            fillBackground(glow: false)
            var y: CGFloat = 200
            if branded { drawBrandRow(at: y) }
            y += 90
            let headline = "WEEK \(frame.week)"
            drawHeadline(headline, at: CGPoint(x: margin, y: y), size: 170, color: .white)
            if range.1 > range.0 {
                let width = (headline as NSString).size(withAttributes: [.font: brandFont(170)]).width
                drawStamp("OF \(range.1)", at: CGPoint(x: margin + width + 20, y: y + 132), color: secondary)
            }
            y += 206
            // How far through the timelapse this frame is.
            let track = CGRect(x: margin, y: y, width: canvas.width - margin * 2, height: 8)
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 4).fill()
            accent.setFill()
            UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: max(track.width * progress, 8),
                                             height: track.height), cornerRadius: 4).fill()
            y += 34
            let width = canvas.width - margin * 2
            drawPhoto(frame.url, in: CGRect(x: margin, y: y, width: width, height: width * 4 / 3), cornerRadius: 36)
        }
    }

    private nonisolated static func endCard(range: (Int, Int), weeks: Int) -> UIImage {
        render { _ in
            fillBackground(glow: true)
            let center = canvas.width / 2
            drawBarbell(plates: min(max(weeks, 1), 8), center: CGPoint(x: center, y: 620), height: 150)
            drawCentered("GAINLAPSE", y: 720, font: brandFont(230), color: .white)
            drawCentered("One photo a week.", y: 990, font: .systemFont(ofSize: 50, weight: .bold), color: .white)
            drawCentered("A timelapse of every gain.", y: 1056, font: .systemFont(ofSize: 50, weight: .bold), color: secondary)
            drawCentered("SEARCH GAINLAPSE ON THE APP STORE", y: 1200, font: stampFont(32), color: accent, tracking: 3)
        }
    }

    // MARK: Drawing

    private nonisolated static func render(_ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image(actions: draw)
    }

    private nonisolated static func blend(_ from: UIImage, _ to: UIImage, amount: CGFloat) -> UIImage {
        render { _ in
            from.draw(at: .zero)
            to.draw(at: .zero, blendMode: .normal, alpha: amount)
        }
    }

    private nonisolated static func fillBackground(glow: Bool) {
        background.setFill()
        UIRectFill(CGRect(origin: .zero, size: canvas))
        guard glow, let context = UIGraphicsGetCurrentContext() else { return }
        let colors = [accent.withAlphaComponent(0.32).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
        else { return }
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: canvas.width / 2, y: 0), startRadius: 0,
                                   endCenter: CGPoint(x: canvas.width / 2, y: 0), endRadius: 1100, options: [])
    }

    private nonisolated static func brandFont(_ size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .black, width: .compressed)
    }

    private nonisolated static func stampFont(_ size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    private nonisolated static func drawBrandRow(at y: CGFloat, left: CGFloat = margin) {
        drawBarbell(plates: 5, center: CGPoint(x: left + 70, y: y + 32), height: 56)
        ("GAINLAPSE" as NSString).draw(at: CGPoint(x: left + 158, y: y - 6),
                                       withAttributes: [.font: brandFont(76), .foregroundColor: UIColor.white])
    }

    private nonisolated static func drawHeadline(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: brandFont(size), .foregroundColor: color])
    }

    private nonisolated static func drawWeekRange(first: Int, last: Int, at point: CGPoint, size: CGFloat) {
        let font = brandFont(size)
        let text = NSMutableAttributedString(string: "WEEK \(first) ", attributes: [.font: font, .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: "→", attributes: [.font: font, .foregroundColor: accent]))
        text.append(NSAttributedString(string: " \(last)", attributes: [.font: font, .foregroundColor: UIColor.white]))
        text.draw(at: point)
    }

    private nonisolated static func drawStamp(_ text: String, at point: CGPoint, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: stampFont(34), .foregroundColor: color, .kern: 3])
    }

    private nonisolated static func drawCaption(_ text: String, at point: CGPoint) {
        (text as NSString).draw(at: point,
                                withAttributes: [.font: UIFont.systemFont(ofSize: 42, weight: .bold), .foregroundColor: secondary])
    }

    private nonisolated static func drawCentered(_ text: String, y: CGFloat, font: UIFont, color: UIColor,
                                                 tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (canvas.width - size.width) / 2, y: y), withAttributes: attributes)
    }

    private nonisolated static func drawPhoto(_ url: URL, in rect: CGRect, cornerRadius: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1).setFill()
        UIRectFill(rect)
        if let image = ImageLoader.load(url: url, maxPixels: 1600) {
            let scale = max(rect.width / image.size.width, rect.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                  width: drawn.width, height: drawn.height))
        }
        context.restoreGState()
    }

    private nonisolated static func drawPhotoTag(_ text: String, in rect: CGRect, highlighted: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: brandFont(64), .foregroundColor: highlighted ? UIColor.black : UIColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: rect.minX + 18, y: rect.maxY - size.height - 34, width: size.width + 36, height: size.height + 12)
        (highlighted ? accent : UIColor.black.withAlphaComponent(0.55)).setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 18, y: pill.minY + 6), withAttributes: attributes)
    }

    /// The brand mark: a bar with one plate per week, the same as in the app.
    private nonisolated static func drawBarbell(plates: Int, center: CGPoint, height: CGFloat) {
        let sizes: [CGFloat] = [1, 1, 0.84, 0.84, 0.7, 0.7, 0.58, 0.58]
        let plateWidth = height * 0.22
        let spacing: CGFloat = height * 0.06
        let count = min(plates, sizes.count)
        let barWidth = height * 2.6
        let left = center.x - barWidth / 2
        accent.withAlphaComponent(0.5).setFill()
        let barHeight = max(height * 0.1, 4)
        UIBezierPath(roundedRect: CGRect(x: left, y: center.y - barHeight / 2, width: barWidth, height: barHeight),
                     cornerRadius: barHeight / 2).fill()
        accent.setFill()
        var x = left + height * 0.16
        for index in 0..<count {
            let plateHeight = height * sizes[index]
            UIBezierPath(roundedRect: CGRect(x: x, y: center.y - plateHeight / 2, width: plateWidth, height: plateHeight),
                         cornerRadius: height * 0.06).fill()
            x += plateWidth + spacing
        }
    }

    // MARK: Encoding

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
        context.draw(cg, in: CGRect(origin: .zero, size: canvas))
        return buffer
    }

    private nonisolated static func append(_ buffer: CVPixelBuffer, frame: Int, input: AVAssetWriterInput,
                                           adaptor: AVAssetWriterInputPixelBufferAdaptor) async throws {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps)) else {
            throw ExportError.failed
        }
    }
}
