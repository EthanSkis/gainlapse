import SwiftUI

/// A milestone look back: week 1 against now, the numbers that moved, and one button to share it.
struct RecapView: View {
    let weeks: Int

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

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
                    if let first = photos.first, let latest = photos.last, first.id != latest.id {
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
                Button("Share your recap") { showShare = true }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showShare) { ShareProgressSheet(pose: pose) }
            .onAppear { store.markRecapSeen(weeks) }
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
