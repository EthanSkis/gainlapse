import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class Subscriptions {
    static let weeklyID = "com.ethangardner.gainlapse.weekly"
    static let annualID = "com.ethangardner.gainlapse.annual"

    private(set) var products: [Product] = []
    private(set) var isEntitled = false
    private(set) var hasChecked = false
    private(set) var isLoadingProducts = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    #if DEBUG
    /// Lets a test build pass the paywall where StoreKit has no products, such as a simulator launched outside Xcode.
    private static let previewKey = "debug.previewEntitled"
    var usesPreviewPlans: Bool { products.isEmpty && !isLoadingProducts }
    func grantPreviewEntitlement() {
        UserDefaults.standard.set(true, forKey: Self.previewKey)
        isEntitled = true
    }

    func revokePreviewEntitlement() {
        UserDefaults.standard.removeObject(forKey: Self.previewKey)
        isEntitled = false
    }
    #endif

    func start() async {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        await refreshEntitlement()
        hasChecked = true
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        var loaded: [Product] = []
        do {
            loaded = try await Product.products(for: [Self.weeklyID, Self.annualID])
            #if DEBUG
            print("[StoreKit] loaded \(loaded.count): \(loaded.map { "\($0.id) \($0.displayPrice)" })")
            #endif
        } catch {
            #if DEBUG
            print("[StoreKit] failed: \(error)")
            #endif
        }
        products = loaded.sorted { $0.price > $1.price }
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               [Self.weeklyID, Self.annualID].contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.previewKey) { active = true }
        #endif
        isEntitled = active
    }

    /// Apple's signed record of the active subscription. The server checks it before each check-in.
    static func signedTransaction() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               [weeklyID, annualID].contains(transaction.productID),
               transaction.revocationDate == nil {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    /// Returns true when the user now has access. A cancelled purchase simply returns false.
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            await refreshEntitlement()
            return isEntitled
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }
}
