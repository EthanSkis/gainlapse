import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.047, blue: 0.043)
    static let surface = Color(red: 0.11, green: 0.10, blue: 0.095)
    static let surfaceRaised = Color(red: 0.16, green: 0.15, blue: 0.14)
    static let accent = Color(red: 1.0, green: 0.353, blue: 0.122)
    static let secondaryText = Color.white.opacity(0.68)
    static let photoAspect: CGFloat = 3.0 / 4.0
}

extension Font {
    /// Poster headlines, using the system font's compressed width.
    static func brand(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.compressed)
    }

    /// Small date and week stamps.
    static func stamp(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

struct Stamp: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(.stamp())
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// A dark background with a soft glow, which gives Liquid Glass something to refract.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Theme.accent.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

/// The brand mark and streak: one plate for every week with a photo.
/// Plates are never taken away, so a missed week doesn't punish anyone.
struct Barbell: View {
    let plates: Int
    var showsNext = true
    var height: CGFloat = 48
    var color: Color = Theme.accent

    private let maxShown = 8
    private let sizes: [CGFloat] = [1, 1, 0.84, 0.84, 0.7, 0.7, 0.58, 0.58]

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.5)).frame(height: max(height * 0.1, 4))
            HStack(spacing: 3) {
                ForEach(0..<min(plates, maxShown), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: height * 0.22, height: height * sizes[index])
                        .transition(.asymmetric(insertion: .offset(x: 70).combined(with: .opacity), removal: .opacity))
                }
                if showsNext && plates < maxShown {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .background(Theme.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
                        .frame(width: height * 0.22, height: height * sizes[min(plates, maxShown - 1)])
                }
            }
            .padding(.leading, 8)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(plates) \(plates == 1 ? "week" : "weeks") of photos")
    }
}

/// The one main action on a screen, in orange-tinted Liquid Glass.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Capsule())
            .glassEffect(isEnabled ? .regular.tint(Theme.accent).interactive() : .regular, in: Capsule())
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A round Liquid Glass icon button for camera and overlay controls.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
        }
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(label)
    }
}

/// Four corner marks that frame a photo.
struct FrameBrackets: Shape {
    var length: CGFloat = 20
    var inset: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let box = rect.insetBy(dx: inset, dy: inset)
        path.move(to: CGPoint(x: box.minX, y: box.minY + length))
        path.addLine(to: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX + length, y: box.minY))
        path.move(to: CGPoint(x: box.maxX - length, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + length))
        path.move(to: CGPoint(x: box.minX, y: box.maxY - length))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.minX + length, y: box.maxY))
        path.move(to: CGPoint(x: box.maxX - length, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - length))
        return path
    }
}

/// A photo that shows a spinner while it loads, never a blank box.
struct PhotoFrame: View {
    let photo: ProgressPhoto
    var maxPixels: Int = 1200
    var fitsAspect = true
    @Environment(ProgressStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        Group {
            if fitsAspect {
                content.aspectRatio(Theme.photoAspect, contentMode: .fit)
            } else {
                content
            }
        }
        .clipped()
        .task(id: photo.id) { image = await store.image(for: photo, maxPixels: maxPixels) }
    }

    private var content: some View {
        Rectangle()
            .fill(Theme.surfaceRaised)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().tint(.white)
                }
            }
    }
}
