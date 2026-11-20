import SwiftUI

/// Two photos stacked on each other. Dragging the handle reveals the earlier one over the later one.
struct CompareSlider: View {
    let before: ProgressPhoto
    let after: ProgressPhoto
    let beforeLabel: String
    let afterLabel: String

    @State private var position: CGFloat = 0.5
    @State private var edgeHits = 0
    @State private var isSideways: Bool?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = width * position
            ZStack(alignment: .leading) {
                PhotoFrame(photo: after, maxPixels: 1200, fitsAspect: false)
                PhotoFrame(photo: before, maxPixels: 1200, fitsAspect: false)
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .offset(x: x - 1.5)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .offset(x: x - 22)
            }
            .frame(width: width, height: geometry.size.height)
            .overlay(alignment: .bottomLeading) { tag(beforeLabel).opacity(position > 0.18 ? 1 : 0) }
            .overlay(alignment: .bottomTrailing) { tag(afterLabel).opacity(position < 0.82 ? 1 : 0) }
            .contentShape(Rectangle())
            // Runs alongside the page's scrolling and only follows sideways drags, so scrolling past still works.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if isSideways == nil {
                            isSideways = abs(value.translation.width) > abs(value.translation.height)
                        }
                        guard isSideways == true else { return }
                        let next = min(max(value.location.x / width, 0), 1)
                        if (next == 0 || next == 1) && next != position { edgeHits += 1 }
                        position = next
                    }
                    .onEnded { _ in isSideways = nil }
            )
            .onTapGesture { location in
                withAnimation(.smooth(duration: 0.25)) { position = min(max(location.x / width, 0), 1) }
            }
        }
        .aspectRatio(Theme.photoAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .animation(.smooth(duration: 0.15), value: position > 0.18)
        .animation(.smooth(duration: 0.15), value: position < 0.82)
        .sensoryFeedback(.impact(weight: .light), trigger: edgeHits)
        .accessibilityElement()
        .accessibilityLabel("Comparison of \(beforeLabel) and \(afterLabel)")
        .accessibilityValue("\(Int(position * 100)) percent \(beforeLabel)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: position = min(position + 0.1, 1)
            case .decrement: position = max(position - 0.1, 0)
            @unknown default: break
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
            .padding(10)
    }
}
