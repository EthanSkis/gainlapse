import Foundation
import HealthKit

/// Reads body weight from Apple Health. Gainlapse only reads; it never writes to Health,
/// and weights it imports stay on this phone.
enum HealthSync {
    struct Sample: Sendable {
        let id: UUID
        let date: Date
        let kilograms: Double
    }

    private static let store = HKHealthStore()
    private static let bodyMass = HKQuantityType(.bodyMass)

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows Apple's permission sheet. Health never says whether reading was allowed,
    /// so the answer is only whether the sheet was shown without an error.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMass])
            return true
        } catch {
            return false
        }
    }

    static func weights(since start: Date) async -> [Sample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 2_000)
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map {
            Sample(id: $0.uuid, date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }
}
