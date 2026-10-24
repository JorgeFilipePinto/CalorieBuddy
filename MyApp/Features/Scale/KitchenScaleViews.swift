import SwiftUI

/// Alimentos → Balança: connect to the Prozis Bit Scale, watch the live weight on a big gauge, tare.
struct KitchenScaleView: View {
    @Environment(KitchenScaleManager.self) private var scale

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                WeightGauge(net: scale.grams ?? 0, tare: scale.tareGrams,
                            isLive: scale.isConnected && scale.reading != nil)
                    .frame(maxWidth: 420)
                    .padding(.top, 8)

                if let reading = scale.reading {
                    BatteryGauge(percent: reading.batteryPercent)
                        .padding(.horizontal)
                } else if scale.isConnected {
                    Text("Põe algo na balança para ver o peso.")
                        .foregroundStyle(.secondary)
                }

                Text(scale.state.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    if scale.isConnected {
                        TareButton(prominent: true)
                        Button("Desligar", role: .destructive) { scale.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Ligar à balança", systemImage: "dot.radiowaves.left.and.right") { scale.connect() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)

                Text("Prozis Bit Scale. A balança não tem ecrã e só envia o peso quando ele muda. Cada Tara fica a vermelho no gauge e o peso novo a verde. Mantém a Tara premida para limpar tudo e pôr a balança a zero.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Balança")
    }
}

/// A big circular gauge from 0 to 2 kg. The position is the total on the scale (tare + net); the tared
/// part is red and the weight added since is green. The number in the middle is the net weight.
struct WeightGauge: View {
    /// What the scale shows (already net of the tare).
    let net: Int
    /// What every tare so far zeroed away.
    let tare: Int
    let isLive: Bool
    /// Weight was added with no food chosen: pulses orange and asks for one.
    var needsFood = false
    @State private var pulse = false

    static let maxGrams = 2000.0
    private let sweep = 1.0  // the whole circle, starting at the top

    private var gross: Double { max(0, Double(tare + net)) }
    private func fraction(_ grams: Double) -> Double { min(max(grams / Self.maxGrams, 0), 1) * sweep }

    var body: some View {
        let redEnd = fraction(min(Double(tare), gross))
        let greenEnd = fraction(gross)
        ZStack {
            arc(from: 0, to: sweep, color: Color.secondary.opacity(0.2))
            arc(from: 0, to: redEnd, color: .red)
            arc(from: redEnd, to: greenEnd, color: .green)

            if needsFood {
                Circle()
                    .stroke(Color.orange, lineWidth: 6)
                    .opacity(pulse ? 1 : 0.2)
            }

            VStack(spacing: 4) {
                Text(isLive ? "\(net)" : "—")
                    .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if needsFood {
                    Label("Escolhe o alimento", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                } else {
                    Text("gramas")
                        .foregroundStyle(.secondary)
                }
                if tare > 0 {
                    Label("Tara \(tare) g", systemImage: "minus.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                }
                if gross > Self.maxGrams {
                    Text("Acima de 2 kg")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }

            VStack {
                Text("0 · 2 kg")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 36)
                Spacer()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeOut(duration: 0.25), value: net)
        .animation(.easeOut(duration: 0.25), value: tare)
        .onChange(of: needsFood) { _, needs in
            if needs {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(.default) { pulse = false }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peso")
        .accessibilityValue("\(net) gramas, tara \(tare) gramas")
    }

    /// An arc of the track, `from`/`to` as fractions of the full circle.
    private func arc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: from, to: max(from, to))
            .stroke(color, style: StrokeStyle(lineWidth: 28, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .padding(14)
    }
}

/// A compact row for a list of amounts: connection status, live weight and tare.
struct KitchenScaleStatusRow: View {
    @Environment(KitchenScaleManager.self) private var scale

    var body: some View {
        HStack {
            Image(systemName: "scalemass")
                .foregroundStyle(scale.isConnected ? Color.accentColor : .secondary)
            if scale.isConnected {
                Text(scale.grams.map { "\($0) g" } ?? "—")
                    .font(.headline.monospacedDigit())
                Spacer()
                TareButton(prominent: false)
            } else {
                Text(scale.state == .idle ? "Balança" : scale.state.title)
                    .foregroundStyle(.secondary)
                Spacer()
                if scale.state == .idle {
                    Button("Ligar") { scale.connect() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// The scale's battery as a gauge with its percentage (the byte is a hypothesis, see the protocol notes).
struct BatteryGauge: View {
    let percent: Int

    private var clamped: Int { min(max(percent, 0), 100) }
    private var tint: Color { clamped <= 15 ? .red : clamped <= 30 ? .orange : .green }
    private var symbol: String {
        switch clamped {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Gauge(value: Double(clamped), in: 0...100) {
                Image(systemName: symbol)
            } currentValueLabel: {
                Text("\(clamped)%")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)
            .scaleEffect(1.3)
            .frame(width: 64, height: 64)
            Text("Bateria")
                .foregroundStyle(.secondary)
        }
    }
}

/// Tap = tare (adds to the gauge's red part); long press = forget every tare and say the scale is at zero.
struct TareButton: View {
    @Environment(KitchenScaleManager.self) private var scale
    let prominent: Bool
    @State private var resets = 0

    var body: some View {
        Label("Tara", systemImage: "scalemass")
            .font(prominent ? .body.weight(.semibold) : .subheadline)
            .padding(.horizontal, prominent ? 20 : 12)
            .padding(.vertical, prominent ? 12 : 6)
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { scale.tare() }
            .onLongPressGesture(minimumDuration: 0.6) {
                scale.resetToZero()
                resets += 1
            }
            .sensoryFeedback(.success, trigger: resets)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Limpar tudo e pôr a zero") { scale.resetToZero() }
    }
}
