import SwiftUI

// MARK: - Combined values (app + Apple Health)

/// One value of a body metric, from the app's own log or from Apple Health (a smart scale).
struct BodyMetricReading: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
    /// The entry in the app's database, when the value came from there.
    let measurement: BodyMeasurement?
    /// Written to Apple Health by this app — still deletable from here.
    var isFromThisApp = false
    var isFromHealth: Bool { measurement == nil }
    /// Values from a scale or another app can only be deleted in the Health app itself.
    var isDeletable: Bool { measurement != nil || isFromThisApp }
    /// Shown under the date: where the value came from, when it wasn't typed in this app.
    var sourceLabel: String? { isFromHealth && !isFromThisApp ? "app Saúde" : nil }
}

extension BodyMetric {
    var color: Color {
        switch self {
        case .bodyFat: return .orange
        case .muscleMass: return .purple
        case .leanMass: return .indigo
        case .visceralFat: return .red
        default: return .blue
        }
    }

    static var composition: [BodyMetric] { allCases.filter { !$0.isCircumference } }
    static var circumferences: [BodyMetric] { allCases.filter(\.isCircumference) }

    /// "24,5 %", "38,2 kg", "9", "84,0 cm".
    func formatted(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(self == .visceralFat ? 0 : 1)))
        return unitLabel.isEmpty ? number : "\(number) \(unitLabel)"
    }
}

@MainActor
extension DataStore {
    /// Every reading of `metric`, most recent first: the app's own entries plus, for the metrics
    /// Apple Health has (body fat, lean mass, waist), what Health holds — written by this app or by
    /// a smart scale.
    func readings(of metric: BodyMetric, healthKit: HealthKitManager) -> [BodyMetricReading] {
        var readings = bodyMeasurements(of: metric).map {
            BodyMetricReading(id: $0.id, date: $0.date, value: $0.value, measurement: $0)
        }
        let fromHealth: [HealthKitManager.QuantitySample]
        switch metric {
        case .bodyFat: fromHealth = healthKit.bodyFatHistory
        case .leanMass: fromHealth = healthKit.leanMassHistory
        case .waist: fromHealth = healthKit.waistHistory
        default: fromHealth = []
        }
        // Health stores body fat as a fraction (0,245); the app shows it as a percentage.
        let scale = metric == .bodyFat ? 100.0 : 1.0
        readings += fromHealth.map {
            BodyMetricReading(id: $0.id, date: $0.date, value: $0.value * scale, measurement: nil, isFromThisApp: $0.isFromThisApp)
        }
        return readings.sorted { $0.date > $1.date }
    }
}

// MARK: - Sections shown in Saúde

/// "Composição Corporal" or "Medidas Corporais", for the Saúde tab's list. Composition lists every
/// metric; the tape measurements are one row (latest values as subtitle) that opens
/// `BodyMeasurementsView`. Logging happens from the "Registo de Medidas" area
/// (`BodyMeasurementLogCard`).
struct BodyCompositionSections: View {
    enum Part { case composition, circumferences }

    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    let part: Part

    var body: some View {
        switch part {
        case .composition:
            Section {
                bmiRow
                ForEach(BodyMetric.composition) { metric in
                    BodyMetricRow(metric: metric)
                }
            } header: {
                Text("Composição Corporal")
            } footer: {
                Text("A massa gorda e a massa magra são guardadas na app Saúde (e lidas de lá, incluindo as de uma balança inteligente). A massa muscular e a gordura visceral não existem na app Saúde, por isso ficam na app. O IMC é calculado a partir do peso e da altura.")
            }
        case .circumferences:
            Section {
                NavigationLink {
                    BodyMeasurementsView()
                } label: {
                    measurementsSummaryRow
                }
            } footer: {
                Text("Pescoço, peito, braço, cintura, anca, coxa e gémeo — toca para ver cada medida, o histórico e como medir.")
            }
        }
    }

    /// "Medidas Corporais" with the current value of each measurement as the subtitle.
    private var measurementsSummaryRow: some View {
        let latest = BodyMetric.circumferences.compactMap { metric in
            store.readings(of: metric, healthKit: healthKit).first.map { (metric, $0) }
        }
        let lastDate = latest.map(\.1.date).max()
        return HStack(spacing: 12) {
            BodyMetricIcon(systemImage: "ruler", color: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Medidas Corporais")
                if latest.isEmpty {
                    Text("Ainda sem medidas registadas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(latest.map { "\($0.0.displayName) \($0.0.formatted($0.1.value))" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let lastDate {
                        Text("Última medição: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Rows

    /// BMI from Apple Health, or worked out from the latest weight and height when no app writes it.
    private var bmiRow: some View {
        let fromHealth = healthKit.bmiHistory.first
        let computed: Double? = {
            guard let weight = healthKit.latestWeightKG, let height = healthKit.latestHeightMeters, height > 0 else { return nil }
            return weight / (height * height)
        }()
        let bmi = fromHealth?.value ?? computed
        return HStack {
            BodyMetricIcon(systemImage: "figure", color: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("IMC")
                if let bmi {
                    Text(Self.bmiCategory(bmi) + (fromHealth == nil ? " · calculado (peso e altura)" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Regista o peso e a altura na app Saúde")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(.headline)
                .monospacedDigit()
        }
    }

    /// WHO adult categories.
    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Baixo peso"
        case ..<25: return "Peso normal"
        case ..<30: return "Excesso de peso"
        default: return "Obesidade"
        }
    }
}

/// One body metric: latest value, its date and source, and the change since the reading before.
/// Opens the metric's history.
struct BodyMetricRow: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit

    let metric: BodyMetric

    var body: some View {
        let readings = store.readings(of: metric, healthKit: healthKit)
        NavigationLink {
            BodyMetricHistoryView(metric: metric)
        } label: {
            HStack {
                BodyMetricIcon(systemImage: metric.symbolName, color: metric.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.displayName)
                    if let latest = readings.first {
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted) + (latest.sourceLabel.map { " · \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(readings.first.map { metric.formatted($0.value) } ?? "—")
                        .font(.headline)
                        .monospacedDigit()
                    if readings.count > 1 {
                        let change = readings[0].value - readings[1].value
                        Text(change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) + (metric.unitLabel.isEmpty ? "" : " \(metric.unitLabel)"))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The small coloured square icon of the body-metric rows.
struct BodyMetricIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Medidas Corporais (own screen)

/// Every tape measurement with its latest value, change and history — opened from the
/// "Medidas Corporais" row in Saúde.
struct BodyMeasurementsView: View {
    @State private var showingLog = false

    var body: some View {
        List {
            Section {
                ForEach(BodyMetric.circumferences) { metric in
                    BodyMetricRow(metric: metric)
                }
            } footer: {
                Text("A cintura é guardada na app Saúde; as outras medidas ficam na app. Toca numa medida para ver o histórico e como a medir.")
            }
            Section {
                NavigationLink {
                    MeasurementGuideView()
                } label: {
                    Label("Como Medir", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("Medidas Corporais")
        .trackScreen("Medidas Corporais")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLog = true
                } label: {
                    Label("Registar Medidas", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            LogBodyMeasurementsView()
        }
    }
}

// MARK: - Top "Registo de Medidas" area

/// The Saúde tab's entry point for logging a measuring session (composition and tape
/// measurements), with the how-to guide next to it.
struct BodyMeasurementLogCard: View {
    @Binding var showingLog: Bool

    var body: some View {
        Section {
            Button {
                showingLog = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "ruler.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Registar Medidas")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Massa gorda, massa muscular, visceral e perímetros")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            NavigationLink {
                MeasurementGuideView()
            } label: {
                Label("Como Medir", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Registo de Medidas")
        } footer: {
            Text("Mede de manhã, em jejum, com uma fita métrica flexível e sempre do mesmo lado do corpo.")
        }
    }
}

// MARK: - Logging

/// One form for a whole measuring session: every field is optional, only the filled ones are saved.
struct LogBodyMeasurementsView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    @State private var date = Date()
    @State private var texts: [BodyMetric: String] = [:]
    @State private var guideMetric: BodyMetric?
    @State private var errorMessage: String?

    private func value(for metric: BodyMetric) -> Double? {
        guard let text = texts[metric]?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var hasAnyValue: Bool { BodyMetric.allCases.contains { value(for: $0) != nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section("Composição (balança)") {
                    ForEach(BodyMetric.composition) { field(for: $0) }
                }
                Section {
                    ForEach(BodyMetric.circumferences) { field(for: $0) }
                } header: {
                    Text("Perímetros (fita métrica)")
                } footer: {
                    Text("Toca no ícone de cada medida para veres como a medir. Deixa em branco o que não mediste. A massa gorda, a massa magra e a cintura são guardadas na app Saúde.")
                }
            }
            .navigationTitle("Registar Medidas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!hasAnyValue || isSaving)
                }
            }
            .sheet(item: $guideMetric) { metric in
                NavigationStack {
                    ScrollView {
                        MeasurementGuideCard(metric: metric)
                            .padding()
                    }
                    .navigationTitle(metric.displayName)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { guideMetric = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Valor fora do normal", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func field(for metric: BodyMetric) -> some View {
        HStack {
            Button {
                guideMetric = metric
            } label: {
                Image(systemName: metric.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(metric.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Como medir \(metric.displayName)")

            Text(metric.displayName)
            Spacer()
            TextField("—", text: Binding(get: { texts[metric] ?? "" }, set: { texts[metric] = $0 }))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(metric.unitLabel)
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
        }
    }

    private func save() {
        var values: [(BodyMetric, Double)] = []
        for metric in BodyMetric.allCases {
            guard let value = value(for: metric) else { continue }
            guard metric.validRange.contains(value) else {
                errorMessage = "\(metric.displayName): \(metric.formatted(value)) parece um engano (esperado entre \(metric.formatted(metric.validRange.lowerBound)) e \(metric.formatted(metric.validRange.upperBound)))."
                return
            }
            values.append((metric, value))
        }
        isSaving = true
        Task {
            var local: [BodyMeasurement] = []
            for (metric, value) in values {
                // Health's metrics go to Health (and nowhere else, or they'd show up twice); if
                // that fails — no permission, no Health on this device — the app keeps them.
                if metric.isHealthKitWritable, await healthKit.logBodyMetric(metric, value: value, date: date) {
                    continue
                }
                local.append(BodyMeasurement(metric: metric, value: value, date: date))
            }
            if !local.isEmpty { store.addBodyMeasurements(local) }
            if values.contains(where: { $0.0.isHealthKitWritable }) {
                await healthKit.refresh(days: 365)
            }
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - History per metric

struct BodyMetricHistoryView: View {
    @Environment(DataStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    let metric: BodyMetric

    @State private var showingLog = false

    var body: some View {
        let readings = store.readings(of: metric, healthKit: healthKit)
        List {
            Section {
                MeasurementGuideCard(metric: metric)
            }

            Section {
                if readings.isEmpty {
                    Text("Ainda sem registos.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.date.formatted(date: .abbreviated, time: .omitted))
                            if let source = reading.sourceLabel {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if index + 1 < readings.count {
                            let change = reading.value - readings[index + 1].value
                            Text(change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(metric.formatted(reading.value))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .deleteDisabled(!reading.isDeletable)
                }
                .onDelete { offsets in
                    for index in offsets {
                        let reading = readings[index]
                        if let measurement = reading.measurement {
                            store.deleteBodyMeasurement(measurement)
                        } else if reading.isFromThisApp {
                            Task { await healthKit.deleteBodyMetricSample(metric, id: reading.id) }
                        }
                    }
                }
            } header: {
                Text("Histórico")
            } footer: {
                if readings.contains(where: { !$0.isDeletable }) {
                    Text("Os valores escritos por outras apps (ex.: uma balança) só se apagam na própria app Saúde.")
                }
            }
        }
        .navigationTitle(metric.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            LogBodyMeasurementsView()
        }
    }
}

// MARK: - How to measure

/// Every measurement with its illustration and instructions.
struct MeasurementGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Mede sempre nas mesmas condições — de manhã, em jejum, depois de ir à casa de banho e antes de treinar — para que as diferenças entre registos sejam reais.")
                    .font(.subheadline)
            }
            ForEach(BodyMetric.circumferences + BodyMetric.composition) { metric in
                Section(metric.displayName) {
                    MeasurementGuideCard(metric: metric)
                }
            }
        }
        .navigationTitle("Como Medir")
    }
}

/// The figure with the tape drawn where to measure (or a scale, for scale readings), plus the
/// written instructions.
struct MeasurementGuideCard: View {
    let metric: BodyMetric

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            BodyFigureIllustration(metric: metric)
                .frame(width: 90, height: 170)
            Text(metric.howToMeasure)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// A standing figure with the measuring tape drawn as a coloured band where `metric` is taken.
struct BodyFigureIllustration: View {
    let metric: BodyMetric

    var body: some View {
        if let tape = metric.tapePosition {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Image(systemName: "figure.stand")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                    Capsule()
                        .fill(metric.color)
                        .frame(width: size.width * tape.width, height: 4)
                        .shadow(color: metric.color.opacity(0.8), radius: 3)
                        .offset(x: size.width * tape.x, y: size.height * tape.y - 2)
                }
            }
            .accessibilityHidden(true)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(metric.color)
                Image(systemName: metric.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    NavigationStack {
        MeasurementGuideView()
    }
}
