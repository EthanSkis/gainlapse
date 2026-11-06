import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var restoreMessage: String?
    #if DEBUG
    @State private var confirmStartOver = false
    #endif

    private var goal: Binding<Goal> {
        Binding { store.profile.goal ?? .justStarted } set: { store.profile.goal = $0 }
    }

    private var aiEnabled: Binding<Bool> {
        Binding { store.profile.aiConsent == true } set: { store.profile.aiConsent = $0 }
    }

    private var scheduleKey: String {
        "\(store.profile.checkInWeekday)-\(store.profile.checkInHour)-\(store.profile.checkInMinute)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    ScheduleControls()
                }
                Section {
                    Picker("Goal", selection: goal) {
                        ForEach(Goal.allCases) { option in Text(option.title).tag(option) }
                    }
                }
                Section {
                    Toggle("AI check-ins", isOn: aiEnabled)
                } footer: {
                    Text("When on, your photos are sent for each check-in. When off, photos aren't sent anywhere.")
                }
                Section("Subscription") {
                    Button("Manage subscription") {
                        Task {
                            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                            try? await AppStore.showManageSubscriptions(in: scene)
                        }
                    }
                    Button("Restore purchases") {
                        Task {
                            do {
                                try await subscriptions.restore()
                                restoreMessage = subscriptions.isEntitled
                                    ? "Your subscription is active." : "No active subscription was found."
                            } catch {
                                restoreMessage = "Purchases couldn't be restored. Please try again."
                            }
                        }
                    }
                }
                Section("Privacy") {
                    NavigationLink("How your photos are handled") { PrivacyView() }
                    Link("Help and support", destination: Backend.supportURL)
                    Button("Delete all photos", role: .destructive) { confirmDelete = true }
                        .disabled(store.photos.isEmpty)
                }
                #if DEBUG
                Section {
                    Button("Skip to next photo week") {
                        store.skipToNextPhotoWeek()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(store.photos.isEmpty)
                    Button("Start over from the beginning", role: .destructive) { confirmStartOver = true }
                } header: {
                    Text("Test build only")
                } footer: {
                    Text("Skip moves your photos back in time, so you can take the next one and get a comparison now. Start over erases everything and returns to the Welcome screen.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .onChange(of: scheduleKey) {
                Task {
                    await Reminders.reschedule(dates: store.upcomingCheckIns())
                }
            }
            #if DEBUG
            .alert("Start over?", isPresented: $confirmStartOver) {
                Button("Erase everything", role: .destructive) {
                    store.startOver()
                    subscriptions.revokePreviewEntitlement()
                    Task { await Reminders.cancelAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases every photo, check-in and setting in this test build and returns to the Welcome screen. It can't be undone.")
            }
            #endif
            .alert("Delete all photos?", isPresented: $confirmDelete) {
                Button("Delete everything", role: .destructive) {
                    store.deleteAllPhotos()
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every photo and check-in from this phone. It can't be undone.")
            }
            .alert("Restore purchases", isPresented: Binding(get: { restoreMessage != nil },
                                                             set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }
}

struct PrivacyView: View {
    /// On the paywall, Settings is out of reach, so deleting has to be available here.
    var showsDelete = false

    @Environment(ProgressStore.self) private var store
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("On your phone", "Your photos are saved inside Gainlapse, not in your photo library. They can be included in your iCloud or computer backups if those are on. Nothing is public and there's no feed.")
                section("AI check-ins", "If you allow check-ins, this week's photo and your earlier photo go to the Gainlapse server and to Anthropic's Claude AI to write your feedback. Gainlapse doesn't keep them on its server. You can turn this off in Settings.")
                section("Sharing", "A photo or video only leaves Gainlapse if you export it and choose where it goes.")
                section("Deleting", "Delete all photos removes every photo and check-in from this phone straight away.")
                Link("Read the full privacy policy", destination: Backend.privacyURL)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                if showsDelete && !store.photos.isEmpty {
                    Button("Delete all photos", role: .destructive) { confirmDelete = true }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Your privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all photos?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) {
                store.deleteAllPhotos()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every photo and check-in from this phone. It can't be undone.")
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(Theme.secondaryText)
        }
    }
}
