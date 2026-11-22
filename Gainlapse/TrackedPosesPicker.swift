import SwiftUI

/// Which angles to take each week. Front is always on; side and back are optional.
struct TrackedPosesPicker: View {
    /// Glass chips for onboarding; plain toggles inside a Settings form.
    var style = Style.chips

    enum Style { case chips, toggles }

    @Environment(ProgressStore.self) private var store

    var body: some View {
        switch style {
        case .chips:
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(Pose.allCases) { pose in chip(pose) }
                }
            }
            .sensoryFeedback(.selection, trigger: store.trackedPoses)
        case .toggles:
            ForEach(Pose.allCases) { pose in
                Toggle(pose.title, isOn: binding(pose))
                    .disabled(pose == .front)
            }
        }
    }

    private func binding(_ pose: Pose) -> Binding<Bool> {
        Binding { store.trackedPoses.contains(pose) } set: { store.setTracked(pose, $0) }
    }

    private func chip(_ pose: Pose) -> some View {
        let isOn = store.trackedPoses.contains(pose)
        return Button {
            guard pose != .front else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { store.setTracked(pose, !isOn) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.caption.weight(.bold))
                Text(pose.title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isOn ? .black : .white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: Capsule())
        .accessibilityLabel(pose == .front ? "Front, always included" : pose.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
