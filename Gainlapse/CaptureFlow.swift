import SwiftUI
import UIKit

/// Camera, then review, then check-in. During onboarding it ends at the saved photo, which leads to the paywall.
struct CaptureFlow: View {
    let isOnboarding: Bool
    var initialPose: Pose?
    var isRetake = false

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var captured: UIImage?
    @State private var pose: Pose = .front
    @State private var savedPhoto: ProgressPhoto?
    @State private var saveFailed = false
    @State private var confirmReplace = false
    @State private var retakeRequested = false

    var body: some View {
        Group {
            if let savedPhoto {
                NavigationStack {
                    CheckInView(photo: savedPhoto) { retakePose in
                        pose = retakePose
                        retakeRequested = true
                        captured = nil
                        self.savedPhoto = nil
                    }
                }
            } else if let captured {
                review(captured)
            } else {
                CameraView(pose: $pose) { image in
                    store.saveDraft(image, pose: pose)
                    captured = image
                }
            }
        }
        .onAppear {
            if let draft = store.loadDraft() {
                pose = draft.pose
                captured = draft.image
            } else if let initialPose {
                pose = initialPose
            }
        }
        .alert("Replace this week's \(pose.rawValue) photo?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) {
                if let captured { save(captured) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The photo you already took for this pose will be replaced. Your check-in for this week stays.")
        }
        .alert("Your photo couldn't be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that your iPhone has free storage, then try again.")
        }
    }

    private func review(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Text("\(pose.title) pose").font(.headline)
                    HStack {
                        GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }
                        Spacer()
                    }
                }
                .frame(minHeight: 46)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(Theme.photoAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Spacer(minLength: 0)
                Button("Use photo") { use(image) }.buttonStyle(.primary)
                Button("Retake") {
                    store.clearDraft()
                    captured = nil
                }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minHeight: 36)
            }
            .padding(.horizontal, 16)
        }
    }

    private func use(_ image: UIImage) {
        let replacesPhoto = store.photosThisWeek.contains { $0.pose == pose }
        if replacesPhoto && !isRetake && !retakeRequested {
            confirmReplace = true
        } else {
            save(image)
        }
    }

    private func save(_ image: UIImage) {
        do {
            let photo = try store.addPhoto(image, pose: pose)
            store.clearDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if isOnboarding {
                store.profile.onboardingDone = true
                dismiss()
            } else {
                savedPhoto = photo
            }
        } catch {
            saveFailed = true
        }
    }
}

struct CameraView: View {
    @Binding var pose: Pose
    let onCapture: (UIImage) -> Void

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var camera = CameraController()
    @State private var timerSeconds = 5
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var showGhost = true
    @State private var ghost: UIImage?
    @State private var flash = false

    private let timerOptions = [0, 3, 5, 10]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.access == .denied {
                deniedView
            } else {
                VStack(spacing: 14) {
                    topBar
                    viewfinder
                    posePicker
                    Spacer(minLength: 0)
                    bottomBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .task { await camera.start() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
        .task(id: pose) { await loadGhost() }
        .sensoryFeedback(.selection, trigger: pose)
        .sensoryFeedback(.impact(weight: .light), trigger: countdown)
    }

    private var topBar: some View {
        HStack {
            GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }
            Spacer()
            if store.ghostPhoto(for: pose) != nil {
                GlassIconButton(symbol: showGhost ? "person.fill.viewfinder" : "viewfinder",
                                label: showGhost ? "Hide last photo" : "Show last photo") { showGhost.toggle() }
            }
            GlassIconButton(symbol: "arrow.triangle.2.circlepath.camera", label: "Switch camera") { camera.flip() }
        }
    }

    private var viewfinder: some View {
        Rectangle()
            .fill(Theme.surface)
            .aspectRatio(Theme.photoAspect, contentMode: .fit)
            .overlay {
                if hasRealCamera {
                    CameraPreview(session: camera.session)
                } else {
                    Text("The simulator has no camera. A test photo will be used.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center).padding(40)
                }
            }
            .overlay {
                if showGhost, let ghost {
                    Image(uiImage: ghost).resizable().scaledToFill().opacity(0.38).allowsHitTesting(false)
                } else if ghost == nil {
                    guideLines
                }
            }
            .overlay {
                if let countdown {
                    Text("\(countdown)")
                        .font(.brand(110))
                        .foregroundStyle(.white)
                        .shadow(radius: 10)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .overlay {
                FrameBrackets()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .allowsHitTesting(false)
            }
            .overlay { if flash { Color.white } }
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    /// Shown until there's a last photo to line up with.
    private var guideLines: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack {
                ForEach([0.08, 0.94], id: \.self) { position in
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: height * position))
                        path.addLine(to: CGPoint(x: geometry.size.width - 20, y: height * position))
                    }
                    .stroke(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                }
                Text("Keep your head and feet between the lines")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassEffect(.regular, in: Capsule())
                    .position(x: geometry.size.width / 2, y: height * 0.13)
            }
        }
        .allowsHitTesting(false)
    }

    private var posePicker: some View {
        Picker("Pose", selection: $pose) {
            ForEach(Pose.allCases) { option in Text(option.title).tag(option) }
        }
        .pickerStyle(.segmented)
        .disabled(countdown != nil)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                let index = timerOptions.firstIndex(of: timerSeconds) ?? 0
                timerSeconds = timerOptions[(index + 1) % timerOptions.count]
            } label: {
                Label(timerSeconds == 0 ? "Off" : "\(timerSeconds)s", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 46)
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityLabel("Self-timer \(timerSeconds == 0 ? "off" : "\(timerSeconds) seconds")")
            Spacer()
            Button(action: shutterTapped) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    if countdown == nil {
                        Circle().fill(Theme.accent).frame(width: 62, height: 62)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                    }
                }
            }
            .accessibilityLabel(countdown == nil ? "Take photo" : "Cancel timer")
            Spacer()
            Color.clear.frame(width: 84, height: 46)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            HStack {
                GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }
                Spacer()
            }
            Spacer()
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("Camera access is off").font(.title3.weight(.bold))
            Text("Gainlapse needs the camera for your weekly photo. It stays private in the app unless you ask for a check-in or export it.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.secondaryText)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.primary)
        }
        .padding(16)
    }

    private func loadGhost() async {
        guard let photo = store.ghostPhoto(for: pose) else {
            ghost = nil
            return
        }
        ghost = await store.image(for: photo, maxPixels: 1200)
    }

    private func shutterTapped() {
        if countdown != nil {
            countdownTask?.cancel()
            countdown = nil
            return
        }
        countdownTask = Task {
            var remaining = timerSeconds
            while remaining > 0 {
                withAnimation { countdown = remaining }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            countdown = nil
            takePhoto()
        }
    }

    private func takePhoto() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        flash = true
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            flash = false
        }
        guard hasRealCamera else {
            let week = store.photos(for: pose).count
            onCapture(CameraController.prepare(SyntheticPhoto.make(week: week, pose: pose)))
            return
        }
        camera.capture { image in
            if let image { onCapture(image) }
        }
    }
}
