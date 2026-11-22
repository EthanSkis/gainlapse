import Foundation
import Observation
import RevenueCat
import StoreKit

@MainActor
@Observable
final class Subscriptions {
    static let weeklyID = "com.ethangardner.gainlapse.weekly"
    static let annualID = "com.ethangardner.gainlapse.annual"

    /// RevenueCat's public Apple SDK key (starts with "appl_"). It is meant to ship inside the app.
    /// Left empty, RevenueCat stays off and the app works exactly as before.
    static let revenueCatAPIKey = "appl_jxOPfxfrpeZuBUQmdprSaOVPOVB"

    /// Local test builds (Debug, or anything in the simulator) stay out of RevenueCat, so reinstalls
    /// don't show up as customers. Launch with -revenueCat to turn it on for a local test.
    private static var revenueCatEnabledHere: Bool {
        if ProcessInfo.processInfo.arguments.contains("-revenueCat") { return true }
        #if DEBUG || targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// RevenueCat watches purchases the app completes itself, so the paywall, the entitlement check
    /// and the server's signed-transaction check all keep running on StoreKit as before.
    static func configureRevenueCat() {
        guard !revenueCatAPIKey.isEmpty, !Purchases.isConfigured, revenueCatEnabledHere else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(with: Configuration.Builder(withAPIKey: revenueCatAPIKey)
            .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
            .build())
    }

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
        UserDefaults.standard.removeObject(forKey: Self.lastKnownKey)
        isEntitled = false
    }
    #endif

    /// The last answer from the App Store, so a returning subscriber opens straight into the app.
    /// The real check still runs on every launch and corrects it.
    private static let lastKnownKey = "subscription.lastKnownEntitled"

    /// True for Debug builds and for TestFlight or Xcode installs, which buy with sandbox accounts.
    /// Test builds skip the AI check-in limits; App Store installs never do.
    nonisolated(unsafe) static var isTestBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    func start() async {
        Self.configureRevenueCat()
        if case .verified(let app)? = try? await AppTransaction.shared, app.environment != .production {
            Self.isTestBuild = true
        }
        #if DEBUG
        let forcesFree = ProcessInfo.processInfo.arguments.contains("-forceFree")
        #else
        let forcesFree = false
        #endif
        if !forcesFree, UserDefaults.standard.bool(forKey: Self.lastKnownKey) {
            isEntitled = true
            hasChecked = true
        }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        await refreshEntitlement()
        hasChecked = true
        Task { await syncExistingSubscriptionOnce() }
        await loadProducts()
    }

    private static let revenueCatSyncedKey = "revenuecat.didSyncExistingSubscription"

    /// People who subscribed before RevenueCat was added are unknown to it. The first launch of a
    /// build with RevenueCat sends their subscription over once, then never again on this device.
    private func syncExistingSubscriptionOnce() async {
        guard Purchases.isConfigured,
              !UserDefaults.standard.bool(forKey: Self.revenueCatSyncedKey) else { return }
        if isEntitled {
            // On failure the flag stays unset, so the next launch tries again.
            guard (try? await Purchases.shared.syncPurchases()) != nil else { return }
        }
        // Nothing to send when there is no subscription; a later purchase is reported as it happens.
        UserDefaults.standard.set(true, forKey: Self.revenueCatSyncedKey)
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
        // Test builds launched with -forceFree act like a free user, even with a test subscription on the device.
        if ProcessInfo.processInfo.arguments.contains("-forceFree") { active = false }
        #endif
        isEntitled = active
        UserDefaults.standard.set(active, forKey: Self.lastKnownKey)
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
        if Purchases.isConfigured {
            // Reporting is best effort; a RevenueCat outage never blocks a purchase.
            _ = try? await Purchases.shared.recordPurchase(result)
        }
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
        if Purchases.isConfigured { _ = try? await Purchases.shared.syncPurchases() }
        await refreshEntitlement()
    }
}
