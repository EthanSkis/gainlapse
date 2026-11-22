import SwiftUI

/// A milestone look back: week 1 against now, the numbers that moved, and one button to share it.
struct RecapView: View {
    let weeks: Int

    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var showPaywall = false

    /// The first recap is the moment the first timelapse is ready, so free users are offered the full one here.
    private var offersUpgrade: Bool { !subscriptions.isEntitled }

    /// The pose with the most photos makes the fairest comparison.
    private var pose: Pose {
        store.posesWithPhotos.max { store.photos(for: $0).count < store.photos(for: $1).count } ?? .front
    }

    private var photos: [ProgressPhoto] { store.photos(for: pose) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Stamp(text: "\(store.photoWeekCount) weeks of photos", color: Theme.accent)
                        Text(ProgressStore.recapTitle(weeks).uppercased())
                            .font(.brand(64))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if offersUpgrade, let first = photos.first, let latest = photos.last, first.id != latest.id {
                        LockedCompare(before: first, after: latest)
                        stats(from: first.date, to: latest.date)
                    } else if let first = photos.first, let latest = photos.last, first.id != latest.id {
                        CompareSlider(before: first, after: latest,
                                      beforeLabel: "Week \(store.weekNumber(for: first))",
                                      afterLabel: "Week \(store.weekNumber(for: latest))")
                        Text("Drag to compare")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity)
                        stats(from: first.date, to: latest.date)
                    }
                    if let focus = store.photos.last(where: { $0.checkIn != nil })?.checkIn?.focusTip {
                        VStack(alignment: .leading, spacing: 6) {
                            Stamp(text: "Focus for the next stretch", color: Theme.accent)
                            Text(focus).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(AmbientBackground())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if offersUpgrade {
                        Button("Unlock your full timelapse") { showPaywall = true }
                            .buttonStyle(.primary)
                        Button("Share the free version") { showShare = true }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(minHeight: 36)
                    } else {
                        Button("Share your recap") { showShare = true }
                            .buttonStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                // Cards scrolling underneath fade out instead of showing through the buttons.
                .background {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.95)],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
                        .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showShare) { ShareProgressSheet(pose: pose) }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .timelapseReady) }
            .onAppear {
                let isFirstView = !(store.profile.seenRecaps ?? []).contains(weeks)
                store.markRecapSeen(weeks)
                // The first time the first timelapse is ready, the offer opens on its own. After that it waits for a tap.
                if isFirstView && offersUpgrade && weeks == ProgressStore.recapWeeks[0] { showPaywall = true }
            }
            .sensoryFeedback(.success, trigger: weeks)
        }
    }

    private func stats(from start: Date, to end: Date) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            stat("Streak", value: store.streak == 1 ? "1 week" : "\(store.streak) weeks")
            stat("Photos", value: "\(store.photos.count)")
            ForEach(BodyMetric.allCases) { metric in
                if let change = store.change(for: metric, from: start, to: end) ?? (metric == .weight ? store.trendChange(for: metric) : nil) {
                    stat(metric.title, value: metric.format(change, metric: store.usesMetric, signed: true))
                }
            }
        }
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.stamp(11)).tracking(1).foregroundStyle(Theme.secondaryText)
            Text(value).font(.brand(32))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
