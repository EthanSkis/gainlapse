import StoreKit
import SwiftUI

/// Why the paywall is showing, which sets its headline.
enum PaywallContext {
    /// Once, right after onboarding.
    case intro
    /// When the first month's timelapse is ready.
    case timelapseReady
    /// From a locked feature.
    case feature
}

struct PaywallView: View {
    var context: PaywallContext = .feature
    /// Called when the user closes it without buying. Sheets are closed with dismiss instead.
    var onClose: (() -> Void)?

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
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

    private var stampText: String {
        switch context {
        case .intro: isFirstWeek ? "Week 1 locked in" : "Your photos are safe"
        case .timelapseReady: "\(store.photoWeekCount) weeks of photos"
        case .feature: "Your photos are always free"
        }
    }

    private var headline: String {
        switch context {
        case .intro: isFirstWeek ? "SEE EVERY GAIN, NOT JUST PHOTOS" : "PICK UP WHERE YOU LEFT OFF"
        case .timelapseReady: "YOUR FIRST TIMELAPSE IS READY"
        case .feature: "GET THE FULL PICTURE"
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 12) {
                        benefit("Your full-quality timelapse, without the watermark", symbol: "play.square.stack.fill")
                        benefit("Honest AI check-ins on what's changing", symbol: "text.bubble.fill")
                        benefit("Week 1 next to now, side by side", symbol: "rectangle.split.2x1.fill")
                        benefit("Weekly photos stay free, always", symbol: "camera.fill")
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
                    Stamp(text: stampText, color: Theme.accent)
                    Barbell(plates: store.photoWeekCount, height: 54).frame(width: 150)
                    if let weight = store.latestEntry(for: .weight) {
                        Text("Starting at \(BodyMetric.weight.format(weight.value, metric: store.usesMetric))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                GlassIconButton(symbol: "xmark", label: "Close") { close() }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            // Two lines at most, so both plans fit above the button on smaller iPhones.
            Text(headline)
                .font(.brand(60))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
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
            if selectedPlan?.product == nil && !DebugFlags.storeShots {
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
        // If the plans ever run long, they fade out under the button instead of showing through it.
        .background {
            LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
        }
    }

    private func start() async {
        isWorking = true
        defer { isWorking = false }
        guard let plan = selectedPlan else { return }
        guard let product = plan.product else {
            #if DEBUG
            subscriptions.grantPreviewEntitlement()
            if onClose == nil { dismiss() }
            #endif
            return
        }
        do {
            if try await subscriptions.purchase(product), onClose == nil { dismiss() }
        } catch {
            message = "Your purchase didn't go through, and you weren't charged. Please try again."
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await subscriptions.restore()
            if !subscriptions.isEntitled {
                message = "No active subscription was found for this Apple Account."
            } else if onClose == nil {
                dismiss()
            }
        } catch {
            message = "Purchases couldn't be restored. Check your connection and try again."
        }
    }
}
