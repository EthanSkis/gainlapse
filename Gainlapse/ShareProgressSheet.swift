import SwiftUI
import UIKit

/// Turns one pose's photos into a 9:16 video or image to post, with a preview of exactly what gets shared.
struct ShareProgressSheet: View {
    let pose: Pose

    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var format = Format.video
    @State private var preview: UIImage?
    @State private var isExporting = false
    @State private var shareItem: ShareItem?
    @State private var failed = false
    @State private var lastURL: URL?

    private enum Format: String, CaseIterable, Identifiable {
        case video = "Timelapse", image = "Before & after"
        var id: String { rawValue }
    }

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var photos: [ProgressPhoto] { store.photos(for: pose) }
    private var hasComparison: Bool { photos.count >= 2 }
    private var makesVideo: Bool { hasComparison && format == .video }

    private var frames: [TimelapseExporter.Frame] {
        photos.map { TimelapseExporter.Frame(url: store.fileURL(for: $0), week: store.weekNumber(for: $0)) }
    }

    /// Free exports always carry the Gainlapse branding; subscribers can turn it off.
    private var isBranded: Bool { store.profile.watermark || !subscriptions.isEntitled }

    private var branded: Binding<Bool> {
        Binding { isBranded } set: { store.profile.watermark = $0 }
    }

    private var previewKey: String { "\(makesVideo)-\(isBranded)-\(photos.map(\.filename).joined())" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if hasComparison {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { option in Text(option.rawValue).tag(option) }
                    }
                    .pickerStyle(.segmented)
                }
                previewCard
                if subscriptions.isEntitled {
                    Toggle("Show Gainlapse branding", isOn: branded)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Button { showPaywall = true } label: {
                        HStack {
                            Label("Remove branding, full quality", systemImage: "lock.fill")
                            Spacer()
                            Text("Unlock").foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Nothing is shared until you choose where it goes.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                Button { Task { await export() } } label: {
                    if isExporting { ProgressView().tint(.white) } else { Text(makesVideo ? "Share timelapse" : "Share image") }
                }
                .buttonStyle(.primary)
                .disabled(isExporting || photos.isEmpty)
            }
            .padding(16)
            .background(AmbientBackground())
            .navigationTitle(hasComparison ? "Share your progress" : "Share week 1")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .task(id: previewKey) { await loadPreview() }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .feature) }
            .sensoryFeedback(.selection, trigger: format)
            .sheet(item: $shareItem, onDismiss: {
                if let url = lastURL { try? FileManager.default.removeItem(at: url) }
            }) { item in
                ActivityShareSheet(url: item.url).presentationDetents([.medium, .large])
            }
            .alert("Couldn't make that", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private var previewCard: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            if makesVideo, preview != nil {
                Label("\(photos.count) weeks", systemImage: "play.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(makesVideo ? "Preview of your timelapse" : "Preview of your image")
    }

    private func loadPreview() async {
        let frames = frames
        let video = makesVideo
        let isBranded = isBranded
        let image = await Task.detached(priority: .userInitiated) {
            TimelapseExporter.preview(frames: frames, video: video, branded: isBranded)
        }.value
        withAnimation(.smooth(duration: 0.2)) { preview = image }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        let frames = frames
        let video = makesVideo
        let isBranded = isBranded
        let fullQuality = subscriptions.isEntitled
        do {
            let url = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                video ? try await TimelapseExporter.video(frames: frames, branded: isBranded, fullQuality: fullQuality)
                      : try TimelapseExporter.still(frames: frames, branded: isBranded)
            }.value
            lastURL = url
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            shareItem = ShareItem(url: url)
        } catch {
            failed = true
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
