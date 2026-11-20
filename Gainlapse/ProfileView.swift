import SwiftUI
import UIKit

/// The user's own page: their timelapse, comparison and every photo. Settings sits at the top right.
struct ProfileView: View {
    let scrollToTop: Int

    @Environment(ProgressStore.self) private var store
    @State private var pose: Pose = .front
    @State private var frames: [UIImage] = []
    @State private var index = 0
    @State private var isPlaying = true
    @State private var showExport = false
    @State private var showSettings = false
    @State private var selectedPhoto: ProgressPhoto?
    @State private var logMetric: BodyMetric?

    private var photos: [ProgressPhoto] { store.photos(for: pose) }
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        summary.id("top")
                        if store.photos.isEmpty {
                            emptyState
                        } else {
                            if store.posesWithPhotos.count > 1 {
                                Picker("Pose", selection: $pose) {
                                    ForEach(store.posesWithPhotos) { option in Text(option.title).tag(option) }
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 16)
                            }
                            if photos.count < 2 {
                                Text("Your timelapse starts with next week's \(pose.rawValue) photo.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            } else {
                                player
                                comparison
                            }
                            trends
                            allPhotos
                        }
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: scrollToTop) {
                    withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) }
                }
            }
            .background(AmbientBackground())
            .safeAreaInset(edge: .bottom) {
                if !photos.isEmpty {
                    Button(photos.count >= 2 ? "Share your progress" : "Share week 1") { showExport = true }
                        .buttonStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showExport) {
                ShareProgressSheet(pose: pose)
            }
            .sheet(item: $logMetric) { metric in LogBodySheet(metric: metric) }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
            .onAppear {
                if !store.posesWithPhotos.contains(pose), let first = store.posesWithPhotos.first { pose = first }
            }
            .task(id: frameKey) { await loadFrames() }
            .task(id: isPlaying) { await play() }
        }
    }

    private var frameKey: String { photos.map(\.filename).joined() }

    private var summary: some View {
        HStack(spacing: 14) {
            Barbell(plates: store.photoWeekCount, height: 44).frame(width: 126)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.photoWeekCount == 1 ? "1 WEEK" : "\(store.photoWeekCount) WEEKS").font(.brand(30))
                Text(store.streak == 1 ? "1 in a row" : "\(store.streak) in a row")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("NO PHOTOS YET").font(.brand(40))
            Text("Your timelapse builds itself from your weekly photos.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 70)
        .padding(.horizontal, 24)
    }

    private var player: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Theme.surfaceRaised)
                .aspectRatio(Theme.photoAspect, contentMode: .fit)
                .overlay {
                    if frames.indices.contains(index) {
                        Image(uiImage: frames[index]).resizable().scaledToFill()
                            .id(index)
                            .transition(.opacity)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        if photos.indices.contains(index) {
                            Text("WEEK \(store.weekNumber(for: photos[index]))")
                                .font(.brand(58))
                                .shadow(color: .black.opacity(0.5), radius: 8)
                        }
                        playerControls
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: isPlaying ? 0 : index)
    }

    private var playerControls: some View {
        HStack(spacing: 6) {
            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            if frames.count > 1 {
                Slider(value: Binding(get: { Double(index) }, set: { value in
                    isPlaying = false
                    index = Int(value.rounded())
                }), in: 0...Double(frames.count - 1), step: 1)
                .accessibilityLabel("Choose a week")
                .padding(.trailing, 14)
            }
        }
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder private var comparison: some View {
        if let first = photos.first, let latest = photos.last {
            VStack(alignment: .leading, spacing: 10) {
                Text("WEEK \(store.weekNumber(for: first)) VS LATEST").font(.brand(30))
                CompareSlider(before: first, after: latest,
                              beforeLabel: "Week \(store.weekNumber(for: first))",
                              afterLabel: "Week \(store.weekNumber(for: latest))")
                Text("Drag to compare")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                StatChangesRow(from: first.date, to: latest.date)
            }
            .padding(.horizontal, 16)
        }
    }

    /// Weight first, then any measurement that has been logged.
    private var trends: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRENDS").font(.brand(30))
            BodyTrendCard(metric: .weight) { logMetric = .weight }
            ForEach([BodyMetric.waist, .chest, .arms].filter { store.latestEntry(for: $0) != nil }) { metric in
                BodyTrendCard(metric: metric) { logMetric = metric }
            }
            if [BodyMetric.waist, .chest, .arms].allSatisfy({ store.latestEntry(for: $0) == nil }) {
                MeasurementsRow { logMetric = $0 }
            }
        }
        .padding(.horizontal, 16)
    }

    private var allPhotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL PHOTOS").font(.brand(30)).padding(.horizontal, 16)
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(store.photos.reversed()) { photo in
                    Button { selectedPhoto = photo } label: {
                        PhotoFrame(photo: photo, maxPixels: 400)
                            .overlay(alignment: .bottomLeading) {
                                Text("WK \(store.weekNumber(for: photo))")
                                    .font(.stamp(11))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 3)
                                    .padding(6)
                            }
                    }
                    .accessibilityLabel("Week \(store.weekNumber(for: photo)), \(photo.pose.title)")
                }
            }
        }
    }

    private func loadFrames() async {
        var loaded: [UIImage] = []
        for photo in photos {
            if let image = await store.image(for: photo, maxPixels: 1200) { loaded.append(image) }
        }
        frames = loaded
        index = min(index, max(loaded.count - 1, 0))
    }

    private func play() async {
        guard isPlaying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, frames.count > 1 else { continue }
            withAnimation(.easeInOut(duration: 0.28)) { index = (index + 1) % frames.count }
        }
    }
}

/// One photo and its check-in, in a sheet that swipes down to close.
private struct PhotoDetailView: View {
    let photo: ProgressPhoto
    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotoFrame(photo: photo).clipShape(RoundedRectangle(cornerRadius: 22))
                    Stamp(text: "\(photo.pose.title) / \(photo.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                    if let checkIn = photo.checkIn {
                        Text(checkIn.feedback).font(.body).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 6) {
                            Stamp(text: "Focus", color: Theme.accent)
                            Text(checkIn.focusTip).font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Week \(store.weekNumber(for: photo))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }
}
