import SwiftUI

/// A 12-week sample timelapse for onboarding, made from AI-generated photos of one person. It says so on screen.
struct SampleTimelapse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Frame {
        let week: Int
        let image: String
    }

    private static let frames = [1, 4, 8, 12].map { Frame(week: $0, image: "SampleWeek\($0)") }
    /// Each photo holds, then fades into the next. The last one holds longer before the loop restarts.
    private static let hold = 0.9
    private static let fade = 0.5
    private static let finalHold = 1.6
    private static var loop: Double { Double(frames.count - 1) * (hold + fade) + finalHold }

    var body: some View {
        VStack(spacing: 10) {
            if reduceMotion {
                HStack(spacing: 10) {
                    card(from: 0, to: 0, blend: 0)
                    card(from: Self.frames.count - 1, to: Self.frames.count - 1, blend: 0)
                }
            } else {
                TimelineView(.animation) { timeline in
                    let (from, to, blend) = Self.position(at: timeline.date)
                    card(from: from, to: to, blend: blend)
                }
            }
            Text("AI-generated example. Everyone's results are different.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI-generated example photos of one person from week 1 to week 12. Everyone's results are different.")
    }

    /// Which photo is showing, which comes next, and how far the fade between them has gone.
    private static func position(at date: Date) -> (Int, Int, Double) {
        var time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        for index in 0..<(frames.count - 1) {
            if time < hold { return (index, index, 0) }
            time -= hold
            if time < fade { return (index, index + 1, time / fade) }
            time -= fade
        }
        return (frames.count - 1, frames.count - 1, 0)
    }

    private func card(from: Int, to: Int, blend: Double) -> some View {
        let shown = blend < 0.5 ? Self.frames[from] : Self.frames[to]
        return ZStack(alignment: .topLeading) {
            ZStack {
                photo(Self.frames[from].image)
                if to != from {
                    photo(Self.frames[to].image).opacity(blend)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: reduceMotion ? 220 : 300, alignment: .top)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Stamp(text: "Week \(shown.week)", color: Theme.accent)
                Barbell(plates: shown.week, showsNext: false, height: 26).frame(width: 90)
            }
            .padding(10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    /// Skips the empty wall above the head so the stomach, where most of the change shows, stays in view.
    private func photo(_ name: String) -> some View {
        GeometryReader { geometry in
            let imageHeight = geometry.size.width * 4 / 3
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: imageHeight)
                .offset(y: -imageHeight * 0.09)
        }
        .frame(height: reduceMotion ? 220 : 300)
        .clipped()
    }
}
