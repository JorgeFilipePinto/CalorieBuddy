import SwiftUI

/// The icons a food can have (SF Symbols), shown when weighing a meal. A food without one uses `defaultName`.
enum FoodIcon {
    static let defaultName = "carrot.fill"
    /// The plate that starts a weighed meal.
    static let plateName = "fork.knife.circle.fill"

    static let choices = [
        "carrot.fill", "leaf.fill", "fish.fill", "fork.knife", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "cup.and.saucer.fill", "mug.fill", "drop.fill", "wineglass.fill",
        "popcorn.fill", "flame.fill", "bolt.fill", "heart.fill", "star.fill", "circle.hexagongrid.fill"
    ]
}

extension FoodItem {
    var icon: String { iconName ?? FoodIcon.defaultName }
}

/// A grid of icons to choose a food's icon from; tapping the chosen one goes back to the default.
struct FoodIconPicker: View {
    @Binding var selection: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(FoodIcon.choices, id: \.self) { name in
                let isSelected = (selection ?? FoodIcon.defaultName) == name
                Button {
                    selection = isSelected ? nil : name
                } label: {
                    Image(systemName: name)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
