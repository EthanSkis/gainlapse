import SwiftUI

struct CheckInView: View {
    let photo: ProgressPhoto
    /// Called when the AI can't use this photo and the user chooses to take it again.
    var onRetake: (Pose) -> Void = { _ in }

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .idle
    @State private var didFinish = false
    @State private var needsRetake = false

    private enum Phase: Equatable {
        case idle, loading
        case failed(title: String, detail: String, canRetry: Bool)
    }

    private var current: ProgressPhoto { store.photos.first { $0.id == photo.id } ?? photo }
    private var comparison: ProgressPhoto? { store.comparison(for: current) }
    private var canCheckIn: Bool { store.canCheckIn(current) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photos
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AmbientBackground())
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Week \(store.weekNumber(for: current))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
            }
        }
        .sensoryFeedback(.success, trigger: didFinish)
        .task { await startIfAllowed() }
    }

    private var photos: some View {
        HStack(spacing: 10) {
            if let comparison {
                labeledPhoto(comparison, label: "Week \(store.weekNumber(for: comparison))")
            }
            labeledPhoto(current, label: comparison == nil ? "Week \(store.weekNumber(for: current))" : "This week")
        }
        // A single photo stays small enough to keep the text below it in view.
        .frame(maxWidth: comparison == nil ? 220 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func labeledPhoto(_ photo: ProgressPhoto, label: String) -> some View {
        PhotoFrame(photo: photo, maxPixels: 800)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .padding(8)
            }
    }

    @ViewBuilder private var content: some View {
        if let checkIn = current.checkIn ?? store.weekCheckIn(for: current) {
            result(checkIn)
        } else if !canCheckIn {
            card(title: "Baseline saved", symbol: "flag.fill",
                 text: "This is the starting point for this pose. Your check-in compares against it next week.")
        } else if store.profile.aiConsent == nil {
            consent
        } else if store.profile.aiConsent == false {
            card(title: "AI check-ins are off", symbol: "lock.fill",
                 text: "Your photo is saved and added to your timelapse. You can turn check-ins on in Settings.")
        } else {
            switch phase {
            case .idle, .loading: loading
            case .failed(let title, let detail, _): card(title: title, symbol: "exclamationmark.circle.fill", text: detail)
            }
        }
    }

    private func result(_ checkIn: CheckIn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: comparison == nil ? "Your starting point" : "Your check-in", symbol: "text.bubble.fill",
                 text: checkIn.feedback)
            card(title: "Focus this week", symbol: "scope", text: checkIn.focusTip)
            if checkIn.isSample {
                Label("Test build: this isn't real AI feedback", systemImage: "hammer.fill")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func card(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }

    private var loading: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.accent)
            Text(comparison == nil ? "Looking at your first photo…" : "Comparing your photos…")
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get AI feedback on your photos?").font(.headline)
            Text("To write your check-in, Gainlapse sends your photos to its server and to Anthropic's Claude AI. Gainlapse doesn't keep them on its server, and they're never public. Check-ins are for adults 18 and older.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 8) {
            if current.checkIn == nil, canCheckIn, store.profile.aiConsent == nil {
                Link("Read the privacy policy", destination: Backend.privacyURL)
                    .font(.footnote)
                    .frame(minHeight: 32)
                Button("I'm 18+, allow and get check-in") {
                    store.profile.aiConsent = true
                    Task { await run() }
                }
                .buttonStyle(.primary)
                Button("Not now") {
                    store.profile.aiConsent = false
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(minHeight: 36)
            } else if needsRetake {
                Button("Retake photo") { onRetake(current.pose) }.buttonStyle(.primary)
            } else if case .failed(_, _, true) = phase {
                Button("Try again") { Task { await run() } }.buttonStyle(.primary)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
                    .disabled(phase == .loading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func startIfAllowed() async {
        guard current.checkIn == nil, canCheckIn, store.profile.aiConsent == true else { return }
        await run()
    }

    private func run() async {
        guard phase != .loading else { return }
        guard store.canRequestAI else {
            needsRetake = false
            phase = .failed(title: "That's enough tries for now",
                            detail: "Your photo is saved and added to your timelapse. You can get a check-in again in a few days.",
                            canRetry: false)
            return
        }
        phase = .loading
        var earlier: UIImage?
        if let comparison { earlier = await store.image(for: comparison, maxPixels: 1024) }
        guard let image = await store.image(for: current, maxPixels: 1024),
              comparison == nil || earlier != nil else {
            phase = .failed(title: "Photo couldn't be read", detail: "Please try again.", canRetry: true)
            return
        }
        do {
            let checkIn = try await CheckInClient.request(goal: store.profile.goal ?? .justStarted,
                                                          pose: current.pose,
                                                          week: store.weekNumber(for: current),
                                                          current: image, previous: earlier)
            store.recordAIRequest()
            store.setCheckIn(checkIn, for: current)
            phase = .idle
            didFinish = true
        } catch CheckInError.notConfigured {
            phase = .failed(title: "Check-ins aren't connected yet",
                            detail: "Your photo is saved and added to your timelapse. Check-ins will work once the AI service is connected.",
                            canRetry: false)
        } catch CheckInError.subscriptionRequired {
            phase = .failed(title: "Couldn't confirm your subscription",
                            detail: "Your photo is saved. Try Restore purchases in Settings, then try again.",
                            canRetry: true)
        } catch CheckInError.limitReached {
            phase = .failed(title: "That's enough tries for now",
                            detail: "Your photo is saved and added to your timelapse. You can get a check-in again in a few days.",
                            canRetry: false)
        } catch CheckInError.declined {
            store.recordAIRequest()
            phase = .failed(title: "No check-in for this photo",
                            detail: "We couldn't write feedback for this one. Your photo is still saved and added to your timelapse.",
                            canRetry: false)
        } catch CheckInError.unusable(let message) {
            store.recordAIRequest()
            needsRetake = store.canRequestAI
            phase = .failed(title: "Try a different photo", detail: message, canRetry: false)
        } catch {
            phase = .failed(title: "Check-in didn't load",
                            detail: "Your photo is saved. Check your connection and try again.",
                            canRetry: true)
        }
    }
}
