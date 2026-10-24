import SwiftUI

/// How a value compares with its reference range; sets the colour of the bar's segment.
enum RangeTone {
    case low, healthy, caution, high, veryHigh

    var color: Color {
        switch self {
        case .low: return Color(red: 0.66, green: 0.80, blue: 0.99)
        case .healthy: return Color(red: 0.99, green: 0.90, blue: 0.67)
        case .caution: return Color(red: 0.97, green: 0.69, blue: 0.29)
        case .high: return Color(red: 0.98, green: 0.58, blue: 0.25)
        case .veryHigh: return Color(red: 0.92, green: 0.47, blue: 0.45)
        }
    }
}

/// A segment of a `StatusBar`: up to `upTo` (the last one up to the end of the bar).
struct RangeBand {
    let upTo: Double
    let tone: RangeTone
    var label: String
}

/// A coloured bar split into reference ranges, with the value marked by a callout above it and the
/// range limits written under it (BMI, body fat, visceral fat…).
struct StatusBar: View {
    let domain: ClosedRange<Double>
    let bands: [RangeBand]
    let value: Double
    let valueText: String
    var ticks: [Double] = []

    /// The label of the band the value is in.
    private var status: String? {
        bands.first { value <= $0.upTo }?.label ?? bands.last?.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let x = position(of: value, in: geo.size.width)
                let calloutWidth = CGFloat(valueText.count) * 9 + 26
                let calloutX = min(max(x - calloutWidth / 2, 0), max(geo.size.width - calloutWidth, 0))
                // The status goes right of the callout, or left of it when there is no room.
                let statusLeft = calloutX + calloutWidth + 8 + statusWidth(status) > geo.size.width
                HStack(spacing: 8) {
                    if statusLeft, let status { Text(status).font(.subheadline) }
                    ValueCallout(text: valueText, pointerOffset: x - calloutX - calloutWidth / 2)
                        .frame(width: calloutWidth)
                    if !statusLeft, let status { Text(status).font(.subheadline) }
                }
                .offset(x: statusLeft ? calloutX - statusWidth(status) : calloutX)
            }
            .frame(height: 38)

            bar
                .frame(height: 22)

            GeometryReader { geo in
                ForEach(ticks, id: \.self) { tick in
                    Text(tick.formatted(.number.precision(.fractionLength(tick.rounded() == tick ? 0 : 1))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: position(of: tick, in: geo.size.width), y: 8)
                }
            }
            .frame(height: 16)
        }
    }

    /// Rough width of the status text, so it can sit to the left of the callout.
    private func statusWidth(_ text: String?) -> CGFloat {
        CGFloat(text?.count ?? 0) * 8 + 8
    }

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    let start = index == 0 ? domain.lowerBound : bands[index - 1].upTo
                    let end = index == bands.count - 1 ? domain.upperBound : band.upTo
                    Rectangle()
                        .fill(band.tone.color)
                        .frame(width: max(position(of: end, in: geo.size.width) - position(of: start, in: geo.size.width), 0))
                }
            }
            .clipShape(Capsule())
        }
    }

    private func position(of v: Double, in width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((v - domain.lowerBound) / span, 0), 1)) * width
    }
}

/// The dark label with a little pointer under it that marks a value on a bar.
struct ValueCallout: View {
    let text: String
    /// How far the pointer is from the centre (the label is clamped inside the bar).
    var pointerOffset: CGFloat = 0
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Triangle()
                .fill(tint)
                .frame(width: 10, height: 5)
                .offset(x: pointerOffset)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A plain bar filled up to a value (muscle mass, bone mass), with the value on a callout.
struct FillBar: View {
    let fraction: Double
    let valueText: String
    var color: Color = .blue
    /// A mark on the bar (e.g. a recommended value), as a fraction too.
    var mark: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let x = CGFloat(min(max(fraction, 0), 1)) * geo.size.width
                let width = CGFloat(valueText.count) * 9 + 26
                let calloutX = min(max(x - width / 2, 0), max(geo.size.width - width, 0))
                ValueCallout(text: valueText, pointerOffset: x - calloutX - width / 2)
                    .frame(width: width)
                    .offset(x: calloutX)
            }
            .frame(height: 38)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color).frame(width: max(CGFloat(min(max(fraction, 0), 1)) * geo.size.width, 22))
                    if let mark {
                        Rectangle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 2)
                            .offset(x: CGFloat(min(max(mark, 0), 1)) * geo.size.width - 1)
                    }
                }
            }
            .frame(height: 22)
        }
    }
}

/// The weight on a grey track with the goal marked below it.
struct WeightGoalBar: View {
    let weight: Double
    let goal: Double?

    private var domain: ClosedRange<Double> {
        let low = min(weight, goal ?? weight)
        let start = (floor((low - 15) / 5) * 5)
        return start...(start + 35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let x = position(weight, geo.size.width)
                let width = CGFloat(8) * 9 + 26
                let calloutX = min(max(x - width / 2, 0), max(geo.size.width - width, 0))
                HStack(spacing: 8) {
                    Text("O teu peso").font(.subheadline)
                    ValueCallout(text: Self.kg(weight), pointerOffset: x - calloutX - width / 2)
                        .frame(width: width)
                }
                .offset(x: max(calloutX - 96, 0))
            }
            .frame(height: 38)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 8)
                        .offset(x: position(weight, geo.size.width) - 4)
                }
                .clipShape(Capsule())
            }
            .frame(height: 24)

            GeometryReader { geo in
                ForEach(Array(stride(from: domain.lowerBound, through: domain.upperBound, by: 5)), id: \.self) { tick in
                    Text("\(Int(tick))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: position(tick, geo.size.width), y: 8)
                }
            }
            .frame(height: 16)

            if let goal {
                GeometryReader { geo in
                    let x = position(goal, geo.size.width)
                    let width = CGFloat(8) * 9 + 26
                    let calloutX = min(max(x - width / 2, 0), max(geo.size.width - width, 0))
                    HStack(spacing: 8) {
                        Text("Objetivo").font(.subheadline)
                        Text(Self.kg(goal))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .offset(x: max(calloutX - 70, 0))
                }
                .frame(height: 34)
            }
        }
    }

    private func position(_ v: Double, _ width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        return CGFloat(min(max((v - domain.lowerBound) / span, 0), 1)) * width
    }

    static func kg(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1))) + " kg"
    }
}
