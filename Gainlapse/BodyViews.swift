import Charts
import SwiftUI

/// A quick bottom sheet for logging today's weight or a measurement. Swipe down to close.
struct LogBodySheet: View {
    @State var metric: BodyMetric

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isMetric: Bool { store.usesMetric }
    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var isValid: Bool { value.map { metric.isPlausible($0, metric: isMetric) } ?? false }

    private var placeholder: String {
        guard let last = store.latestEntry(for: metric) else { return "0" }
        return metric.display(last.value, metric: isMetric).formatted(.number.precision(.fractionLength(1)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("What to log", selection: $metric) {
                    ForEach(BodyMetric.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(placeholder, text: $text)
                        .font(.brand(88))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .fixedSize()
                        .accessibilityLabel("\(metric.title) in \(metric.unit(metric: isMetric))")
                    Text(metric.unit(metric: isMetric))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                if let last = store.latestEntry(for: metric) {
                    Text("Last: \(metric.format(last.value, metric: isMetric)), \(last.date.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text(metric == .weight ? "Weigh in at the same time of day, like after waking up."
                                           : "Measure at the widest point, with the tape level.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .safeAreaInset(edge: .bottom) {
                Button("Save") { save() }
                    .buttonStyle(.primary)
                    .disabled(!isValid)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(AmbientBackground())
            .navigationTitle("Log \(metric.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .onChange(of: metric) { text = "" }
            .sensoryFeedback(.selection, trigger: metric)
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let value, isValid else { return }
        store.logBody(metric, value: metric.stored(value, metric: isMetric))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// The latest value, the change since the first entry, and a chart of every entry.
struct BodyTrendCard: View {
    let metric: BodyMetric
    let onLog: () -> Void

    @Environment(ProgressStore.self) private var store

    private var isMetric: Bool { store.usesMetric }
    private var entries: [BodyEntry] { store.entries(for: metric) }

    @State private var showsHistory = false
    @State private var isConnectingHealth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Stamp(text: metric.title, color: Theme.accent)
                Spacer()
                Button(action: onLog) {
                    Label("Log", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("Log \(metric.title.lowercased())")
            }
            if let latest = entries.last {
                Button { showsHistory = true } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(metric.display(latest.value, metric: isMetric).formatted(.number.precision(.fractionLength(1))))
                                .font(.brand(48))
                            Text(metric.unit(metric: isMetric))
                                .font(.headline)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            if let change = store.trendChange(for: metric) {
                                Text("\(metric.format(change, metric: isMetric, signed: true)) since start")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        if entries.count >= 2 {
                            chart
                        } else {
                            Text("Log it again on another day and your trend starts here.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows every entry, where you can fix or delete one")
            } else {
                Text(metric == .weight
                     ? "Weigh in a few times a week. Your trend sits next to your photos, so you can see what the scale misses."
                     : "Measure every couple of weeks to see the change in numbers too.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if metric == .weight, HealthSync.isAvailable, store.profile.healthSync != true {
                Button {
                    Task {
                        isConnectingHealth = true
                        await store.connectHealth()
                        isConnectingHealth = false
                    }
                } label: {
                    Label(isConnectingHealth ? "Connecting…" : "Sync weight from Apple Health", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 36)
                }
                .disabled(isConnectingHealth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .sheet(isPresented: $showsHistory) { BodyHistorySheet(metric: metric) }
    }

    /// Weight shows a smoothed 7-day line over faint daily dots. Measurements are sparse, so they plot directly.
    private var chart: some View {
        let smoothed = metric == .weight
        let points = (smoothed ? store.trend(for: metric) : entries.map { ($0.date, $0.value) })
            .map { (date: $0.0, value: metric.display($0.1, metric: isMetric)) }
        let raw = entries.map { (date: $0.date, value: metric.display($0.value, metric: isMetric)) }
        let values = raw.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.15, metric.isLength ? 0.5 : 1)
        return Chart {
            if smoothed {
                ForEach(Array(raw.enumerated()), id: \.offset) { _, point in
                    PointMark(x: .value("Date", point.date), y: .value("Daily", point.value))
                        .foregroundStyle(Theme.secondaryText.opacity(0.45))
                        .symbolSize(14)
                }
            }
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Base", low - pad),
                         yEnd: .value(metric.title, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if index == points.count - 1 {
                    PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(60)
                }
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(height: 130)
        .accessibilityLabel(smoothed ? "\(metric.title), 7-day average over time" : "\(metric.title) over time")
    }
}

/// Every entry for one thing, newest first. Tap to fix a number, swipe to delete.
struct BodyHistorySheet: View {
    let metric: BodyMetric

    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BodyEntry?
    @State private var text = ""

    private var isMetric: Bool { store.usesMetric }

    var body: some View {
        NavigationStack {
            List {
                if metric == .weight, store.profile.healthSync == true {
                    Section {
                        Label("New weigh-ins from Apple Health are added automatically.", systemImage: "heart.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(store.entries(for: metric).reversed()) { entry in
                    Button {
                        text = metric.display(entry.value, metric: isMetric).formatted(.number.precision(.fractionLength(1)).grouping(.never))
                        editing = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                if entry.healthID != nil {
                                    Text("From Apple Health").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                            Text(metric.format(entry.value, metric: isMetric)).font(.headline)
                        }
                        .foregroundStyle(.white)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.deleteBodyEntry(entry) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .overlay {
                if store.entries(for: metric).isEmpty {
                    ContentUnavailableView("Nothing logged", systemImage: metric.symbol)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .alert("Fix this entry", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField(metric.unit(metric: isMetric), text: $text).keyboardType(.decimalPad)
                Button("Save") {
                    if let entry = editing, let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                       metric.isPlausible(value, metric: isMetric) {
                        store.updateBodyEntry(entry, value: metric.stored(value, metric: isMetric))
                    }
                    editing = nil
                }
                Button("Delete", role: .destructive) {
                    if let entry = editing { store.deleteBodyEntry(entry) }
                    editing = nil
                }
                Button("Cancel", role: .cancel) { editing = nil }
            } message: {
                if let entry = editing {
                    Text("\(metric.title) on \(entry.date.formatted(date: .abbreviated, time: .omitted)), in \(metric.unit(metric: isMetric)).")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Waist, chest and arms in one row: the latest number, or a prompt to add the first one.
struct MeasurementsRow: View {
    let onLog: (BodyMetric) -> Void
    @Environment(ProgressStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            ForEach([BodyMetric.waist, .chest, .arms]) { metric in
                Button { onLog(metric) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title.uppercased())
                            .font(.stamp(11))
                            .tracking(1)
                            .foregroundStyle(Theme.secondaryText)
                        if let latest = store.latestEntry(for: metric) {
                            Text(metric.format(latest.value, metric: store.usesMetric))
                                .font(.headline)
                                .foregroundStyle(.white)
                            if let change = store.totalChange(for: metric) {
                                Text(metric.format(change, metric: store.usesMetric, signed: true))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        } else {
                            Label("Add", systemImage: "plus")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel(accessibilityText(metric))
            }
        }
    }

    private func accessibilityText(_ metric: BodyMetric) -> String {
        guard let latest = store.latestEntry(for: metric) else { return "Add \(metric.title.lowercased())" }
        return "\(metric.title), \(metric.format(latest.value, metric: store.usesMetric)). Log new value."
    }
}

/// Number changes between two photo dates, shown beside a comparison.
struct StatChangesRow: View {
    let from: Date
    let to: Date
    @Environment(ProgressStore.self) private var store

    private var changes: [(BodyMetric, Double)] {
        BodyMetric.allCases.compactMap { metric in
            store.change(for: metric, from: from, to: to).map { (metric, $0) }
        }
    }

    var body: some View {
        if !changes.isEmpty {
            HStack(spacing: 8) {
                ForEach(changes, id: \.0) { metric, change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title.uppercased()).font(.stamp(11)).tracking(1).foregroundStyle(Theme.secondaryText)
                        Text(metric.format(change, metric: store.usesMetric, signed: true))
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
