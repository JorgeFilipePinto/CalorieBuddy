import SwiftUI

/// Weight and body composition, backed by Apple Health so data already logged by other apps (a
/// smart scale, the Health app) shows up here automatically. Water and coffee are logged from
/// the Alimentos tab (`DrinksSections`).
struct HealthSectionView: View {
    @Environment(HealthKitManager.self) private var healthKit

    @State private var showingLogWeight = false
    @State private var showingLogMeasurements = false
    @State private var showingLogProgressPhotos = false

    /// A year of Apple Health data, so the monthly weight history has something to group.
    private static let historyDays = 365

    /// One month of weight readings, as shown in the collapsible monthly history.
    private struct WeightMonth: Identifiable {
        let start: Date
        /// Most recent first.
        let samples: [HealthKitManager.QuantitySample]
        let average: Double
        /// Gained (+) or lost (−) over the month; `nil` when there's nothing to compare against.
        let change: Double?
        var id: Date { start }
    }

    var body: some View {
        Group {
            if healthKit.isSupported {
                List {
                    weightSection
                    BodyCompositionSections(part: .composition)
                    BodyCompositionSections(part: .circumferences)
                    BodyMeasurementLogCard(showingLog: $showingLogMeasurements)
                    ProgressPhotosSection(showingLog: $showingLogProgressPhotos)
                    historySection
                }
            } else {
                ContentUnavailableView(
                    "Não Disponível",
                    systemImage: "heart.text.square",
                    description: Text("O controlo de peso e da composição corporal usa a app Saúde, disponível apenas no iPhone e iPad.")
                )
            }
        }
        .navigationTitle("Saúde")
        .trackScreen("Saúde")
        .task {
            await healthKit.requestAuthorization()
            await healthKit.refresh(days: Self.historyDays)
        }
        .refreshable {
            Haptics.light()
            await healthKit.refresh(days: Self.historyDays)
        }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightView()
        }
        .sheet(isPresented: $showingLogMeasurements) {
            LogBodyMeasurementsView()
        }
        .sheet(isPresented: $showingLogProgressPhotos) {
            LogProgressPhotosView()
        }
    }

    private var weightSection: some View {
        Section {
            currentWeightCard
        } header: {
            Text("Peso")
        }
    }

    /// The weight history by month, then the link to the multi-metric evolution chart.
    private var historySection: some View {
        Section {
            ForEach(weightMonths) { month in
                DisclosureGroup {
                    ForEach(month.samples) { sample in
                        HStack {
                            Text(sample.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            Spacer()
                            Text(Self.kilograms(sample.value))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } label: {
                    weightMonthLabel(month)
                }
            }
            NavigationLink {
                TrendsView()
            } label: {
                Label("Ver Evolução", systemImage: "chart.line.uptrend.xyaxis")
            }
        } header: {
            Text("Histórico")
        } footer: {
            Text("Peso por mês: a variação é o último peso do mês face ao último do mês anterior (no mês mais antigo, face ao primeiro registo do próprio mês). Os valores vêm da app Saúde — incluindo os que outras apps ou uma balança inteligente já lá tenham registado.")
        }
    }

    /// The latest weight, big and centred, with the change since the reading before it.
    private var currentWeightCard: some View {
        VStack(spacing: 6) {
            if let latest = healthKit.weightHistory.first {
                Text("Peso atual")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latest.value.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("kg")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Último registo: " + latest.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if healthKit.weightHistory.count > 1 {
                    let change = latest.value - healthKit.weightHistory[1].value
                    Text(Self.signedKilograms(change) + " face ao registo anterior")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Self.changeColor(change))
                }
            } else {
                Image(systemName: "scalemass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Sem registos de peso.")
                    .foregroundStyle(.secondary)
            }

            Button {
                showingLogWeight = true
            } label: {
                // Inside a List the icon would take the (red) accent colour and vanish on the
                // red button, so the whole label is set white explicitly.
                Label("Registar Peso", systemImage: "scalemass")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func weightMonthLabel(_ month: WeightMonth) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.start.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                Text("\(month.samples.count) \(month.samples.count == 1 ? "registo" : "registos") · média \(Self.kilograms(month.average))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let change = month.change {
                Text(Self.signedKilograms(change))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Self.changeColor(change))
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Weight readings grouped by calendar month, most recent month first.
    private var weightMonths: [WeightMonth] {
        let calendar = Calendar.current
        let byMonth = Dictionary(grouping: healthKit.weightHistory) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? calendar.startOfDay(for: $0.date)
        }
        let starts = byMonth.keys.sorted(by: >)
        return starts.enumerated().map { index, start in
            let samples = (byMonth[start] ?? []).sorted { $0.date > $1.date }
            let values = samples.map(\.value)
            let average = values.reduce(0, +) / Double(max(values.count, 1))
            // Against the previous month's last reading; the oldest loaded month falls back to its
            // own first reading (no change to show when that's its only one).
            let baseline = index + 1 < starts.count
                ? byMonth[starts[index + 1]]?.max { $0.date < $1.date }?.value
                : (samples.count > 1 ? samples.last?.value : nil)
            var change: Double?
            if let latest = samples.first?.value, let baseline { change = latest - baseline }
            return WeightMonth(start: start, samples: samples, average: average, change: change)
        }
    }

    private static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " kg"
    }

    /// "+0,5 kg", "-0,1 kg" or "0,0 kg".
    private static func signedKilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false))) + " kg"
    }

    /// Neutral colours on purpose: whether gaining or losing is good depends on the athlete's goal.
    private static func changeColor(_ change: Double) -> Color {
        if abs(change) < 0.05 { return .secondary }
        return change > 0 ? .orange : .teal
    }
}

private struct LogWeightView: View {
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""

    private var weight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Peso (kg)")
                    Spacer()
                    TextField("70.0", text: $weightText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .navigationTitle("Registar Peso")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let weight {
                            Task {
                                await healthKit.logWeight(kilograms: weight)
                                dismiss()
                            }
                        }
                    }
                    .disabled(weight == nil)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthSectionView()
    }
    .environment(HealthKitManager())
}
