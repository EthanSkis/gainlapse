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
        await MainActor.run { ProgressStore.shared.cameraRequested = true }
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
        }
    }
}

struct RootView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions

    var body: some View {
        Group {
            if !subscriptions.hasChecked {
                ZStack {
                    AmbientBackground()
                    VStack(spacing: 18) {
                        Barbell(plates: 5, showsNext: false, height: 72).frame(width: 150)
                        ProgressView().tint(.white)
                    }
                }
            } else if !store.profile.onboardingDone {
                OnboardingView()
            } else if !subscriptions.isEntitled {
                PaywallView()
            } else {
                MainTabs()
            }
        }
        .animation(.smooth, value: store.profile.onboardingDone)
        .animation(.smooth, value: subscriptions.isEntitled)
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
    @State private var selection = Item.home
    @State private var capture: CaptureRequest?
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
        }
        .onChange(of: store.cameraRequested, initial: true) { _, requested in
            guard requested else { return }
            store.cameraRequested = false
            selection = .home
            capture = CaptureRequest()
        }
    }
}
