import Foundation

/// The few numbers the home screen widget shows, shared through the App Group.
/// No photos are shared with the widget.
struct WidgetSnapshot: Codable, Equatable {
    var weeks: Int
    var streak: Int
    /// When the next weekly photo is due. nil before the first photo.
    var nextPhoto: Date?
    var photoDueNow: Bool
    /// Latest weight in kilograms, and the change since the first entry.
    var weight: Double?
    var weightChange: Double?
    var usesMetric: Bool

    static let appGroup = "group.com.ethangardner.gainlapse"
    private static let key = "widget.snapshot"

    static let placeholder = WidgetSnapshot(weeks: 6, streak: 6, nextPhoto: .now.addingTimeInterval(3 * 86_400),
                                            photoDueNow: false, weight: 80.2, weightChange: 2.1, usesMetric: false)

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    func weightText(_ kilograms: Double, signed: Bool = false) -> String {
        let shown = usesMetric ? kilograms : kilograms * 2.204_62
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let text = signed ? shown.formatted(style.sign(strategy: .always(includingZero: false))) : shown.formatted(style)
        return "\(text) \(usesMetric ? "kg" : "lb")"
    }
}
