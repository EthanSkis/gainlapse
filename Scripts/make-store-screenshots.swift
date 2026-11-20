// Composes the App Store screenshots from real captures of the app.
// One idea per frame: a short headline, one line of support, and the app shown straight-on at full size.
//
// Captures come from a screenshot run of the Debug build (see Marketing/app-store/SCREENSHOTS.md):
//   home.png  recap.png  checkin.png  checkin-start.png  weight.png  share.png   (1206 x 2622 each)
//
// Usage: swift Scripts/make-store-screenshots.swift <captures dir> <output dir>
// Writes 01.png ... 06.png at 1290 x 2796 into <output dir>, and at 1206 x 2622 into <output dir>-6.3in.
// Also writes the three wide creative assets into a `creative` folder beside <output dir>.
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift make-store-screenshots.swift <captures dir> <output dir>")
}
let capturesDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2])

// MARK: Brand

let brandOrange = NSColor(srgbRed: 1.0, green: 0.353, blue: 0.122, alpha: 1)
let ink = NSColor(srgbRed: 0.055, green: 0.047, blue: 0.043, alpha: 1)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func brandFont(_ size: CGFloat) -> NSFont { NSFont.systemFont(ofSize: size, weight: .black, width: .compressed) }
func stampFont(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .bold) }

enum Theme {
    case orange, dark

    var headline: NSColor { self == .orange ? ink : .white }
    var accent: NSColor { self == .orange ? .white : brandOrange }
    var eyebrow: NSColor { self == .orange ? ink.withAlphaComponent(0.72) : brandOrange }
    var body: NSColor { self == .orange ? ink.withAlphaComponent(0.86) : NSColor.white.withAlphaComponent(0.72) }
}

/// A headline line; `accent` lines take the frame's second colour.
struct Line {
    let text: String
    var accent = false
}

enum Subject {
    /// The app, straight-on. `patchTop` covers a capture's status bar area with a clean one from another capture.
    case phone(capture: String, patchTopFrom: String? = nil)
    case privacy
}

struct Frame {
    let theme: Theme
    let eyebrow: String
    let headline: [Line]
    let body: String
    let subject: Subject
}

let frames: [Frame] = [
    Frame(theme: .orange, eyebrow: "WEEKLY PROGRESS PHOTOS",
          headline: [Line(text: "SEE EVERY"), Line(text: "GAIN")],
          body: "One photo a week. A timelapse of every gain.",
          subject: .phone(capture: "home")),
    Frame(theme: .dark, eyebrow: "WEEK 1 AGAINST NOW",
          headline: [Line(text: "DRAG TO"), Line(text: "COMPARE", accent: true)],
          body: "Slide across the same photo and watch the change.",
          subject: .phone(capture: "recap")),
    Frame(theme: .orange, eyebrow: "AI CHECK-IN",
          headline: [Line(text: "HONEST,"), Line(text: "NOT HARSH")],
          body: "Feedback from your very first photo. Never a score.",
          subject: .phone(capture: "checkin-start")),
    Frame(theme: .dark, eyebrow: "WEIGHT AND MEASUREMENTS",
          headline: [Line(text: "THE SCALE,"), Line(text: "SMOOTHED", accent: true)],
          body: "A 7-day trend, right beside your photos.",
          subject: .phone(capture: "weight", patchTopFrom: "checkin")),
    Frame(theme: .orange, eyebrow: "TIMELAPSE AND BEFORE & AFTER",
          headline: [Line(text: "MADE TO"), Line(text: "SHARE")],
          body: "Vertical video for TikTok, Reels and Stories.",
          subject: .phone(capture: "share")),
    Frame(theme: .dark, eyebrow: "PRIVATE BY DESIGN",
          headline: [Line(text: "YOUR PHOTOS."), Line(text: "NOBODY ELSE'S.", accent: true)],
          body: "Nothing leaves your phone unless you share it.",
          subject: .privacy),
]

// MARK: Drawing helpers (top-left origin, in design units of a 1290 x 2796 canvas)

let designSize = CGSize(width: 1290, height: 2796)
let margin: CGFloat = 86

func load(_ name: String) -> CGImage {
    let url = capturesDirectory.appendingPathComponent("\(name).png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing capture: \(url.path)") }
    return image
}

func draw(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: point)
}

func width(of text: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: font, .kern: kern]).size().width
}

func fillBackground(_ theme: Theme, in ctx: CGContext) {
    let full = CGRect(origin: .zero, size: designSize)
    switch theme {
    case .orange:
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1.0, green: 0.43, blue: 0.17, alpha: 1),
            CGColor(srgbRed: 0.96, green: 0.30, blue: 0.08, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: designSize.width, y: designSize.height), options: [])
        // A soft pool of shade low on the page, so the phone sits on something.
        let shade = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.45, green: 0.10, blue: 0, alpha: 0.42), CGColor(srgbRed: 0.45, green: 0.10, blue: 0, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(shade, startCenter: CGPoint(x: designSize.width / 2, y: designSize.height), startRadius: 0,
                               endCenter: CGPoint(x: designSize.width / 2, y: designSize.height), endRadius: 1500, options: [])
    case .dark:
        ctx.setFillColor(ink.cgColor)
        ctx.fill(full)
        let glow = CGGradient(colorsSpace: space, colors: [
            brandOrange.withAlphaComponent(0.34).cgColor, brandOrange.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: designSize.width, y: 0), startRadius: 0,
                               endCenter: CGPoint(x: designSize.width, y: 0), endRadius: 1500, options: [])
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 0, y: designSize.height), startRadius: 0,
                               endCenter: CGPoint(x: 0, y: designSize.height), endRadius: 1100, options: [])
    }
}

/// Eyebrow, headline and body. Returns the y where the text block ends.
func drawText(_ frame: Frame) -> CGFloat {
    let theme = frame.theme
    var y: CGFloat = 150
    draw(frame.eyebrow, font: stampFont(33), color: theme.eyebrow, at: CGPoint(x: margin, y: y), kern: 5)
    y += 78

    // One size for both lines, as large as the longest line allows.
    let maxWidth = designSize.width - margin * 2
    var size: CGFloat = 268
    while size > 120, frame.headline.contains(where: { width(of: $0.text, font: brandFont(size), kern: -2) > maxWidth }) {
        size -= 4
    }
    let font = brandFont(size)
    let lineHeight = size * 0.99   // room for a comma above the next line
    for line in frame.headline {
        // Draw so the cap height, not the font's line box, sets the rhythm.
        let top = y - (font.ascender - font.capHeight) + size * 0.02
        draw(line.text, font: font, color: line.accent ? theme.accent : theme.headline,
             at: CGPoint(x: margin - size * 0.012, y: top), kern: -2)
        y += lineHeight
    }
    y += 30
    // The support line always fits on one line inside the margins.
    var bodySize: CGFloat = 46
    while bodySize > 34, width(of: frame.body, font: NSFont.systemFont(ofSize: bodySize, weight: .semibold)) > maxWidth {
        bodySize -= 1
    }
    draw(frame.body, font: NSFont.systemFont(ofSize: bodySize, weight: .semibold), color: theme.body, at: CGPoint(x: margin, y: y))
    return y + 60
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws an image into a rect given in top-left coordinates.
func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

/// The capture inside a plain, accurate phone body that runs off the bottom of the frame.
func drawPhone(capture: String, patchTopFrom: String?, top: CGFloat, ctx: CGContext,
               centerX: CGFloat = designSize.width / 2, screenWidth: CGFloat = 1000) {
    let image = load(capture)
    let scale = screenWidth / CGFloat(image.width)
    let screen = CGRect(x: centerX - screenWidth / 2, y: top, width: screenWidth, height: CGFloat(image.height) * scale)
    let screenRadius = 186 * scale          // the iPhone's own display corner
    let bezel: CGFloat = 22 * screenWidth / 1000
    let body = screen.insetBy(dx: -bezel, dy: -bezel)

    // Shadow under the phone.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 46), blur: 110, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(roundedPath(body, radius: screenRadius + bezel))
    ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Body with a fine metal edge.
    ctx.addPath(roundedPath(body.insetBy(dx: -3, dy: -3), radius: screenRadius + bezel + 3))
    ctx.setFillColor(CGColor(gray: 0.30, alpha: 1))
    ctx.fillPath()
    ctx.addPath(roundedPath(body, radius: screenRadius + bezel))
    ctx.setFillColor(CGColor(gray: 0.03, alpha: 1))
    ctx.fillPath()

    // Screen.
    ctx.saveGState()
    ctx.addPath(roundedPath(screen, radius: screenRadius))
    ctx.clip()
    drawImage(image, in: screen, ctx: ctx)
    if let patchTopFrom {
        // Replace the area behind the status bar with a clean one, fading into the capture.
        let patch = load(patchTopFrom)
        let rows = 178
        if let strip = patch.cropping(to: CGRect(x: 0, y: 0, width: patch.width, height: rows)) {
            let rect = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: CGFloat(rows) * scale)
            ctx.saveGState()
            let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: [
                CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1),
            ] as CFArray, locations: [0, 0.72, 1])!
            let maskContext = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            maskContext.drawLinearGradient(fade, start: CGPoint(x: 0, y: rect.height), end: .zero, options: [])
            if let mask = maskContext.makeImage() {
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.clip(to: CGRect(origin: .zero, size: rect.size), mask: mask)
                ctx.interpolationQuality = .high
                ctx.draw(strip, in: CGRect(origin: .zero, size: rect.size))
            }
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()
}

func symbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
}

/// The brand mark: a bar with one plate per week.
func drawBarbell(center: CGPoint, height: CGFloat, color: NSColor, ctx: CGContext) {
    let sizes: [CGFloat] = [1, 1, 0.84, 0.84, 0.7, 0.7, 0.58, 0.58]
    let plateWidth = height * 0.2
    let gap = height * 0.07
    let barWidth = height * 2.9
    let left = center.x - barWidth / 2
    ctx.setFillColor(color.withAlphaComponent(0.5).cgColor)
    let barHeight = height * 0.1
    ctx.addPath(roundedPath(CGRect(x: left, y: center.y - barHeight / 2, width: barWidth, height: barHeight), radius: barHeight / 2))
    ctx.fillPath()
    ctx.setFillColor(color.cgColor)
    var x = left + height * 0.18
    for size in sizes {
        let plateHeight = height * size
        ctx.addPath(roundedPath(CGRect(x: x, y: center.y - plateHeight / 2, width: plateWidth, height: plateHeight), radius: height * 0.05))
        ctx.fillPath()
        x += plateWidth + gap
    }
}

func drawPrivacy(top: CGFloat, ctx: CGContext) {
    let rows: [(symbol: String, title: String, detail: String)] = [
        ("eye.slash.fill", "No feed. Nothing public.", "No followers, no likes, no profile."),
        ("iphone", "Saved on your iPhone", "Not in your camera roll, not on our server."),
        ("person.crop.circle.badge.xmark", "No account. No ads.", "No sign-up and no tracking."),
        ("heart.fill", "Health data stays put", "Apple Health weight never leaves it."),
        ("sparkles", "AI check-ins are your call", "The app asks first. Photos aren't stored."),
    ]
    let rowHeight: CGFloat = 286
    let cardHeight = CGFloat(rows.count) * rowHeight + 40
    let wordmarkTop = designSize.height - 330
    // Centred in the space between the text and the wordmark.
    let cardTop = max(top, top + (wordmarkTop - top - cardHeight) / 2 - 20)
    let card = CGRect(x: margin, y: cardTop, width: designSize.width - margin * 2, height: cardHeight)
    ctx.addPath(roundedPath(card, radius: 64))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
    ctx.fillPath()
    ctx.addPath(roundedPath(card.insetBy(dx: 1, dy: 1), radius: 63))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(2)
    ctx.strokePath()

    var y = card.minY + 20
    for (index, row) in rows.enumerated() {
        let badge = CGRect(x: card.minX + 56, y: y + (rowHeight - 136) / 2, width: 136, height: 136)
        ctx.addPath(roundedPath(badge, radius: 36))
        ctx.setFillColor(brandOrange.withAlphaComponent(0.16).cgColor)
        ctx.fillPath()
        if let icon = symbol(row.symbol, pointSize: 56, color: brandOrange) {
            let size = icon.size
            icon.draw(in: CGRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2, width: size.width, height: size.height))
        }
        draw(row.title, font: NSFont.systemFont(ofSize: 60, weight: .bold), color: .white,
             at: CGPoint(x: badge.maxX + 44, y: y + rowHeight / 2 - 76))
        draw(row.detail, font: NSFont.systemFont(ofSize: 40, weight: .medium), color: NSColor.white.withAlphaComponent(0.62),
             at: CGPoint(x: badge.maxX + 44, y: y + rowHeight / 2 + 8))
        y += rowHeight
        if index < rows.count - 1 {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.09).cgColor)
            ctx.fill(CGRect(x: card.minX + 56, y: y - 1, width: card.width - 112, height: 2))
        }
    }

    // Wordmark at the foot of the last frame.
    let wordmark = "GAINLAPSE"
    let font = brandFont(150)
    let markHeight: CGFloat = 96
    let total = markHeight * 2.9 + 44 + width(of: wordmark, font: font)
    let startX = (designSize.width - total) / 2
    let baseline = designSize.height - 290
    drawBarbell(center: CGPoint(x: startX + markHeight * 1.45, y: baseline + 78), height: markHeight, color: brandOrange, ctx: ctx)
    draw(wordmark, font: font, color: .white, at: CGPoint(x: startX + markHeight * 2.9 + 44, y: baseline - 12))
}

// MARK: Render

func render(_ frame: Frame, pixelSize: CGSize) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Top-left origin, scaled so the same design fits both sizes. The 6.3" canvas is a hair taller in
    // proportion, so the design stretches to fill it rather than leaving a strip.
    ctx.translateBy(x: 0, y: pixelSize.height)
    ctx.scaleBy(x: pixelSize.width / designSize.width, y: -pixelSize.height / designSize.height)
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    fillBackground(frame.theme, in: ctx)
    let textBottom = drawText(frame)
    switch frame.subject {
    case .phone(let capture, let patchTopFrom):
        drawPhone(capture: capture, patchTopFrom: patchTopFrom, top: max(textBottom + 96, 960), ctx: ctx)
    case .privacy:
        drawPrivacy(top: textBottom + 110, ctx: ctx)
    }

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Can't write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// MARK: Wide creative assets (product page header and search results)

/// Headline centred over three phones. Everything important stays in the middle, because the App Store
/// crops the sides of these images differently on each device.
func renderWide(pixelSize: CGSize) -> CGImage {
    let width = pixelSize.width, height = pixelSize.height
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 1.0, green: 0.43, blue: 0.17, alpha: 1),
        CGColor(srgbRed: 0.96, green: 0.30, blue: 0.08, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    let shade = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.45, green: 0.10, blue: 0, alpha: 0.45), CGColor(srgbRed: 0.45, green: 0.10, blue: 0, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(shade, startCenter: CGPoint(x: width / 2, y: height), startRadius: 0,
                           endCenter: CGPoint(x: width / 2, y: height), endRadius: height * 1.1, options: [])

    let eyebrow = "WEEKLY GYM PROGRESS PHOTOS"
    let eyebrowFont = stampFont(height * 0.026)
    let eyebrowKern = height * 0.006
    draw(eyebrow, font: eyebrowFont, color: ink.withAlphaComponent(0.75),
         at: CGPoint(x: (width - width_(eyebrow, eyebrowFont, eyebrowKern)) / 2, y: height * 0.07), kern: eyebrowKern)

    let headline = "SEE EVERY GAIN"
    var size = height * 0.2
    while width_(headline, brandFont(size), -2) > min(width * 0.8, height * 1.9) { size -= 4 }
    let font = brandFont(size)
    let capTop = height * 0.125
    draw(headline, font: font, color: ink,
         at: CGPoint(x: (width - width_(headline, font, -2)) / 2, y: capTop - (font.ascender - font.capHeight)), kern: -2)

    // Side phones first, so the middle one overlaps their shadows.
    let middle = height * 0.36, side = height * 0.31
    let offset = middle / 2 + side / 2 + height * 0.07
    drawPhone(capture: "recap", patchTopFrom: nil, top: height * 0.47, ctx: ctx, centerX: width / 2 - offset, screenWidth: side)
    drawPhone(capture: "checkin-start", patchTopFrom: nil, top: height * 0.47, ctx: ctx, centerX: width / 2 + offset, screenWidth: side)
    drawPhone(capture: "home", patchTopFrom: nil, top: height * 0.385, ctx: ctx, centerX: width / 2, screenWidth: middle)

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func width_(_ text: String, _ font: NSFont, _ kern: CGFloat) -> CGFloat { width(of: text, font: font, kern: kern) }

let creativeDirectory = outputDirectory.deletingLastPathComponent().appendingPathComponent("creative")
for (name, size) in [("header-21x9.png", CGSize(width: 3840, height: 1646)),
                     ("search-results-3x2.png", CGSize(width: 3840, height: 2560)),
                     ("universal-16x9.png", CGSize(width: 5244, height: 2950))] {
    write(renderWide(pixelSize: size), to: creativeDirectory.appendingPathComponent(name))
    print("Wrote creative/\(name)")
}

let smallDirectory = URL(fileURLWithPath: outputDirectory.path + "-6.3in")
for (index, frame) in frames.enumerated() {
    let name = String(format: "%02d.png", index + 1)
    write(render(frame, pixelSize: CGSize(width: 1290, height: 2796)), to: outputDirectory.appendingPathComponent(name))
    write(render(frame, pixelSize: CGSize(width: 1206, height: 2622)), to: smallDirectory.appendingPathComponent(name))
    print("Wrote \(name)")
}
