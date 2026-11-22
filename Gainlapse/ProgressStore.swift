import CoreImage
import Foundation
import ImageIO
import Observation
import UIKit
import WidgetKit

/// Everything the app remembers. Stored only on this device, using iOS file protection.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    private(set) var photos: [ProgressPhoto] = []
    private(set) var bodyEntries: [BodyEntry] = []
    var profile = UserProfile() { didSet { save() } }
    /// Set when a reminder notification or the widget is tapped, so it opens the camera.
    var cameraRequested = false
    /// Set by the widget's link when no photo is due, so it opens the weigh-in sheet.
    var weightLogRequested = false
    /// Set when a recap notification is tapped.
    var recapRequested = false
    #if DEBUG
    /// A screen to jump straight to, from a gainlapse://shot/<name> link in a screenshot run.
    var debugShot: String?
    #endif

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private var isLoading = false

    private var rootURL: URL {
        URL.applicationSupportDirectory.appending(path: "Gainlapse", directoryHint: .isDirectory)
    }
    private var photosURL: URL { rootURL.appending(path: "Photos", directoryHint: .isDirectory) }
    private var stateURL: URL { rootURL.appending(path: "state.json") }

    private struct SavedState: Codable {
        var profile: UserProfile
        var photos: [ProgressPhoto]
        /// Optional so data saved before body logging still loads.
        var bodyEntries: [BodyEntry]?
    }

    init() {
        clearExports()
        load()
        if let weeks = DebugFlags.demoWeeks, photos.isEmpty { seedDemo(weeks: weeks) }
        #if DEBUG
        // Test builds launched with -resetAILimit get their AI tries back, keeping every photo.
        if ProcessInfo.processInfo.arguments.contains("-resetAILimit") {
            profile.aiRequestDates = nil
            save() // didSet doesn't run inside init
        }
        #endif
        updateWidget()
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        profile = state.profile
        photos = state.photos.sorted { $0.date < $1.date }
        bodyEntries = (state.bodyEntries ?? []).sorted { $0.date < $1.date }
    }

    private func save() {
        guard !isLoading else { return }
        let state = SavedState(profile: profile, photos: photos, bodyEntries: bodyEntries)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: [.atomic, .completeFileProtection])
        updateWidget()
    }

    // MARK: Widget

    /// Shares a few numbers (never photos) with the home screen widget, and refreshes it only when they change.
    private func updateWidget() {
        let snapshot = WidgetSnapshot(
            weeks: photoWeekCount,
            streak: streak,
            nextPhoto: photos.isEmpty ? nil : nextCheckIn(),
            photoDueNow: !photos.isEmpty && !hasPhotoThisWeek,
            weight: latestEntry(for: .weight)?.value,
            weightChange: trendChange(for: .weight),
            usesMetric: usesMetric)
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Recaps

    nonisolated static let recapWeeks = [4, 8, 12, 26, 52]

    /// The newest milestone reached that hasn't been opened or dismissed.
    var pendingRecap: Int? {
        let seen = Set(profile.seenRecaps ?? [])
        return Self.recapWeeks.filter { $0 <= photoWeekCount && !seen.contains($0) }.max()
    }

    func markRecapSeen(_ weeks: Int) {
        // Opening a later recap covers the earlier ones too.
        let covered = Self.recapWeeks.filter { $0 <= weeks }
        profile.seenRecaps = Array(Set((profile.seenRecaps ?? []) + covered)).sorted()
        Reminders.cancelRecap()
    }

    nonisolated static func recapTitle(_ weeks: Int) -> String {
        switch weeks {
        case 4: "Your first month"
        case 8: "Two months in"
        case 12: "Three months in"
        case 26: "Six months in"
        case 52: "One year"
        default: "\(weeks) weeks in"
        }
    }

    // MARK: Photos

    /// Saves a photo for this week. Retaking a pose replaces that pose's photo for the week.
    @discardableResult
    func addPhoto(_ image: UIImage, pose: Pose, date: Date = .now) throws -> ProgressPhoto {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let start = periodStart(containing: date)
        var keptCheckIn: CheckIn?
        if let existing = photos.first(where: { $0.pose == pose && periodStart(containing: $0.date) == start }) {
            // A retake keeps the week's check-in, so replacing a photo can't buy another AI response.
            keptCheckIn = existing.checkIn
            removeFile(for: existing)
            photos.removeAll { $0.id == existing.id }
        }
        let photo = ProgressPhoto(id: UUID(), date: date, pose: pose, filename: "\(UUID().uuidString).jpg",
                                  checkIn: keptCheckIn)
        try data.write(to: photosURL.appending(path: photo.filename), options: [.atomic, .completeFileProtection])
        photos.append(photo)
        photos.sort { $0.date < $1.date }
        save()
        return photo
    }

    func setCheckIn(_ checkIn: CheckIn, for photo: ProgressPhoto) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        photos[index].checkIn = checkIn
        save()
    }

    /// Removes leftover export files, which contain the user's photos.
    private func clearExports() {
        let fileManager = FileManager.default
        let directory = URL.temporaryDirectory
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("Gainlapse-") {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: Body stats

    var usesMetric: Bool { profile.usesMetric ?? (Locale.current.measurementSystem == .metric) }

    func entries(for metric: BodyMetric) -> [BodyEntry] { bodyEntries.filter { $0.metric == metric } }

    func latestEntry(for metric: BodyMetric) -> BodyEntry? { bodyEntries.last { $0.metric == metric } }

    /// Saves today's value. Logging the same thing twice in a day replaces the first one.
    func logBody(_ metric: BodyMetric, value: Double, date: Date = .now) {
        bodyEntries.removeAll { $0.metric == metric && calendar.isDate($0.date, inSameDayAs: date) }
        bodyEntries.append(BodyEntry(id: UUID(), date: date, metric: metric, value: value))
        bodyEntries.sort { $0.date < $1.date }
        save()
    }

    func deleteBodyEntry(_ entry: BodyEntry) {
        if let healthID = entry.healthID {
            profile.ignoredHealthIDs = (profile.ignoredHealthIDs ?? []) + [healthID]
        }
        bodyEntries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: Apple Health

    /// Asks for read access to weight, then pulls in the last few months.
    func connectHealth() async {
        guard await HealthSync.requestAccess() else { return }
        profile.healthSync = true
        await syncHealth()
    }

    /// Adds Health weigh-ins Gainlapse hasn't seen. One per day: a weight logged here that day wins.
    func syncHealth() async {
        guard profile.healthSync == true else { return }
        let lastImport = bodyEntries.last { $0.healthID != nil }?.date
        let start = lastImport.map { $0.addingTimeInterval(-2 * 86_400) }
            ?? calendar.date(byAdding: .day, value: -120, to: .now) ?? .now
        let samples = await HealthSync.weights(since: start)
        let known = Set(bodyEntries.compactMap(\.healthID) + (profile.ignoredHealthIDs ?? []))
        var added = false
        // The latest sample each day is the one kept.
        for sample in samples.reversed() where !known.contains(sample.id) {
            let sameDay = bodyEntries.contains {
                $0.metric == .weight && calendar.isDate($0.date, inSameDayAs: sample.date)
            }
            guard !sameDay, BodyMetric.weight.isPlausible(sample.kilograms, metric: true) else { continue }
            bodyEntries.append(BodyEntry(id: UUID(), date: sample.date, metric: .weight,
                                         value: sample.kilograms, healthID: sample.id))
            added = true
        }
        if added {
            bodyEntries.sort { $0.date < $1.date }
            save()
        }
    }

    func updateBodyEntry(_ entry: BodyEntry, value: Double) {
        guard let index = bodyEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        bodyEntries[index].value = value
        save()
    }

    /// Each entry's 7-day average, which smooths out day-to-day water swings on the scale.
    func trend(for metric: BodyMetric) -> [(date: Date, value: Double)] {
        let all = entries(for: metric)
        return all.map { entry in
            let start = entry.date.addingTimeInterval(-7 * 86_400)
            let window = all.filter { $0.date > start && $0.date <= entry.date }
            return (entry.date, window.map(\.value).reduce(0, +) / Double(max(window.count, 1)))
        }
    }

    /// Change from the first to the latest smoothed value, for weight. Measurements use the raw values.
    func trendChange(for metric: BodyMetric) -> Double? {
        guard metric == .weight else { return totalChange(for: metric) }
        let points = trend(for: metric)
        guard let first = entries(for: metric).first, let last = points.last, points.count > 1 else { return nil }
        return last.value - first.value
    }

    var hasLoggedWeightToday: Bool {
        bodyEntries.contains { $0.metric == .weight && calendar.isDateInToday($0.date) }
    }

    /// Change from the first entry to the latest, in stored units.
    func totalChange(for metric: BodyMetric) -> Double? {
        let all = entries(for: metric)
        guard let first = all.first, let last = all.last, all.count > 1 else { return nil }
        return last.value - first.value
    }

    /// Change between the values nearest two dates, used to put a number beside a photo comparison.
    /// `typedOnly` leaves out weights read from Apple Health, for anything that leaves the phone.
    func change(for metric: BodyMetric, from start: Date, to end: Date, typedOnly: Bool = false) -> Double? {
        let all = entries(for: metric).filter { !typedOnly || $0.healthID == nil }
        guard all.count > 1 else { return nil }
        func nearest(_ date: Date) -> BodyEntry? {
            all.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        guard let first = nearest(start), let last = nearest(end), first.id != last.id,
              abs(first.date.timeIntervalSince(start)) < 4 * 86_400,
              abs(last.date.timeIntervalSince(end)) < 4 * 86_400 else { return nil }
        return last.value - first.value
    }

    /// Days in a row ending today or yesterday with a weight logged.
    var weightLogStreak: Int {
        let days = Set(entries(for: .weight).map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: .now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    // MARK: Draft photo

    private var draftURL: URL { rootURL.appending(path: "draft.jpg") }

    /// Keeps a just-taken photo so closing the camera or the app doesn't lose it.
    func saveDraft(_ image: UIImage, pose: Pose) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        try? data.write(to: draftURL, options: [.atomic, .completeFileProtection])
        profile.draftPose = pose
    }

    func loadDraft() -> (image: UIImage, pose: Pose)? {
        guard let pose = profile.draftPose,
              let data = try? Data(contentsOf: draftURL),
              let image = UIImage(data: data) else { return nil }
        return (image, pose)
    }

    func clearDraft() {
        try? FileManager.default.removeItem(at: draftURL)
        profile.draftPose = nil
    }

    /// How many separate weeks have a photo. This never goes down when a week is missed.
    var photoWeekCount: Int { Set(photos.map { periodStart(containing: $0.date) }).count }

    func deleteAllPhotos() {
        clearDraft()
        clearExports()
        try? FileManager.default.removeItem(at: photosURL)
        try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        cache.removeAllObjects()
        photos = []
        save()
    }

    private func removeFile(for photo: ProgressPhoto) {
        try? FileManager.default.removeItem(at: photosURL.appending(path: photo.filename))
        cache.removeObject(forKey: photo.filename as NSString)
    }

    func fileURL(for photo: ProgressPhoto) -> URL { photosURL.appending(path: photo.filename) }

    /// Loads a photo scaled down to `maxPixels` on its longest side.
    func image(for photo: ProgressPhoto, maxPixels: Int = 1200) async -> UIImage? {
        let key = "\(photo.filename)-\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = fileURL(for: photo)
        let image = await Task.detached(priority: .userInitiated) {
            ImageLoader.load(url: url, maxPixels: maxPixels)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    // MARK: Weekly schedule

    private var checkInComponents: DateComponents {
        DateComponents(hour: profile.checkInHour, minute: profile.checkInMinute, weekday: profile.checkInWeekday)
    }

    private func rawPeriodStart(containing date: Date) -> Date {
        calendar.nextDate(after: date.addingTimeInterval(1), matching: checkInComponents,
                          matchingPolicy: .nextTime, direction: .backward) ?? date
    }

    private func rawNextCheckIn(after date: Date) -> Date {
        calendar.nextDate(after: date, matching: checkInComponents, matchingPolicy: .nextTime) ?? date
    }

    /// The first two weeks follow the first photo instead of the chosen day. The second photo is due on day 6,
    /// so the first comparison lands inside a 7-day trial. The chosen day takes over from the third photo,
    /// at least 5 days after the second, so comparisons never use two nearly identical photos.
    private struct OpeningWeeks {
        let firstStart: Date
        let secondStart: Date
        let secondReminder: Date
        let thirdStart: Date
    }

    private var openingWeeks: OpeningWeeks? {
        guard let first = photos.first else { return nil }
        let firstStart = calendar.startOfDay(for: first.date)
        guard let secondStart = calendar.date(byAdding: .day, value: 6, to: firstStart),
              let secondReminder = calendar.date(bySettingHour: profile.checkInHour, minute: profile.checkInMinute,
                                                 second: 0, of: secondStart),
              let earliestThird = calendar.date(byAdding: .day, value: 5, to: secondStart) else { return nil }
        return OpeningWeeks(firstStart: firstStart, secondStart: secondStart, secondReminder: secondReminder,
                            thirdStart: rawNextCheckIn(after: earliestThird.addingTimeInterval(-1)))
    }

    /// The moment the week containing `date` began. Each week runs from one to the next.
    func periodStart(containing date: Date) -> Date {
        guard let weeks = openingWeeks, date >= weeks.firstStart, date < weeks.thirdStart else {
            return rawPeriodStart(containing: date)
        }
        return date < weeks.secondStart ? weeks.firstStart : weeks.secondStart
    }

    func nextCheckIn(after date: Date = .now) -> Date {
        guard let weeks = openingWeeks else { return rawNextCheckIn(after: date) }
        if date < weeks.secondReminder { return weeks.secondReminder }
        if date < weeks.thirdStart { return weeks.thirdStart }
        return rawNextCheckIn(after: date)
    }

    /// The next few photo days, for scheduling reminders.
    func upcomingCheckIns(count: Int = 8) -> [Date] {
        var dates: [Date] = []
        var cursor = Date.now
        for _ in 0..<count {
            cursor = nextCheckIn(after: cursor)
            dates.append(cursor)
        }
        return dates
    }

    var daysUntilNextCheckIn: Int {
        let today = calendar.startOfDay(for: .now)
        let next = calendar.startOfDay(for: nextCheckIn())
        return calendar.dateComponents([.day], from: today, to: next).day ?? 0
    }

    var photosThisWeek: [ProgressPhoto] {
        let start = periodStart(containing: .now)
        return photos.filter { periodStart(containing: $0.date) == start }
    }

    var hasPhotoThisWeek: Bool { !photosThisWeek.isEmpty }

    var missingPosesThisWeek: [Pose] {
        let taken = Set(photosThisWeek.map(\.pose))
        return Pose.allCases.filter { !taken.contains($0) }
    }

    /// Front always comes first; side and back are added by choice.
    var trackedPoses: [Pose] {
        let chosen = Set(profile.trackedPoses ?? [])
        return Pose.allCases.filter { $0 == .front || chosen.contains($0) }
    }

    func setTracked(_ pose: Pose, _ isTracked: Bool) {
        guard pose != .front else { return }
        var chosen = Set(profile.trackedPoses ?? [.front])
        if isTracked { chosen.insert(pose) } else { chosen.remove(pose) }
        profile.trackedPoses = Pose.allCases.filter { chosen.contains($0) }
    }

    /// The chosen angles still to take this week, in order.
    var missingTrackedPosesThisWeek: [Pose] {
        let taken = Set(photosThisWeek.map(\.pose))
        return trackedPoses.filter { !taken.contains($0) }
    }

    var latestPhoto: ProgressPhoto? { photos.last }

    /// Consecutive weeks with a photo. This week counts once taken, and doesn't break the streak before then.
    var streak: Int {
        let starts = Set(photos.map { periodStart(containing: $0.date) })
        var cursor = periodStart(containing: .now)
        if !starts.contains(cursor) {
            cursor = periodStart(containing: cursor.addingTimeInterval(-1))
        }
        var count = 0
        while starts.contains(cursor) {
            count += 1
            cursor = periodStart(containing: cursor.addingTimeInterval(-1))
        }
        return count
    }

    /// Week 1 is the week of the first photo. Missed weeks still count, so the number stays true to time.
    func weekNumber(for photo: ProgressPhoto) -> Int {
        guard let weeks = openingWeeks else { return 1 }
        let start = periodStart(containing: photo.date)
        if start == weeks.firstStart { return 1 }
        if start == weeks.secondStart { return 2 }
        let days = calendar.dateComponents([.day], from: weeks.thirdStart, to: start).day ?? 0
        return Int((Double(days) / 7).rounded()) + 3
    }

    /// The most recent earlier photo of the same pose, taken in an earlier week.
    func comparison(for photo: ProgressPhoto) -> ProgressPhoto? {
        let start = periodStart(containing: photo.date)
        return photos.last { $0.pose == photo.pose && $0.id != photo.id && $0.date < start }
    }

    /// The latest photo for the ghost overlay in the camera.
    func ghostPhoto(for pose: Pose) -> ProgressPhoto? { photos.last { $0.pose == pose } }

    /// A photo gets a check-in if there's an earlier one to compare, or if it's the very first photo.
    func canCheckIn(_ photo: ProgressPhoto) -> Bool {
        guard weekCheckIn(for: photo) == nil else { return false }
        return comparison(for: photo) != nil || photo.id == photos.first?.id
    }

    /// The check-in already saved for the week this photo belongs to, on any pose.
    func weekCheckIn(for photo: ProgressPhoto) -> CheckIn? {
        let start = periodStart(containing: photo.date)
        return photos.last { $0.checkIn != nil && periodStart(containing: $0.date) == start }?.checkIn
    }

    private var recentAIRequests: [Date] {
        let cutoff = Date.now.addingTimeInterval(-5 * 24 * 60 * 60)
        return (profile.aiRequestDates ?? []).filter { $0 > cutoff }
    }

    /// Caps AI answers, including unusable-photo and declined replies. Connection failures don't count.
    var canRequestAI: Bool { Subscriptions.isTestBuild || recentAIRequests.count < 3 }

    func recordAIRequest() {
        profile.aiRequestDates = recentAIRequests + [.now]
    }

    /// This week's photo that can have a check-in but doesn't yet.
    var pendingCheckInPhoto: ProgressPhoto? {
        photosThisWeek.last { $0.checkIn == nil && canCheckIn($0) }
    }

    var latestCheckInPhoto: ProgressPhoto? { photosThisWeek.last { $0.checkIn != nil } }

    func photos(for pose: Pose) -> [ProgressPhoto] { photos.filter { $0.pose == pose } }

    var posesWithPhotos: [Pose] {
        Pose.allCases.filter { pose in photos.contains { $0.pose == pose } }
    }

    // MARK: Test data

    #if DEBUG
    /// Puts a test build back to a first launch.
    func startOver() {
        deleteAllPhotos()
        bodyEntries = []
        profile = UserProfile()
    }

    /// Lets a test build reach the next photo today, using real photos.
    func skipToNextPhotoWeek() {
        profile.aiRequestDates = nil
        for index in photos.indices {
            photos[index].date = calendar.date(byAdding: .day, value: -7, to: photos[index].date) ?? photos[index].date
        }
        save()
    }
    #endif

    private static func numberWord(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return (formatter.string(from: number as NSNumber) ?? "\(number)").capitalized
    }

    private func seedDemo(weeks: Int) {
        #if DEBUG
        profile.goal = .bulk
        profile.onboardingDone = true
        if DebugFlags.storeShots, let lastPhotoDay = calendar.date(byAdding: .day, value: -2, to: .now) {
            // Photo day matches the sample dates, so each sample lands in its own week.
            profile.checkInWeekday = calendar.component(.weekday, from: lastPhotoDay)
            profile.checkInHour = 0
            profile.checkInMinute = 0
        }
        for index in 0..<weeks {
            // A screenshot run ends two days ago, so this week's photo and check-in are already done.
            let daysBack = DebugFlags.storeShots ? 7 * (weeks - 1 - index) + 2 : 7 * (weeks - index)
            let date = calendar.date(byAdding: .day, value: -daysBack, to: .now) ?? .now
            let provided = DebugFlags.photoDirectory.flatMap { UIImage(contentsOfFile: "\($0)/\(index + 1).jpg") }
            let image = provided ?? SyntheticPhoto.make(week: index, pose: .front)
            guard let photo = try? addPhoto(image, pose: .front, date: date) else { continue }
            if weeks == 1, DebugFlags.storeShots {
                // A single sample photo shows the very first check-in.
                setCheckIn(CheckIn(feedback: "Welcome to week 1. This photo is your baseline, so every later week has something honest to be measured against. The light is soft and even and you're centered in the frame, which will make next week's comparison a fair one.",
                                   focusTip: "Take next week's photo in the same spot, at the same time of day.",
                                   createdAt: date),
                           for: photo)
            }
            if index > 0 {
                // -cleanPaywall is the App Store screenshot run, so it shows a representative check-in.
                let forScreenshots = DebugFlags.storeShots
                setCheckIn(CheckIn(feedback: forScreenshots
                                    ? "Your shoulders are carrying more width than in your earlier photo, and your arms look fuller from this angle. The light is close to last time, so this comparison is a fair one. \(Self.numberWord(weeks)) weeks of showing up is what makes this visible."
                                    : "Sample feedback from a test build, not a real check-in.",
                                   focusTip: forScreenshots
                                    ? "Add one more set of overhead press this week."
                                    : "Sample tip from a test build.",
                                   createdAt: date, isSample: !forScreenshots),
                           for: photo)
            }
        }
        // A gently rising weight logged most days, and measurements every other week, for a bulking demo.
        let days = weeks * 7
        for day in stride(from: days, through: 0, by: -1) where day % 3 != 1 {
            let date = calendar.date(byAdding: .day, value: -day, to: .now) ?? .now
            let progress = Double(days - day) / Double(max(days, 1))
            let wobble = sin(Double(day) * 1.7) * 0.35
            bodyEntries.append(BodyEntry(id: UUID(), date: date, metric: .weight, value: 78 + progress * 2.6 + wobble))
            if day % 14 == 0 {
                bodyEntries.append(BodyEntry(id: UUID(), date: date, metric: .waist, value: 82 + progress * 0.8))
                bodyEntries.append(BodyEntry(id: UUID(), date: date, metric: .chest, value: 101 + progress * 3))
                bodyEntries.append(BodyEntry(id: UUID(), date: date, metric: .arms, value: 35 + progress * 1.4))
            }
        }
        bodyEntries.sort { $0.date < $1.date }
        save()
        #endif
    }
}

enum ImageLoader {
    nonisolated static func load(url: URL, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A drawn stand-in for the camera, used on the simulator and in test data. Never shown on a real phone.
enum SyntheticPhoto {
    static func make(week: Int, pose: Pose) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(white: 0.30, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            let growth = CGFloat(week) * 9
            let shoulders = (pose == .side ? 130 : 230) + growth
            let waist = (pose == .side ? 110 : 150) + growth * 0.3
            let cx = size.width / 2
            // The App Store screenshot run: an illustrated figure, not a photo of a real person.
            if DebugFlags.storeShots {
                let w = 118 + growth * 0.7
                let body = UIBezierPath()
                body.move(to: CGPoint(x: cx - 42, y: 300))
                body.addCurve(to: CGPoint(x: cx - w - 60, y: 410),
                              controlPoint1: CGPoint(x: cx - 60, y: 345), controlPoint2: CGPoint(x: cx - w - 20, y: 340))
                body.addCurve(to: CGPoint(x: cx - w - 45, y: 790),
                              controlPoint1: CGPoint(x: cx - w - 105, y: 520), controlPoint2: CGPoint(x: cx - w - 80, y: 680))
                body.addLine(to: CGPoint(x: cx - w + 5, y: 790))
                body.addCurve(to: CGPoint(x: cx - 125, y: 720),
                              controlPoint1: CGPoint(x: cx - w + 15, y: 660), controlPoint2: CGPoint(x: cx - 150, y: 640))
                body.addCurve(to: CGPoint(x: cx - 135, y: 1200),
                              controlPoint1: CGPoint(x: cx - 120, y: 850), controlPoint2: CGPoint(x: cx - 150, y: 1000))
                body.addLine(to: CGPoint(x: cx + 135, y: 1200))
                body.addCurve(to: CGPoint(x: cx + 125, y: 720),
                              controlPoint1: CGPoint(x: cx + 150, y: 1000), controlPoint2: CGPoint(x: cx + 120, y: 850))
                body.addCurve(to: CGPoint(x: cx + w - 5, y: 790),
                              controlPoint1: CGPoint(x: cx + 150, y: 640), controlPoint2: CGPoint(x: cx + w - 15, y: 660))
                body.addLine(to: CGPoint(x: cx + w + 45, y: 790))
                body.addCurve(to: CGPoint(x: cx + w + 60, y: 410),
                              controlPoint1: CGPoint(x: cx + w + 80, y: 680), controlPoint2: CGPoint(x: cx + w + 105, y: 520))
                body.addCurve(to: CGPoint(x: cx + 42, y: 300),
                              controlPoint1: CGPoint(x: cx + w + 20, y: 340), controlPoint2: CGPoint(x: cx + 60, y: 345))
                body.close()
                let head = UIBezierPath(ovalIn: CGRect(x: cx - 58, y: 130, width: 116, height: 165))
                body.append(head)
                let layer = UIGraphicsImageRenderer(size: size, format: format).image { inner in
                    UIColor(white: 0.07, alpha: 1).setFill()
                    inner.fill(CGRect(origin: .zero, size: size))
                    body.addClip()
                    let warm = [UIColor(red: 0.86, green: 0.55, blue: 0.38, alpha: 1).cgColor,
                                UIColor(red: 0.28, green: 0.14, blue: 0.09, alpha: 1).cgColor]
                    let light = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: warm as CFArray, locations: [0, 1])!
                    inner.cgContext.drawRadialGradient(light, startCenter: CGPoint(x: cx - 90, y: 330), startRadius: 20,
                                                       endCenter: CGPoint(x: cx, y: 520), endRadius: 640, options: [.drawsAfterEndLocation])
                }
                let input = CIImage(image: layer)!.clampedToExtent()
                let blurred = input.applyingGaussianBlur(sigma: 16).cropped(to: CGRect(origin: .zero, size: size))
                if let output = CIContext().createCGImage(blurred, from: blurred.extent) {
                    UIImage(cgImage: output).draw(in: CGRect(origin: .zero, size: size))
                }
                return
            }
            UIColor(red: 0.72, green: 0.56, blue: 0.46, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: cx - 70, y: 130, width: 140, height: 170))
            let torso = UIBezierPath()
            torso.move(to: CGPoint(x: cx - shoulders, y: 340))
            torso.addLine(to: CGPoint(x: cx + shoulders, y: 340))
            torso.addLine(to: CGPoint(x: cx + waist, y: 720))
            torso.addLine(to: CGPoint(x: cx + waist, y: 1120))
            torso.addLine(to: CGPoint(x: cx - waist, y: 1120))
            torso.addLine(to: CGPoint(x: cx - waist, y: 720))
            torso.close()
            torso.fill()

            let label = "TEST PHOTO"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ]
            let width = (label as NSString).size(withAttributes: attributes).width
            (label as NSString).draw(at: CGPoint(x: cx - width / 2, y: 40), withAttributes: attributes)
        }
    }
}
