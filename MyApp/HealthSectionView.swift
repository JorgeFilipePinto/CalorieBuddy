import SwiftUI

/// Weight control and water intake, backed by Apple Health so data already logged by other
/// apps (a smart scale, a water tracker, the Health app) shows up here automatically.
struct HealthSectionView: View {
    @Environment(HealthKitManager.self) private var healthKit

    @State private var showingLogWeight = false
    @State private var showingLogWater = false

    var body: some View {
        Group {
            if healthKit.isSupported {
                List {
                    NavigationLink {
                        TrendsView()
                    } label: {
                        Label("Ver Evolução", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    weightSection
                    waterSection
                    coffeeSection
                }
            } else {
                ContentUnavailableView(
                    "Não Disponível",
                    systemImage: "heart.text.square",
                    description: Text("O controlo de peso e água usa a app Saúde, disponível apenas no iPhone e iPad.")
                )
            }
        }
        .navigationTitle("Saúde")
        .task { await healthKit.requestAuthorization() }
        .refreshable { await healthKit.refresh() }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightView()
        }
        .sheet(isPresented: $showingLogWater) {
            LogWaterView()
        }
    }

    private var weightSection: some View {
        Section {
            if let latestWeightKG = healthKit.latestWeightKG {
                Text(latestWeightKG.formatted(.number.precision(.fractionLength(1))) + " kg")
                    .font(.title2.bold())
            } else {
                Text("Sem registos de peso.")
                    .foregroundStyle(.secondary)
            }

            ForEach(healthKit.weightHistory.dropFirst()) { sample in
                HStack {
                    Text(sample.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text(sample.value.formatted(.number.precision(.fractionLength(1))) + " kg")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showingLogWeight = true
            } label: {
                Label("Registar Peso", systemImage: "scalemass")
            }
        } header: {
            Text("Peso")
        } footer: {
            Text("Os valores vêm da app Saúde — incluindo os que outras apps ou uma balança inteligente já lá tenham registado.")
        }
    }

    private var waterSection: some View {
        Section {
            let waterML = Int((healthKit.todayWaterLiters * 1000).rounded())
            HStack {
                Label("\(waterML) ml", systemImage: "drop.fill")
                    .foregroundStyle(.blue)
                Spacer()
            }

            HStack(spacing: 12) {
                quickAddButton(label: "+250 ml", liters: 0.25)
                quickAddButton(label: "+500 ml", liters: 0.5)
                Button {
                    showingLogWater = true
                } label: {
                    Label("Outro", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Água")
        } footer: {
            Text("A quantidade de hoje inclui a água já registada por outras apps na app Saúde.")
        }
    }

    private func quickAddButton(label: String, liters: Double) -> some View {
        Button(label) {
            Task { await healthKit.logWater(liters: liters) }
        }
        .buttonStyle(.bordered)
    }

    private var coffeeSection: some View {
        Section {
            HStack {
                Button {
                    Task { await healthKit.removeLastCoffee(on: .now) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(healthKit.coffeeCount(on: .now) <= 0)

                Spacer()

                Label("\(healthKit.coffeeCount(on: .now)) cafés hoje", systemImage: "cup.and.saucer.fill")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await healthKit.logCoffee() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.brown)
        } header: {
            Text("Café")
        } footer: {
            Text("Cada café conta como 50 mg de cafeína (a medida padrão de um expresso português de 50 ml) na app Saúde, para incluir também cafés já registados por outras apps.")
        }
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
                        .keyboardType(.decimalPad)
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

private struct LogWaterView: View {
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""

    private var liters: Double? {
        guard let ml = Double(amountText) else { return nil }
        return ml / 1000
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Quantidade (ml)")
                    Spacer()
                    TextField("330", text: $amountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .navigationTitle("Registar Água")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let liters {
                            Task {
                                await healthKit.logWater(liters: liters)
                                dismiss()
                            }
                        }
                    }
                    .disabled(liters == nil)
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
