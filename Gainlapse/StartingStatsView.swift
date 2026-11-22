import SwiftUI

/// Right after the first photo: an optional starting weight, with measurements tucked away until asked for.
struct StartingStatsView: View {
    let onFinish: () -> Void

    @Environment(ProgressStore.self) private var store
    @State private var values: [BodyMetric: String] = [:]
    @State private var showsMeasurements = false
    @FocusState private var focused: BodyMetric?

    private var isMetric: Bool { store.usesMetric }

    private func parsed(_ metric: BodyMetric) -> Double? {
        guard let text = values[metric], let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              metric.isPlausible(value, metric: isMetric) else { return nil }
        return value
    }

    private var hasAnything: Bool { BodyMetric.allCases.contains { parsed($0) != nil } }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Stamp(text: "Week 1 locked in", color: Theme.accent)
                    // Kept to two lines so the weight field stays in view above the keyboard on smaller iPhones.
                    Text("LOG YOUR STARTING POINT")
                        .font(.brand(52))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your timelapse starts now. Optional: add your numbers to chart them next to your photos.")
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    field(.weight)
                    if showsMeasurements {
                        ForEach([BodyMetric.waist, .chest, .arms]) { metric in field(metric) }
                    } else {
                        Button {
                            withAnimation(.smooth) { showsMeasurements = true }
                            focused = .waist
                        } label: {
                            Label("Add measurements", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("Save and continue") { finish(saving: true) }
                        .buttonStyle(.primary)
                        .disabled(!hasAnything)
                    Button("Skip for now") { finish(saving: false) }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minHeight: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                // Solid, so fields scrolling underneath never show through the buttons.
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .onAppear { focused = .weight }
    }

    private func field(_ metric: BodyMetric) -> some View {
        HStack {
            Label(metric.title, systemImage: metric.symbol)
                .font(.headline)
            Spacer()
            TextField("0", text: Binding { values[metric] ?? "" } set: { values[metric] = $0 })
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title2.weight(.bold))
                .focused($focused, equals: metric)
                .frame(maxWidth: 120)
            Text(metric.unit(metric: isMetric))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .onTapGesture { focused = metric }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func finish(saving: Bool) {
        if saving {
            for metric in BodyMetric.allCases {
                if let value = parsed(metric) { store.logBody(metric, value: metric.stored(value, metric: isMetric)) }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        onFinish()
    }
}
