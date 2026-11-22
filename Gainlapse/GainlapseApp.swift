import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let isRecap = response.notification.request.content.userInfo["kind"] as? String == "recap"
        await MainActor.run {
            if isRecap { ProgressStore.shared.recapRequested = true } else { ProgressStore.shared.cameraRequested = true }
        }
    }
}

@main
struct GainlapseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ProgressStore.shared
    @State private var subscriptions = Subscriptions()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(subscriptions)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await subscriptions.start() }
                // Links from the home screen widget open the exact thing it shows.
                .onOpenURL { url in
                    switch url.host() {
                    case "photo": store.cameraRequested = true
                    case "log-weight": store.weightLogRequested = true
                    #if DEBUG
                    case "shot": store.debugShot = url.lastPathComponent
                    #endif
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions

    var body: some View {
        Group {
            // Onboarding never waits on the App Store; only the choice between the app and the paywall does.
            if !store.profile.onboardingDone {
                OnboardingView()
            } else if !subscriptions.hasChecked {
                ZStack {
                    AmbientBackground()
                    VStack(spacing: 18) {
                        Barbell(plates: 5, showsNext: false, height: 72).frame(width: 150)
                        ProgressView().tint(.white)
                    }
                }
            } else if !subscriptions.isEntitled && store.profile.seenIntroPaywall != true {
                // Shown once after onboarding. Closing it opens the free app.
                PaywallView(context: .intro) { store.profile.seenIntroPaywall = true }
            } else {
                MainTabs()
            }
        }
        .animation(.smooth, value: store.profile.onboardingDone)
        .animation(.smooth, value: subscriptions.isEntitled)
        .animation(.smooth, value: store.profile.seenIntroPaywall)
    }
}

struct RecapID: Identifiable {
    let weeks: Int
    var id: Int { weeks }
}

extension MainTabs {
    static func latestReachedRecap(_ store: ProgressStore) -> Int? {
        ProgressStore.recapWeeks.filter { $0 <= store.photoWeekCount }.max()
    }
}

struct CaptureRequest: Identifiable {
    let id = UUID()
    var pose: Pose?
    var isRetake = false
}

/// Home on the left, the create action in the middle, Profile on the right.
struct MainTabs: View {
    private enum Item: Int { case home, capture, profile }

    @Environment(ProgressStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Item.home
    @State private var capture: CaptureRequest?
    @State private var logWeight = false
    @State private var recapWeeks: Int?
    #if DEBUG
    @State private var debugShare = false
    #endif
    @State private var homeTop = 0
    @State private var profileTop = 0

    /// Tapping the current tab returns to its top.
    private var tabSelection: Binding<Item> {
        Binding {
            selection
        } set: { item in
            if item == selection {
                if item == .home { homeTop += 1 } else if item == .profile { profileTop += 1 }
            } else {
                selection = item
            }
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: Item.home) {
                HomeView(scrollToTop: homeTop) { pose, isRetake in
                    capture = CaptureRequest(pose: pose, isRetake: isRetake)
                }
            }
            Tab("Photo", systemImage: "camera.fill", value: Item.capture) {
                AmbientBackground()
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: Item.profile) {
                ProfileView(scrollToTop: profileTop)
            }
        }
        // The middle tab opens the camera instead of a page, then hands the tab bar straight back,
        // so closing the camera returns to the tab the user came from.
        .onChange(of: selection) { previous, item in
            guard item == .capture else { return }
            selection = previous
            // Opens on a pose that's still missing, so it doesn't replace a photo by accident.
            capture = CaptureRequest(pose: store.hasPhotoThisWeek ? store.missingPosesThisWeek.first : nil)
        }
        .fullScreenCover(item: $capture) { request in
            CaptureFlow(isOnboarding: false, initialPose: request.pose, isRetake: request.isRetake)
        }
        .task(id: store.photos.count) {
            await Reminders.reschedule(dates: store.upcomingCheckIns())
            if let weeks = store.pendingRecap { await Reminders.scheduleRecap(weeks: weeks) }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.syncHealth() }
        }
        .sheet(isPresented: $logWeight) { LogBodySheet(metric: .weight) }
        .sheet(item: Binding(get: { recapWeeks.map(RecapID.init) }, set: { recapWeeks = $0?.weeks })) { recap in
            RecapView(weeks: recap.weeks)
        }
        #if DEBUG
        .sheet(isPresented: $debugShare) { ShareProgressSheet(pose: .front) }
        .onChange(of: store.debugShot, initial: true) { _, shot in
            switch shot {
            case "home": selection = .home
            case "profile": selection = .profile
            case "recap": selection = .home; recapWeeks = Self.latestReachedRecap(store)
            case "share": selection = .profile; debugShare = true
            default: break
            }
        }
        #endif
        .onChange(of: store.weightLogRequested, initial: true) { _, requested in
            guard requested else { return }
            store.weightLogRequested = false
            selection = .home
            logWeight = true
        }
        .onChange(of: store.recapRequested, initial: true) { _, requested in
            guard requested else { return }
            store.recapRequested = false
            selection = .home
            recapWeeks = store.pendingRecap ?? Self.latestReachedRecap(store)
        }
        .onChange(of: store.cameraRequested, initial: true) { _, requested in
            guard requested else { return }
            store.cameraRequested = false
            selection = .home
            capture = CaptureRequest()
        }
    }
}
