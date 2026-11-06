// Draws the 1024x1024 subscription images: plates on a bar, on orange, in the app icon's style.
// The yearly plan carries a fuller bar than the weekly plan.
// Usage: swift Scripts/make-plan-image.swift weekly|annual <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let plates: [(width: CGFloat, height: CGFloat)]
switch CommandLine.arguments[1] {
case "weekly": plates = [(84, 620), (72, 480)]
case "annual": plates = [(84, 620), (84, 620), (84, 620), (72, 480), (72, 480), (60, 340), (60, 340)]
default: fatalError("Plan must be weekly or annual")
}

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

let background = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 1.0, green: 0.45, blue: 0.16, alpha: 1),
    CGColor(srgbRed: 0.93, green: 0.27, blue: 0.06, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.06, blue: 0.055, alpha: 1))

// The bar runs off the right edge, like the app icon.
ctx.addPath(CGPath(roundedRect: CGRect(x: 120, y: 482, width: 904, height: 60), cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.fillPath()

var x: CGFloat = 170
for plate in plates {
    let rect = CGRect(x: x, y: 512 - plate.height / 2, width: plate.width, height: plate.height)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    x += plate.width + 20
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[2])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write image") }
