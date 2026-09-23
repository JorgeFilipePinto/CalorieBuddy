import SwiftUI
import Charts

/// A metric that can be plotted on the evolution chart. Each has very different units (kg,
/// kcal, ml), so the chart gives the first two selected metrics their own real-valued Y axis
/// (leading/trailing), colored to match their line, instead of forcing everything onto one
/// shared scale.
enum TrendMetric: String, CaseIterable, Identifiable {
    case weight, caloriesConsumed, caloriesBurned, water, coffee, sleepHours, bodyFatPercent, bmi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight: return "Peso"
        case .caloriesConsumed: return "Calorias Consumidas"
        case .caloriesBurned: return "Calorias Queimadas"
        case .water: return "Água"
        case .coffee: return "Café"
        case .sleepHours: return "Horas de Sono"
        case .bodyFatPercent: return "Massa Gorda"
        case .bmi: return "IMC"
        }
    }

    var color: Color {
        switch self {
        case .weight: return .purple
        case .caloriesConsumed: return .accentColor
        case .caloriesBurned: return .orange
        case .water: return .blue
        case .coffee: return .brown
        case .sleepHours: return .indigo
        case .bodyFatPercent: return .pink
        case .bmi: return .teal
        }
    }
}

/// What tapping/dragging on the chart does. The two behaviors used to fire together on every
/// tap (toggle the scale AND move the analysis line), which was confusing — now the user picks
/// one explicitly.
enum ChartInteractionMode: String, CaseIterable, Identifiable {
    case scale, analyze

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scale: return "Escala"
        case .analyze: return "Analisar"
        }
    }
}

/// General trends dashboard: pick any combination of weight, calories consumed, calories
/// burned and water, and see how they've evolved over the last N days.
struct TrendsView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// `rangeDays` uses this sentinel for "Vida Toda" (lifetime) — there's no fixed day count,
    /// so the actual plotted range is derived from the oldest data found instead.
    private static let lifetimeRange = -1

    @State private var selectedMetrics: Set<TrendMetric> = [.caloriesConsumed, .weight]
    /// The one metric (if any) given its own real-valued scale — tapping a metric's name, or its
    /// line on the chart, makes it this one, immediately replacing whichever metric had it before
    /// so the chart never accumulates more than one extra axis. Everything else shares the
    /// default percentage scale.
    @State private var scaledMetric: TrendMetric?
    /// Whether tapping the chart picks a metric's Y-axis scale, or dragging it draws the
    /// analysis line and shows every plotted metric's value for that day.
    @State private var interactionMode: ChartInteractionMode = .scale
    @State private var selectedDate: Date?
    @State private var rangeDays = 30
    @State private var isLoading = false

    /// On iPhone, a compact vertical size class means the device is rotated to landscape —
    /// switch to a full-screen chart layout for a bigger, more detailed view.
    private var isLandscapeFullScreen: Bool { verticalSizeClass == .compact }

    private var isLifetime: Bool { rangeDays == Self.lifetimeRange }

    /// How many days of Apple Health data to request. "Vida Toda" has no fixed length, so it
    /// just asks for a generously long history (10 years covers essentially anyone's data).
    private var fetchDays: Int { isLifetime ? 3650 : rangeDays }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard isLifetime else {
            return (0..<rangeDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.sorted()
        }

        let earliestHealthDay = [
            healthKit.waterLitersByDay.keys.min(),
            healthKit.caloriesBurnedByDay.keys.min(),
            healthKit.caffeineMgByDay.keys.min(),
            healthKit.sleepHoursByDay.keys.min(),
            healthKit.weightHistory.map { calendar.startOfDay(for: $0.date) }.min(),
            healthKit.bodyFatHistory.map { calendar.startOfDay(for: $0.date) }.min(),
            healthKit.bmiHistory.map { calendar.startOfDay(for: $0.date) }.min()
        ].compactMap { $0 }.min()
        let earliestFoodDay = store.allDays.last
        guard let earliest = [earliestHealthDay, earliestFoodDay].compactMap({ $0 }).min() else { return [today] }

        var result: [Date] = []
        var cursor = earliest
        while cursor <= today {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    var body: some View {
        Group {
            if isLandscapeFullScreen {
                fullScreenLayout
            } else {
                portraitLayout
            }
        }
        .navigationTitle("Evolução")
        .navigationBarHidden(isLandscapeFullScreen)
        .task(id: rangeDays) {
            isLoading = true
            await healthKit.requestAuthorization()
            await healthKit.refresh(days: fetchDays)
            isLoading = false
        }
        .refreshable {
            await healthKit.refresh(days: fetchDays)
        }
    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView("A carregar dados de \(rangeDaysLabel)...")
            Spacer()
        }
        .padding(.vertical, 24)
    }

    private var rangeDaysLabel: String {
        if isLifetime { return "toda a vida" }
        switch rangeDays {
        case 7: return "7 dias"
        case 30: return "30 dias"
        case 90: return "90 dias"
        case 182: return "6 meses"
        case 365: return "1 ano"
        case 730: return "2 anos"
        default: return "\(rangeDays) dias"
        }
    }

    private var portraitLayout: some View {
        List {
            Section {
                Picker("Período", selection: $rangeDays) {
                    Text("7 dias").tag(7)
                    Text("30 dias").tag(30)
                    Text("90 dias").tag(90)
                    Text("6 meses").tag(182)
                    Text("1 ano").tag(365)
                    Text("2 anos").tag(730)
                    Text("Vida Toda").tag(Self.lifetimeRange)
                }
                .pickerStyle(.menu)

                ForEach(TrendMetric.allCases) { metric in
                    HStack {
                        Button {
                            toggleRealScale(for: metric)
                        } label: {
                            HStack {
                                Label {
                                    Text(metric.label)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(metric.color)
                                }
                                if scaledMetric == metric {
                                    Text("escala própria")
                                        .font(.caption2)
                                        .foregroundStyle(metric.color)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!selectedMetrics.contains(metric))

                        Spacer()
                        Toggle("", isOn: binding(for: metric)).labelsHidden()
                    }
                }
            } header: {
                Text("Métricas")
            } footer: {
                Text("Toca no nome de uma métrica, ou na sua linha no gráfico, para lhe dares escala própria (cor a condizer) — só uma de cada vez, a mais recente substitui a anterior. Por defeito, todas partilham uma escala em percentagem.")
            }

            Section {
                if selectedMetrics.isEmpty {
                    ContentUnavailableView(
                        "Escolhe uma Métrica",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Seleciona pelo menos uma métrica para ver a evolução.")
                    )
                } else if isLoading {
                    loadingPlaceholder
                } else {
                    interactionModePicker
                        .padding(.bottom, 4)

                    chart
                        .frame(height: 340)
                        .padding(.vertical, 4)
                    if let selectedDate {
                        selectionSummary(for: selectedDate)
                    } else {
                        Text(interactionModeHint + " Roda o telemóvel para o ecrã inteiro.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Evolução")
            } footer: {
                if !selectedMetrics.isEmpty {
                    Text("Por defeito o eixo mostra a % de cada métrica dentro do período. Em modo Escala, toca no nome de uma métrica acima, ou na sua linha no gráfico, para lhe dares escala própria. Em modo Analisar, arrasta no gráfico para ver os valores exatos de todas as métricas num dia.")
                }
            }
        }
    }

    private var fullScreenLayout: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TrendMetric.allCases) { metric in
                        metricChip(metric)
                    }
                }
                .padding(.horizontal)
            }

            if selectedMetrics.isEmpty {
                Spacer()
                Text("Seleciona pelo menos uma métrica.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if isLoading {
                Spacer()
                loadingPlaceholder
                Spacer()
            } else {
                interactionModePicker
                    .padding(.horizontal)

                chart
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
                Group {
                    if let selectedDate {
                        selectionSummary(for: selectedDate)
                    } else {
                        Text(interactionModeHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .frame(height: 70)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var interactionModePicker: some View {
        Picker("Interação", selection: $interactionMode) {
            ForEach(ChartInteractionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: interactionMode) { _, newMode in
            if newMode != .analyze { selectedDate = nil }
        }
    }

    /// Hint shown below the chart while nothing is selected, explaining what a tap/drag will do
    /// in the current interaction mode.
    private var interactionModeHint: String {
        switch interactionMode {
        case .scale:
            return "Toca no nome de uma métrica, ou na sua linha no gráfico, para lhe dares escala própria."
        case .analyze:
            return "Arrasta no gráfico para ver os valores de todas as métricas num dia."
        }
    }

    private func metricChip(_ metric: TrendMetric) -> some View {
        let isOn = selectedMetrics.contains(metric)
        return Button {
            if isOn { selectedMetrics.remove(metric) } else { selectedMetrics.insert(metric) }
        } label: {
            Text(metric.label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? metric.color.opacity(0.25) : Color(.secondarySystemBackground))
                .foregroundStyle(isOn ? metric.color : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func binding(for metric: TrendMetric) -> Binding<Bool> {
        Binding(
            get: { selectedMetrics.contains(metric) },
            set: { isOn in
                if isOn {
                    selectedMetrics.insert(metric)
                } else {
                    selectedMetrics.remove(metric)
                    if scaledMetric == metric { scaledMetric = nil }
                }
            }
        )
    }

    /// Gives `metric` the real-valued scale, immediately taking it away from whichever metric
    /// had it before (tapping the metric that already has it reverts to the shared percentage
    /// scale instead).
    private func toggleRealScale(for metric: TrendMetric) {
        scaledMetric = (scaledMetric == metric) ? nil : metric
    }

    private func rawValue(_ metric: TrendMetric, on day: Date) -> Double? {
        switch metric {
        case .weight:
            return healthKit.weightKG(on: day)
        case .caloriesConsumed:
            let total = store.totalCalories(on: day)
            return total > 0 ? Double(total) : nil
        case .caloriesBurned:
            let burned = healthKit.caloriesBurned(on: day)
            return burned > 0 ? Double(burned) : nil
        case .water:
            let liters = healthKit.waterLiters(on: day)
            return liters > 0 ? liters * 1000 : nil
        case .coffee:
            let count = healthKit.coffeeCount(on: day)
            return count > 0 ? Double(count) : nil
        case .sleepHours:
            let hours = healthKit.sleepHours(on: day)
            return hours > 0 ? hours : nil
        case .bodyFatPercent:
            return healthKit.bodyFatPercent(on: day).map { $0 * 100 }
        case .bmi:
            return healthKit.bmi(on: day)
        }
    }

    /// A metric's raw (date, value) points in the visible range — `nil` days are simply skipped.
    private func rawPoints(for metric: TrendMetric) -> [(date: Date, value: Double)] {
        days.compactMap { day in rawValue(metric, on: day).map { (day, $0) } }
    }

    /// A little padding above/below a metric's min/max so its line doesn't touch the axis edges,
    /// and a sane fallback range when there's only one point (or all points are equal).
    private func yDomain(for points: [(date: Date, value: Double)]) -> ClosedRange<Double> {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max(), high > low else {
            let value = points.first?.value ?? 0
            return (value - 1)...(value + 1)
        }
        let padding = (high - low) * 0.1
        return (low - padding)...(high + padding)
    }

    /// The shared date range every layered chart below uses, so their lines line up horizontally
    /// despite each having its own, independent Y scale.
    private var xDomain: ClosedRange<Date> {
        guard let first = days.first, let last = days.last, first <= last else {
            return Date()...Date()
        }
        return first...last
    }

    /// Width reserved for the one metric currently on the real-valued scale to draw its own
    /// custom axis label column, just to the left of the plot.
    private let axisColumnWidth: CGFloat = 46

    /// Points for a metric, normalized to 0...1 across its own padded domain (the same padding
    /// `yDomain(for:)` gives a real-valued scale) — used by the shared percentage scale, and to
    /// compare against a tapped point's fraction when hit-testing which line was tapped, so both
    /// use the same 0...1 definition regardless of which scale a metric happens to be on.
    private func normalizedPoints(for metric: TrendMetric) -> [(date: Date, value: Double)] {
        let raw = rawPoints(for: metric)
        let domain = yDomain(for: raw)
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return raw.map { ($0.date, 0.5) } }
        return raw.map { ($0.date, ($0.value - domain.lowerBound) / span) }
    }

    /// The chart layers the shared percentage scale (every metric without its own scale) below
    /// a single real-valued `Chart` for the one metric the user tapped to give its own scale —
    /// that layer gets a hand-drawn, colored axis column (Swift Charts only offers two built-in
    /// axis positions), so only ever one extra axis shows at a time.
    private var chart: some View {
        let metrics = TrendMetric.allCases.filter(selectedMetrics.contains)
        let realMetric = scaledMetric.flatMap { metrics.contains($0) ? $0 : nil }
        let percentMetrics = metrics.filter { $0 != realMetric }

        return ZStack {
            if !percentMetrics.isEmpty {
                percentLayer(percentMetrics, isTopmost: realMetric == nil)
            }
            if let realMetric {
                metricLayer(realMetric, isTopmost: true)
            }
        }
        .padding(.leading, realMetric != nil ? axisColumnWidth : 0)
    }

    /// Finds whichever currently-plotted metric's line passes closest to a tapped point (by date,
    /// then by how high/low its line sits there) and gives it the real scale — an alternative to
    /// tapping the metric's name in the "Métricas" list.
    private func handleLineTap(at location: CGPoint, proxy: ChartProxy, domain: ClosedRange<Double>) {
        let metrics = TrendMetric.allCases.filter(selectedMetrics.contains)
        guard !metrics.isEmpty,
              let rawValue = proxy.value(atY: location.y, as: Double.self),
              let tappedDate = proxy.value(atX: location.x, as: Date.self) else { return }
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return }
        let tappedFraction = (rawValue - domain.lowerBound) / span

        var closestMetric: TrendMetric?
        var closestDistance = Double.greatestFiniteMagnitude
        for metric in metrics {
            guard let nearest = normalizedPoints(for: metric).min(by: {
                abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
            }) else { continue }
            let distance = abs(nearest.value - tappedFraction)
            if distance < closestDistance {
                closestDistance = distance
                closestMetric = metric
            }
        }

        if let closestMetric {
            toggleRealScale(for: closestMetric)
        }
    }

    @ViewBuilder
    private func percentLayer(_ metrics: [TrendMetric], isTopmost: Bool) -> some View {
        let base = Chart {
            ForEach(metrics) { metric in
                ForEach(normalizedPoints(for: metric), id: \.date) { point in
                    LineMark(
                        x: .value("Dia", point.date, unit: .day),
                        y: .value("Valor", point.value)
                    )
                    .foregroundStyle(by: .value("Métrica", metric.label))
                    .symbol(by: .value("Métrica", metric.label))
                }
            }
            if isTopmost, let selectedDate {
                RuleMark(x: .value("Selecionado", selectedDate, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale(
            domain: metrics.map(\.label),
            range: metrics.map(\.color)
        )
        // The "Métricas" list (portrait) and the metric chips (fullscreen) already show each
        // metric's color + name, so Swift Charts' own automatic legend is redundant — and with
        // long Portuguese labels it has no room to lay itself out, so its entries overlap.
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine()
                if let fraction = value.as(Double.self) {
                    AxisValueLabel {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2)
                    }
                }
            }
        }

        if isTopmost, interactionMode == .scale {
            // Only attach the tap-to-scale gesture in Escala mode — in Analisar mode no
            // competing gesture recognizer should sit on top of the chart's own drag-to-select
            // gesture, or it blocks the drag from reaching it.
            withXAxisMarks(base)
                .chartXSelection(value: .constant(nil as Date?))
                .chartOverlay { proxy in
                    GeometryReader { _ in
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                SpatialTapGesture().onEnded { tap in
                                    handleLineTap(at: tap.location, proxy: proxy, domain: 0...1)
                                }
                            )
                    }
                }
        } else if isTopmost {
            withXAxisMarks(base)
                .chartXSelection(value: $selectedDate)
        } else {
            base.chartXAxis(.hidden)
        }
    }

    /// The shared X-axis tick styling used by whichever layer is currently topmost.
    private func withXAxisMarks<V: View>(_ view: V) -> some View {
        view.chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xAxisTickCount)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: xAxisDateFormat, centered: true)
            }
        }
    }

    @ViewBuilder
    private func metricLayer(_ metric: TrendMetric, isTopmost: Bool) -> some View {
        let points = rawPoints(for: metric)
        let domain = yDomain(for: points)
        let base = Chart {
            ForEach(points, id: \.date) { point in
                LineMark(
                    x: .value("Dia", point.date, unit: .day),
                    y: .value(metric.label, point.value)
                )
                .foregroundStyle(metric.color)
                .symbol(Circle())
            }
            if isTopmost, let selectedDate {
                RuleMark(x: .value("Selecionado", selectedDate, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { _ in
                ZStack {
                    // Only attach the tap-to-scale gesture in Escala mode — in Analisar mode no
                    // competing gesture recognizer should sit on top of the chart's own
                    // drag-to-select gesture, or it blocks the drag from reaching it.
                    if isTopmost, interactionMode == .scale {
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                SpatialTapGesture().onEnded { tap in
                                    handleLineTap(at: tap.location, proxy: proxy, domain: domain)
                                }
                            )
                    }
                    ForEach(referenceTicks(for: domain), id: \.self) { tickValue in
                        if let yPosition = proxy.position(forY: tickValue) {
                            Text(formatted(tickValue, for: metric))
                                .font(.caption2)
                                .foregroundStyle(metric.color)
                                .fixedSize()
                                .position(x: -axisColumnWidth * 0.5, y: yPosition)
                        }
                    }
                }
            }
        }

        if isTopmost, interactionMode == .scale {
            withXAxisMarks(base)
                .chartXSelection(value: .constant(nil as Date?))
        } else if isTopmost {
            withXAxisMarks(base)
                .chartXSelection(value: $selectedDate)
        } else {
            base.chartXAxis(.hidden)
        }
    }

    /// Three reference values (max, mid, min) shown on a metric's own custom axis column.
    private func referenceTicks(for domain: ClosedRange<Double>) -> [Double] {
        [domain.upperBound, (domain.lowerBound + domain.upperBound) / 2, domain.lowerBound]
    }

    /// How many labelled ticks the X axis should aim for — dense enough to read dates without
    /// crowding them, however wide the selected period is.
    private var xAxisTickCount: Int {
        rangeDays <= 7 ? rangeDays : 6
    }

    /// The X axis date format: short ranges show day + weekday, longer ones fall back to
    /// month/year so labels don't overlap.
    private var xAxisDateFormat: Date.FormatStyle {
        switch rangeDays {
        case ...7:
            return .dateTime.weekday(.abbreviated).day()
        case ...90:
            return .dateTime.day().month(.abbreviated)
        default:
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func selectionSummary(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.bold())
            ForEach(TrendMetric.allCases.filter(selectedMetrics.contains)) { metric in
                HStack {
                    Circle().fill(metric.color).frame(width: 8, height: 8)
                    Text(metric.label)
                    Spacer()
                    if let value = rawValue(metric, on: date) {
                        Text(formatted(value, for: metric))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Sem dados")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    private func formatted(_ value: Double, for metric: TrendMetric) -> String {
        switch metric {
        case .weight:
            return value.formatted(.number.precision(.fractionLength(1))) + " kg"
        case .caloriesConsumed, .caloriesBurned:
            return "\(Int(value.rounded())) kcal"
        case .water:
            return "\(Int(value.rounded())) ml"
        case .coffee:
            return "\(Int(value.rounded())) cafés"
        case .sleepHours:
            return value.formatted(.number.precision(.fractionLength(1))) + " h"
        case .bodyFatPercent:
            return value.formatted(.number.precision(.fractionLength(1))) + " %"
        case .bmi:
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }
}

#Preview {
    NavigationStack {
        TrendsView()
    }
    .environment(DataStore())
    .environment(HealthKitManager())
}
