import SwiftUI
import UserNotifications

struct HomeView: View {
    let scrollToTop: Int
    let onCapture: (Pose?, Bool) -> Void

    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var checkInPhoto: ProgressPhoto?
    @State private var retakePose: Pose?
    @State private var reminderStatus: UNAuthorizationStatus = .authorized

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    hero.id("top")
                    if isCheckInOff { checkInsOffCard }
                    if let focus = latestFocus { focusCard(focus) }
                    if store.photoWeekCount == 1 && store.hasPhotoThisWeek { comingUpCard }
                    if reminderStatus == .denied || reminderStatus == .notDetermined { remindersCard }
                    if store.hasPhotoThisWeek, let pose = store.missingPosesThisWeek.first {
                        Button("Add \(pose.title.lowercased()) pose") { onCapture(pose, false) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, 12)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await subscriptions.refreshEntitlement() }
            .onChange(of: scrollToTop) {
                withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .background(AmbientBackground())
        .safeAreaInset(edge: .bottom) { primaryAction }
        .task(id: scenePhase) { reminderStatus = await Reminders.status() }
        .fullScreenCover(item: $checkInPhoto, onDismiss: {
            if let pose = retakePose {
                retakePose = nil
                onCapture(pose, true)
            }
        }) { photo in
            NavigationStack {
                CheckInView(photo: photo) { pose in
                    retakePose = pose
                    checkInPhoto = nil
                }
            }
        }
    }

    private var latestFocus: String? { store.photos.last { $0.checkIn != nil }?.checkIn?.focusTip }

    /// There's a check-in available, but the user said no to sending photos.
    private var isCheckInOff: Bool {
        store.pendingCheckInPhoto != nil && store.profile.aiConsent == false
    }

    private var daysText: String {
        switch store.daysUntilNextCheckIn {
        case 0: return "today"
        case 1: return "tomorrow"
        case let days: return "in \(days) days"
        }
    }

    private var nextCheckInText: String {
        if !store.hasPhotoThisWeek && !store.photos.isEmpty { return "Photo due now" }
        return "Next photo \(daysText)"
    }

    @ViewBuilder private var hero: some View {
        if let photo = store.latestPhoto {
            ZStack(alignment: .bottomLeading) {
                PhotoFrame(photo: photo, fitsAspect: false)
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0),
                                       .init(color: .clear, location: 0.2),
                                       .init(color: .clear, location: 0.5),
                                       .init(color: Theme.background.opacity(0.9), location: 0.86),
                                       .init(color: Theme.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Stamp(text: "\(photo.pose.title) / \(photo.date.formatted(.dateTime.month(.abbreviated).day()))",
                              color: .white)
                        Text("WEEK \(store.weekNumber(for: photo))")
                            .font(.brand(92))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                    }
                    statusBar
                }
                .padding(16)
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
        } else {
            VStack(spacing: 18) {
                Barbell(plates: 0, height: 72).frame(width: 150)
                Text("YOUR FIRST WEEK").font(.brand(46))
                Text("Your timelapse starts with one photo.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.72 }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Barbell(plates: store.photoWeekCount, height: 40).frame(width: 118)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.streak == 1 ? "1 week in a row" : "\(store.streak) weeks in a row")
                    .font(.subheadline.weight(.bold))
                Text(nextCheckInText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stamp(text: title, color: Theme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
    }

    private func focusCard(_ focus: String) -> some View {
        infoCard("Your focus") {
            Text(focus).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var comingUpCard: some View {
        infoCard("Coming up") {
            Text("Your second photo is \(daysText). That's when you'll get your first comparison, and your timelapse begins.")
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checkInsOffCard: some View {
        infoCard("AI check-ins are off") {
            Text("Your photo is saved. Turn check-ins on whenever you want feedback.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on check-ins") {
                store.profile.aiConsent = nil
                checkInPhoto = store.pendingCheckInPhoto
            }
            .font(.subheadline.weight(.bold))
            .frame(minHeight: 44)
        }
    }

    private var remindersCard: some View {
        infoCard("Reminders are off") {
            Text("A weekly nudge makes photo day much easier to remember.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on reminders") {
                Task {
                    if reminderStatus == .notDetermined {
                        await Reminders.requestAndSchedule(dates: store.upcomingCheckIns())
                        reminderStatus = await Reminders.status()
                    } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            .font(.subheadline.weight(.bold))
            .frame(minHeight: 44)
        }
    }

    /// One main action, chosen by where the user is in this week's loop.
    @ViewBuilder private var primaryAction: some View {
        Group {
            if !store.hasPhotoThisWeek {
                Button("Take this week's photo") { onCapture(nil, false) }.buttonStyle(.primary)
            } else if let pending = store.pendingCheckInPhoto {
                if !isCheckInOff {
                    Button(store.comparison(for: pending) == nil ? "Get your first check-in" : "Get this week's check-in") {
                        checkInPhoto = pending
                    }
                    .buttonStyle(.primary)
                }
            } else if let done = store.latestCheckInPhoto {
                Button("See this week's check-in") { checkInPhoto = done }.buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
