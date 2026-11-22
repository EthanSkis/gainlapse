import SwiftUI

/// Stands in for a paid feature. Tapping it opens the paywall in a sheet.
struct LockedFeatureCard: View {
    let title: String
    let detail: String
    var symbol = "lock.fill"

    @State private var showPaywall = false

    var body: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start free trial")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22))
        .sheet(isPresented: $showPaywall) { PaywallView(context: .feature) }
    }
}

/// Week 1 next to now, locked: the earlier photo stays hidden behind a blur until they subscribe.
struct LockedCompare: View {
    let before: ProgressPhoto
    let after: ProgressPhoto

    @State private var showPaywall = false

    var body: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 6) {
                PhotoFrame(photo: before, maxPixels: 300)
                    .blur(radius: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                PhotoFrame(photo: after, maxPixels: 300)
                    .blur(radius: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .overlay {
                Label("Compare side by side", systemImage: "lock.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare side by side. Locked. Opens subscription options.")
        .sheet(isPresented: $showPaywall) { PaywallView(context: .feature) }
    }
}
