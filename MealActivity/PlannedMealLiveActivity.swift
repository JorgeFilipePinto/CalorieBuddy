import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The planned meal when its time comes: what, how much, and "Comi" / "Recusar".
struct PlannedMealLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MealActivityAttributes.self) { context in
            // Lock Screen / banner.
            VStack(alignment: .leading, spacing: 10) {
                header(context.attributes)
                actions(context.attributes)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.mealName, systemImage: context.attributes.mealSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.time, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.recipeName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(context.attributes.kcal) kcal · \(context.attributes.macros)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    actions(context.attributes)
                }
            } compactLeading: {
                Image(systemName: context.attributes.mealSymbol)
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(context.attributes.time, style: .time)
                    .font(.caption2)
            } minimal: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }

    private func header(_ attributes: MealActivityAttributes) -> some View {
        HStack {
            Image(systemName: attributes.mealSymbol)
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(attributes.mealName) · \(attributes.time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(attributes.recipeName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(attributes.kcal) kcal · \(attributes.macros)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func actions(_ attributes: MealActivityAttributes) -> some View {
        HStack {
            Button(intent: ConfirmPlannedMealIntent(placementID: attributes.placementID)) {
                Label("Comi", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
            Button(intent: RefusePlannedMealIntent(placementID: attributes.placementID)) {
                Label("Recusar", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.gray)
        }
        .buttonStyle(.borderedProminent)
    }
}
