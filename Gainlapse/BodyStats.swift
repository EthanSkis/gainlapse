import Foundation

/// Something the user can log between photo days. Weight is stored in kilograms, the rest in centimetres.
enum BodyMetric: String, Codable, CaseIterable, Identifiable {
    case weight, waist, chest, arms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Weight"
        case .waist: "Waist"
        case .chest: "Chest"
        case .arms: "Arms"
        }
    }

    var symbol: String {
        switch self {
        case .weight: "scalemass.fill"
        case .waist: "figure.core.training"
        case .chest: "figure.arms.open"
        case .arms: "dumbbell.fill"
        }
    }

    var isLength: Bool { self != .weight }

    func unit(metric: Bool) -> String {
        isLength ? (metric ? "cm" : "in") : (metric ? "kg" : "lb")
    }

    /// From stored kilograms or centimetres to what the user reads.
    func display(_ stored: Double, metric: Bool) -> Double {
        if metric { return stored }
        return isLength ? stored / 2.54 : stored * 2.204_62
    }

    /// From what the user typed back to stored kilograms or centimetres.
    func stored(_ shown: Double, metric: Bool) -> Double {
        if metric { return shown }
        return isLength ? shown * 2.54 : shown / 2.204_62
    }

    /// A sensible range, so a typo like 1800 isn't saved as a weight.
    func isPlausible(_ shown: Double, metric: Bool) -> Bool {
        let value = stored(shown, metric: metric)
        return isLength ? (10...300).contains(value) : (25...400).contains(value)
    }
}

struct BodyEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var metric: BodyMetric
    var value: Double
    /// Set when the entry came from Apple Health, so the same sample is never imported twice.
    var healthID: UUID?
}

extension BodyMetric {
    /// "182.4 lb", "-1.6 in".
    func format(_ stored: Double, metric: Bool, signed: Bool = false) -> String {
        let shown = display(stored, metric: metric)
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(isLength ? 1 : 1))
        let text = signed ? shown.formatted(style.sign(strategy: .always(includingZero: false))) : shown.formatted(style)
        return "\(text) \(unit(metric: metric))"
    }
}
