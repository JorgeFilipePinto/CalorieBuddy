import SwiftUI

/// Water and coffee logging for the Alimentos tab — both are drinks, so they sit with the food,
/// but they're stored in Apple Health (water as `dietaryWater`, a coffee as 50 mg of caffeine) so
/// what other apps log there counts too.
struct DrinksSections: View {
    @Environment(HealthKitManager.self) private var healthKit
    /// Owned by the screen: a sheet attached to a section inside a `List` gets dismissed as soon
    /// as the list re-renders that section.
    @Binding var showingLogWater: Bool

    var body: some View {
        if healthKit.isSupported {
            waterSection
            coffeeSection
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
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
        Button {
            Task { await healthKit.logWater(liters: liters) }
        } label: {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

                Label(coffeesLabel(healthKit.coffeeCount(on: .now)) + " hoje", systemImage: "cup.and.saucer.fill")
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

struct LogWaterView: View {
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

