import SwiftUI
import WidgetKit

private let accent = Color(red: 1.0, green: 0.353, blue: 0.122)
private let widgetBackground = Color(red: 0.055, green: 0.047, blue: 0.043)
private let secondary = Color.white.opacity(0.68)

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry { ProgressEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        var dates: [Date] = [.now]
        // Refresh the moment the photo becomes due, and each midnight so "in 3 days" counts down.
        if let next = snapshot?.nextPhoto, next > .now { dates.append(next) }
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        dates.append(midnight)
        let entries = dates.sorted().map { ProgressEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

/// One plate per week, like the app's brand mark.
private struct Plates: View {
    let count: Int
    var height: CGFloat = 26
    private let sizes: [CGFloat] = [1, 1, 0.84, 0.84, 0.7, 0.7, 0.58, 0.58]

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(accent.opacity(0.5)).frame(height: max(height * 0.1, 2))
            HStack(spacing: 2) {
                ForEach(0..<min(max(count, 0), sizes.count), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: height * 0.22, height: height * sizes[index])
                }
            }
            .padding(.leading, 4)
        }
        .frame(height: height)
    }
}

struct ProgressWidgetView: View {
    let entry: ProgressEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private var dueNow: Bool {
        guard let snapshot else { return false }
        if snapshot.photoDueNow { return true }
        if let next = snapshot.nextPhoto { return next <= entry.date }
        return false
    }

    private var photoText: String {
        guard let snapshot, snapshot.weeks > 0 else { return "Take your week 1 photo" }
        if dueNow { return "Photo day" }
        guard let next = snapshot.nextPhoto else { return "" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                   to: Calendar.current.startOfDay(for: next)).day ?? 0
        switch days {
        case ...0: return "Photo today"
        case 1: return "Photo tomorrow"
        default: return "Photo in \(days) days"
        }
    }

    private var link: URL { URL(string: dueNow || (snapshot?.weeks ?? 0) == 0 ? "gainlapse://photo" : "gainlapse://log-weight")! }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: lockScreen
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(link)
        .containerBackground(for: .widget) { widgetBackground }
    }

    private var weeksHeadline: some View {
        Text(snapshot.map { $0.weeks == 1 ? "1 WEEK" : "\($0.weeks) WEEKS" } ?? "GAINLAPSE")
            .font(.system(size: 30, weight: .black).width(.compressed))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Plates(count: snapshot?.weeks ?? 0)
            weeksHeadline
            Spacer(minLength: 0)
            Text(photoText)
                .font(.footnote.weight(.bold))
                .foregroundStyle(dueNow ? accent : .white)
            if let streak = snapshot?.streak, streak > 1 {
                Text("\(streak) in a row").font(.caption2).foregroundStyle(secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            VStack(alignment: .leading, spacing: 4) {
                Text("WEIGHT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                if let snapshot, let weight = snapshot.weight {
                    Text(snapshot.weightText(weight))
                        .font(.system(size: 28, weight: .black).width(.compressed))
                        .foregroundStyle(.white)
                    if let change = snapshot.weightChange {
                        Text("\(snapshot.weightText(change, signed: true)) since start")
                            .font(.caption)
                            .foregroundStyle(secondary)
                    }
                } else {
                    Text("Tap to log your weight")
                        .font(.footnote)
                        .foregroundStyle(secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Gainlapse").font(.headline).widgetAccentable()
            Text(photoText).font(.subheadline)
            if let snapshot, snapshot.weeks > 0 {
                Text("\(snapshot.weeks) weeks · \(snapshot.streak) in a row").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GainlapseProgress", provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("Progress")
        .description("Your weeks, your next photo day and your weight.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct GainlapseWidgets: WidgetBundle {
    var body: some Widget {
        ProgressWidget()
    }
}
