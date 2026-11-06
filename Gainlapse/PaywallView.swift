import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.openURL) private var openURL
    @State private var selectedID = Subscriptions.annualID
    @State private var isWorking = false
    @State private var message: String?
    @State private var showPrivacy = false

    private struct Plan: Identifiable {
        let id: String
        let title: String
        let price: String
        let note: String?
        let terms: String
        let product: Product?
    }

    private var plans: [Plan] {
        if !subscriptions.products.isEmpty {
            return subscriptions.products.map { product in
                let annual = product.id == Subscriptions.annualID
                let period = annual ? "year" : "week"
                let trial = trialText(for: product)
                return Plan(id: product.id, title: annual ? "Annual" : "Weekly",
                            price: "\(product.displayPrice)/\(period)",
                            note: annual ? "Best value" : nil,
                            terms: "\(trial)then \(product.displayPrice)/\(period). Renews automatically unless you cancel at least 24 hours before renewal. Manage it in your Apple Account.",
                            product: product)
            }
        }
        #if DEBUG
        return [
            Plan(id: Subscriptions.annualID, title: "Annual", price: "$59.99/year", note: "Best value",
                 terms: "Free for 7 days, then $59.99/year. Cancel anytime.", product: nil),
            Plan(id: Subscriptions.weeklyID, title: "Weekly", price: "$4.99/week", note: nil,
                 terms: "Free for 7 days, then $4.99/week. Cancel anytime.", product: nil),
        ]
        #else
        return []
        #endif
    }

    private func trialText(for product: Product) -> String {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return "" }
        let days = offer.period.unit == .day ? offer.period.value : offer.period.value * 7
        return "Free for \(days) days, "
    }

    private var selectedPlan: Plan? { plans.first { $0.id == selectedID } }
    private var isFirstWeek: Bool { store.photos.count <= 1 }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 12) {
                        benefit("A weekly photo that lines up with the last", symbol: "person.crop.rectangle.stack.fill")
                        benefit("Honest AI check-ins on what's changing", symbol: "text.bubble.fill")
                        benefit("A timelapse that builds itself", symbol: "play.square.stack.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    if plans.isEmpty {
                        unavailable
                    } else {
                        GlassEffectContainer {
                            VStack(spacing: 10) {
                                ForEach(plans) { plan in planRow(plan) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { footer }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .alert("Something went wrong", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .sheet(isPresented: $showPrivacy) { NavigationStack { PrivacyView(showsDelete: true) } }
    }

    private func benefit(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 26)
            Text(text)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if let photo = store.latestPhoto {
                    PhotoFrame(photo: photo, maxPixels: 400)
                        .frame(width: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Stamp(text: isFirstWeek ? "Week 1 saved" : "Your photos are safe", color: Theme.accent)
                    Barbell(plates: store.photoWeekCount, height: 54).frame(width: 150)
                }
            }
            Text(isFirstWeek ? "KEEP YOUR TIMELAPSE GOING" : "PICK UP WHERE YOU LEFT OFF")
                .font(.brand(60))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans couldn't load. Check your connection and try again.")
                .foregroundStyle(Theme.secondaryText)
            Button("Try again") { Task { await subscriptions.loadProducts() } }
                .frame(minHeight: 44)
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        let isSelected = selectedID == plan.id
        return Button { selectedID = plan.id } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .black : Theme.secondaryText)
                Text(plan.title).font(.headline).foregroundStyle(isSelected ? .black : .white)
                if let note = plan.note {
                    Text(note)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? .white : .black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(isSelected ? Color.black : Theme.accent, in: Capsule())
                }
                Spacer()
                Text(plan.price).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? .black : .white)
            }
            .padding(16)
            .frame(minHeight: 62)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .glassEffect(isSelected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                     in: RoundedRectangle(cornerRadius: 22))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button { Task { await start() } } label: {
                if isWorking { ProgressView().tint(.black) } else { Text("Start free trial") }
            }
            .buttonStyle(.primary)
            .disabled(isWorking || selectedPlan == nil)
            Text(selectedPlan?.terms ?? " ")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            #if DEBUG
            if selectedPlan?.product == nil && !ProcessInfo.processInfo.arguments.contains("-cleanPaywall") {
                Text("Test build: no real charge").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            #endif
            HStack(spacing: 18) {
                Button("Restore") { Task { await restore() } }
                Button("Terms") {
                    openURL(Backend.termsURL)
                }
                Button("Privacy") { showPrivacy = true }
                    .accessibilityLabel("Privacy policy")
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .frame(minHeight: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func start() async {
        isWorking = true
        defer { isWorking = false }
        guard let plan = selectedPlan else { return }
        guard let product = plan.product else {
            #if DEBUG
            subscriptions.grantPreviewEntitlement()
            #endif
            return
        }
        do {
            _ = try await subscriptions.purchase(product)
        } catch {
            message = "Your purchase didn't go through, and you weren't charged. Please try again."
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await subscriptions.restore()
            if !subscriptions.isEntitled { message = "No active subscription was found for this Apple Account." }
        } catch {
            message = "Purchases couldn't be restored. Check your connection and try again."
        }
    }
}
