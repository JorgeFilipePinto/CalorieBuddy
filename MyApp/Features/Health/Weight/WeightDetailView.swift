import SwiftUI

/// Reference ranges used by the report. They are those of an adult man; sex and age can refine
/// them once the profile has them.
enum BodyReference {
    static let bmiBands = [
        RangeBand(upTo: 18.5, tone: .low, label: "Baixo peso"),
        RangeBand(upTo: 25, tone: .healthy, label: "Normal"),
        RangeBand(upTo: 30, tone: .caution, label: "Excesso de peso"),
        RangeBand(upTo: 35, tone: .high, label: "Obesidade I"),
        RangeBand(upTo: 40, tone: .high, label: "Obesidade II"),
        RangeBand(upTo: .infinity, tone: .veryHigh, label: "Obesidade III")
    ]
    static let bodyFatBands = [
        RangeBand(upTo: 8, tone: .low, label: "Pouca gordura"),
        RangeBand(upTo: 20, tone: .healthy, label: "Saudável"),
        RangeBand(upTo: 25, tone: .caution, label: "Excesso de gordura"),
        RangeBand(upTo: .infinity, tone: .high, label: "Gordura elevada")
    ]
    static let visceralBands = [
        RangeBand(upTo: 10, tone: .healthy, label: "Baixa"),
        RangeBand(upTo: 15, tone: .caution, label: "Alta"),
        RangeBand(upTo: .infinity, tone: .high, label: "Muito alta")
    ]
    static let waterBands = [
        RangeBand(upTo: 50, tone: .high, label: "Baixa"),
        RangeBand(upTo: 65, tone: .healthy, label: "Saudável"),
        RangeBand(upTo: .infinity, tone: .high, label: "Alta")
    ]
    static let proteinBands = [
        RangeBand(upTo: 16, tone: .high, label: "Baixa"),
        RangeBand(upTo: .infinity, tone: .healthy, label: "Padrão")
    ]
    static let skeletalMuscleBands = [
        RangeBand(upTo: 49, tone: .high, label: "Baixo"),
        RangeBand(upTo: 59, tone: .caution, label: "Padrão"),
        RangeBand(upTo: .infinity, tone: .healthy, label: "Alto")
    ]
    static let subcutaneousFatBands = [
        RangeBand(upTo: 8.6, tone: .low, label: "Baixa"),
        RangeBand(upTo: 16.7, tone: .healthy, label: "Padrão"),
        RangeBand(upTo: 20.7, tone: .caution, label: "Elevada"),
        RangeBand(upTo: .infinity, tone: .high, label: "Muito elevada")
    ]

    /// Recommended bone mass (kg) for a man by body weight.
    static func boneRecommendation(weight: Double) -> Double {
        weight < 65 ? 2.6 : weight <= 95 ? 3.2 : 3.7
    }

    static func bodyFatRow(_ percent: Double) -> Int { percent < 8 ? 2 : percent <= 20 ? 1 : 0 }

    /// 0 = low, 1 = standard, 2 = high muscle, from the muscle share of the body weight.
    static func muscleColumn(_ share: Double) -> Int { share < 60 ? 0 : share <= 70 ? 1 : 2 }
}

/// The full report of one weigh-in: weight against the goal, BMI, body fat, physique rating and
/// every other composition value there is. Previous / Next walk through the weigh-ins.
struct WeightDetailView: View {
    let weighIns: [WeighIn]
    let goal: Double?

    @State private var index: Int

    init(weighIns: [WeighIn], selected: UUID, goal: Double?) {
        self.weighIns = weighIns
        self.goal = goal
        _index = State(initialValue: weighIns.firstIndex { $0.id == selected } ?? 0)
    }

    private var current: WeighIn { weighIns[index] }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weightCard
                if let bmi = current.bmi { bmiCard(bmi) }
                if let fat = current.bodyFatPercent { bodyFatCard(fat) }
                if let fat = current.bodyFatPercent, let muscle = current.muscleKg { physiqueCard(fat: fat, muscle: muscle) }
                if let visceral = current.visceralFat {
                    barCard("Gordura Visceral", value: visceral, text: format(visceral, 0),
                            domain: 0...25, bands: BodyReference.visceralBands, ticks: [10, 15])
                }
                if let protein = current.proteinPercent {
                    barCard("Proteína", value: protein, text: format(protein) + "%",
                            domain: 8...24, bands: BodyReference.proteinBands, ticks: [16])
                }
                if let skeletal = current.skeletalMusclePercent {
                    barCard("Músculo Esquelético", value: skeletal, text: format(skeletal) + "%",
                            domain: 30...70, bands: BodyReference.skeletalMuscleBands, ticks: [49, 59])
                }
                if let subcutaneous = current.subcutaneousFatPercent {
                    barCard("Gordura Subcutânea", value: subcutaneous, text: format(subcutaneous) + "%",
                            domain: 2...28, bands: BodyReference.subcutaneousFatBands, ticks: [8.6, 16.7, 20.7])
                }
                if let muscle = current.muscleKg { massCard("Massa Muscular", kg: muscle, color: .indigo) }
                if let water = current.waterPercent {
                    barCard("Água Corporal", value: water, text: format(water) + "%",
                            domain: 35...80, bands: BodyReference.waterBands, ticks: [50, 65])
                }
                if let age = current.metabolicAge { metabolicAgeCard(age) }
                if let bone = current.boneKg { boneCard(bone) }
                if let bmr = current.basalMetabolicRate { bmrCard(bmr) }
                Text("Os intervalos de referência são os de um adulto do sexo masculino.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle(current.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { navigationBar }
    }

    // MARK: - Cards

    private func card<Content: View>(_ title: String? = nil, subtitle: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.title3.bold()) }
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weightCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text(current.weight.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Text("kg").font(.title2).foregroundStyle(.secondary)
                Spacer()
                if let change = current.change, abs(change) >= 0.05 {
                    Label(abs(change).formatted(.number.precision(.fractionLength(1))) + " kg",
                          systemImage: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(change > 0 ? Color.red : Color.teal, in: Capsule())
                }
            }
            WeightGoalBar(weight: current.weight, goal: goal)
        }
    }

    private func bmiCard(_ bmi: Double) -> some View {
        card("IMC") {
            StatusBar(domain: 14...44, bands: BodyReference.bmiBands, value: bmi, valueText: format(bmi),
                      ticks: [18.5, 25, 30, 35, 40])
        }
    }

    private func bodyFatCard(_ percent: Double) -> some View {
        card("Gordura Corporal", subtitle: current.bodyFatKg.map { "\(format($0)) kg de \(format(current.weight)) kg de peso" }) {
            StatusBar(domain: 3...35, bands: BodyReference.bodyFatBands, value: percent, valueText: format(percent) + "%",
                      ticks: [8, 20, 25])
        }
    }

    private func barCard(_ title: String, value: Double, text: String, domain: ClosedRange<Double>,
                         bands: [RangeBand], ticks: [Double]) -> some View {
        card(title) {
            StatusBar(domain: domain, bands: bands, value: value, valueText: text, ticks: ticks)
        }
    }

    private func massCard(_ title: String, kg: Double, color: Color) -> some View {
        card(title, subtitle: "de \(format(current.weight)) kg de peso") {
            FillBar(fraction: current.weight > 0 ? kg / current.weight : 0, valueText: format(kg) + " kg", color: color)
        }
    }

    private func metabolicAgeCard(_ age: Double) -> some View {
        card("Idade Metabólica") {
            StatusBar(domain: 10...90, bands: [RangeBand(upTo: .infinity, tone: .healthy, label: "")],
                      value: age, valueText: format(age, 0), ticks: Array(stride(from: 10.0, through: 90, by: 10)))
        }
    }

    private func boneCard(_ kg: Double) -> some View {
        let recommended = BodyReference.boneRecommendation(weight: current.weight)
        return card("Massa Óssea", subtitle: "de \(format(current.weight)) kg de peso") {
            FillBar(fraction: kg / 6, valueText: format(kg) + " kg", color: .blue, mark: recommended / 6)
            Text("Recomendado*: \(format(recommended)) kg")
                .font(.subheadline)
            Text("*Uma dieta rica em cálcio e vitamina D, exposição solar e exercício físico são essenciais para a saúde dos ossos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bmrCard(_ kcal: Double) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text("Metabolismo Basal").font(.title3.bold())
                Spacer()
                Text(format(kcal, 0)).font(.title2.bold()).monospacedDigit()
                Text("kcal/dia").foregroundStyle(.secondary)
            }
        }
    }

    /// Fat level (rows) against muscle level (columns), with the current one marked.
    private func physiqueCard(fat: Double, muscle: Double) -> some View {
        let row = BodyReference.bodyFatRow(fat)
        let column = BodyReference.muscleColumn(current.weight > 0 ? muscle / current.weight * 100 : 0)
        let names = [
            ["Obesidade oculta", "Obeso", "Corpulento"],
            ["Pouco treinado", "Normal", "Normal musculado"],
            ["Magro", "Magro musculado", "Muito musculado"]
        ]
        let rowTitles = ["Gordura alta", "Saudável", "Pouca gordura"]
        return card("Avaliação Física", subtitle: names[row][column]) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow {
                        Text(rowTitles[r]).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        ForEach(0..<3, id: \.self) { c in
                            let isCurrent = r == row && c == column
                            Image(systemName: "figure.stand")
                                .font(.system(size: 34))
                                .foregroundStyle(isCurrent ? Color.indigo : Color.gray.opacity(0.6))
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .background(isCurrent ? Color.orange.opacity(0.35) : (r == 1 ? Color.green.opacity(0.15) : Color.red.opacity(0.12)),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Label("Gordura", systemImage: "square.fill").foregroundStyle(.orange)
                Label("Músculo", systemImage: "square.fill").foregroundStyle(.indigo)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Navigation between weigh-ins

    /// Previous = the weigh-in before this one (older), Next = the one after.
    private var navigationBar: some View {
        HStack {
            Button {
                index += 1
            } label: {
                Label("Anterior", systemImage: "arrow.left").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(index + 1 >= weighIns.count)
            Divider().frame(height: 28)
            Button {
                index -= 1
            } label: {
                Label("Seguinte", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .disabled(index == 0)
        }
        .font(.headline)
        .padding()
        .background(.bar)
    }

    private func format(_ value: Double, _ digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.title; configuration.icon }
    }
}
