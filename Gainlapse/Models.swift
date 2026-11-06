import Foundation

enum Goal: String, Codable, CaseIterable, Identifiable {
    case bulk
    case tone
    case justStarted = "just_started"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bulk: "Bulk up"
        case .tone: "Tone"
        case .justStarted: "Just started"
        }
    }

    var subtitle: String {
        switch self {
        case .bulk: "Put on size and see it build"
        case .tone: "Track glute and toning progress"
        case .justStarted: "Capture your first months at the gym"
        }
    }

    var symbol: String {
        switch self {
        case .bulk: "dumbbell.fill"
        case .tone: "figure.strengthtraining.functional"
        case .justStarted: "sparkles"
        }
    }
}

enum Pose: String, Codable, CaseIterable, Identifiable {
    case front, side, back

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct CheckIn: Codable, Equatable {
    var feedback: String
    var focusTip: String
    var createdAt: Date
    /// True only for simulator test feedback, so it can never pass as real AI output.
    var isSample: Bool = false
}

struct ProgressPhoto: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var pose: Pose
    var filename: String
    var checkIn: CheckIn?

    static func == (lhs: ProgressPhoto, rhs: ProgressPhoto) -> Bool {
        lhs.id == rhs.id && lhs.checkIn == rhs.checkIn
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct UserProfile: Codable {
    var goal: Goal?
    var checkInWeekday: Int = 1 // Calendar weekday: 1 is Sunday
    var checkInHour: Int = 9
    var checkInMinute: Int = 0
    var onboardingStep: Int = 0
    var onboardingDone: Bool = false
    /// nil means the user hasn't been asked yet.
    var aiConsent: Bool?
    var watermark: Bool = true
    /// The pose of a photo that was taken but not yet confirmed.
    var draftPose: Pose?
    /// When the AI last answered, used to cap repeat requests. Optional so older saved data still loads.
    var aiRequestDates: [Date]?
}
