import SwiftUI

/// Fades and lifts a piece of a page in, a moment after the page itself arrives.
private struct StepEntrance: ViewModifier {
    let order: Int
    let isActive: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive || reduceMotion ? 0 : 22)
            .animation(.spring(response: 0.5, dampingFraction: 0.84).delay(isActive ? 0.1 + Double(order) * 0.07 : 0),
                       value: isActive)
    }
}

/// The primary button stays in one place and changes from solid black to orange glass as the orange leaves.
private struct OnboardingButtonStyle: ButtonStyle {
    let isOnOrange: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var labelColor: Color {
        if isOnOrange { return Theme.accent }
        return isEnabled ? .black : .white.opacity(0.5)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(labelColor)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.black.opacity(isOnOrange ? 1 : 0), in: Capsule())
            .contentShape(Capsule())
            .glassEffect(isOnOrange ? .identity : (isEnabled ? .regular.tint(Theme.accent).interactive() : .regular),
                         in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

struct OnboardingView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCamera = false
    @State private var isSchedulingReminder = false
    @State private var hasAppeared = false
    @State private var loadedPlates = 0
    @GestureState private var backDrag: CGFloat = 0

    private let pageCount = 4
    private var step: Int { store.profile.onboardingStep }
    private var pageAnimation: Animation { .spring(response: 0.55, dampingFraction: 0.88) }

    var body: some View {
        ZStack {
            AmbientBackground()
            orangeLayer
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            page(index)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .offset(x: pageOffset(index, width: geometry.size.width))
                                .opacity(index == step ? 1 : 0)
                                .allowsHitTesting(index == step)
                                .accessibilityHidden(index != step)
                        }
                    }
                }
                footer
            }
            header
        }
        .overlay(alignment: .leading) {
            // A left-edge swipe goes back and follows the finger, like a navigation stack.
            if step > 0 {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .updating($backDrag) { value, state, _ in state = max(value.translation.width, 0) }
                            .onEnded { value in
                                if value.translation.width > 90 || value.predictedEndTranslation.width > 220 {
                                    move(to: step - 1)
                                }
                            }
                    )
            }
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.9), value: backDrag)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .sensoryFeedback(.selection, trigger: store.profile.goal)
        .fullScreenCover(isPresented: $showCamera) {
            CaptureFlow(isOnboarding: true)
        }
        .task { await playIntro() }
    }

    private func move(to newStep: Int) {
        withAnimation(pageAnimation) { store.profile.onboardingStep = newStep }
        if newStep == 0 { Task { await loadPlates() } }
    }

    private func pageOffset(_ index: Int, width: CGFloat) -> CGFloat {
        if reduceMotion { return 0 }
        return CGFloat(index - step) * width + (index == step ? backDrag : 0)
    }

    private func isActive(_ index: Int) -> Bool { hasAppeared && index == step }

    private func entrance(_ order: Int, on index: Int) -> StepEntrance {
        StepEntrance(order: order, isActive: isActive(index), reduceMotion: reduceMotion)
    }

    private func playIntro() async {
        hasAppeared = true
        if step == 0 { await loadPlates() } else { loadedPlates = 7 }
    }

    /// Slides plates onto the bar one by one.
    private func loadPlates() async {
        if reduceMotion {
            loadedPlates = 7
            return
        }
        loadedPlates = 0
        try? await Task.sleep(for: .milliseconds(350))
        for count in 1...7 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { loadedPlates = count }
            try? await Task.sleep(for: .milliseconds(85))
        }
    }

    /// The Welcome screen's orange, which shrinks into the button when you start.
    private var orangeLayer: some View {
        Theme.accent
            .ignoresSafeArea()
            .mask {
                GeometryReader { geometry in
                    let size = geometry.size.height * 2.6
                    Circle()
                        .frame(width: size, height: size)
                        .scaleEffect(step == 0 ? 1 : 0.001)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 90)
                }
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
    }

    private var header: some View {
        VStack {
            HStack {
                GlassIconButton(symbol: "chevron.left", label: "Back") { move(to: step - 1) }
                Spacer()
                stepPlates
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            Spacer()
        }
        .opacity(step > 0 ? 1 : 0)
        .allowsHitTesting(step > 0)
        .accessibilityHidden(step == 0)
        .animation(.smooth(duration: 0.3), value: step)
    }

    /// One plate loads onto the bar with each step.
    private var stepPlates: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { index in
                let height = 34 - CGFloat(index - 1) * 7
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent)
                        .scaleEffect(y: index <= step ? 1 : 0.1)
                        .opacity(index <= step ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.15), value: step)
                }
                .frame(width: 11, height: height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step) of 3")
    }

    @ViewBuilder private func page(_ index: Int) -> some View {
        ScrollView {
            Group {
                switch index {
                case 0: welcome
                case 1: goal
                case 2: schedule
                default: firstPhoto
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, index == 0 ? 0 : 58)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: -46) {
                Text("GAIN").modifier(entrance(0, on: 0))
                Text("LAPSE").modifier(entrance(1, on: 0))
            }
            .font(.brand(150))
            .foregroundStyle(.black)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gainlapse")
            .padding(.top, 18)
            Barbell(plates: loadedPlates, showsNext: false, height: 150, color: .black)
                .padding(.horizontal, -20)
                .padding(.vertical, 22)
                .opacity(step == 0 ? 1 : 0)
            Text("One photo a week. A timelapse of every gain.")
                .font(.title2.weight(.bold))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(entrance(3, on: 0))
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.brand(62))
            .padding(.top, 14)
            .accessibilityAddTraits(.isHeader)
    }

    private var goal: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("WHAT ARE YOU WORKING TOWARD?")
                .padding(.bottom, 8)
                .modifier(entrance(0, on: 1))
            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 10) {
                    ForEach(Array(Goal.allCases.enumerated()), id: \.element.id) { order, option in
                        goalCard(option).modifier(entrance(order + 1, on: 1))
                    }
                }
            }
        }
    }

    private func goalCard(_ option: Goal) -> some View {
        let isSelected = store.profile.goal == option
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { store.profile.goal = option }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.symbol)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(isSelected ? .black : Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.headline).foregroundStyle(isSelected ? .black : .white)
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .black.opacity(0.75) : Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .glassEffect(isSelected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(),
                     in: RoundedRectangle(cornerRadius: 22))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("WHEN'S PHOTO DAY?").modifier(entrance(0, on: 2))
            Text("The same time each week keeps the light matched and the habit easy.")
                .foregroundStyle(Theme.secondaryText)
                .modifier(entrance(1, on: 2))
            ScheduleControls(usesWheel: true)
                .padding(.top, 4)
                .modifier(entrance(2, on: 2))
        }
    }

    private var firstPhoto: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("TAKE YOUR WEEK 1 PHOTO").modifier(entrance(0, on: 3))
            tip("Prop your phone up and use the timer", symbol: "timer").modifier(entrance(1, on: 3))
            tip("Pick a spot with good light you can use every week", symbol: "sun.max.fill").modifier(entrance(2, on: 3))
            tip("Your photos are private and never public", symbol: "lock.fill").modifier(entrance(3, on: 3))
        }
    }

    private func tip(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 28)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: "Get started"
        case 1, 2: "Continue"
        default: "Take first photo"
        }
    }

    private func primaryAction() {
        switch step {
        case 0, 1:
            move(to: step + 1)
        case 2:
            Task {
                isSchedulingReminder = true
                await Reminders.requestAndSchedule(dates: store.upcomingCheckIns())
                isSchedulingReminder = false
                move(to: 3)
            }
        default:
            showCamera = true
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                Text(buttonTitle)
            }
            .buttonStyle(OnboardingButtonStyle(isOnOrange: step == 0))
            .disabled((step == 1 && store.profile.goal == nil) || isSchedulingReminder)
            .animation(.smooth(duration: 0.3), value: step)
            if step == 0 {
                Text("Gainlapse is for adults. By continuing, you confirm you're 18 or older.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/// Check-in day and time, shared by onboarding and Settings.
struct ScheduleControls: View {
    var usesWheel = false

    @Environment(ProgressStore.self) private var store

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: store.profile.checkInHour,
                                                       minute: store.profile.checkInMinute)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.profile.checkInHour = parts.hour ?? 9
            store.profile.checkInMinute = parts.minute ?? 0
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in dayButton(day) }
                }
            }
            if usesWheel {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
            } else {
                HStack {
                    Text("Time")
                    Spacer()
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.profile.checkInWeekday)
    }

    private func dayButton(_ day: Int) -> some View {
        let calendar = Calendar.current
        let isSelected = store.profile.checkInWeekday == day
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { store.profile.checkInWeekday = day }
        } label: {
            Text(calendar.veryShortWeekdaySymbols[day - 1])
                .font(.headline)
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: Circle())
        .accessibilityLabel(calendar.weekdaySymbols[day - 1])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
