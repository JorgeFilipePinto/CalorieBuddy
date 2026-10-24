import Foundation
import Observation

/// One thing on the weighed meal: the plate or a food with the grams measured for it.
struct WeighComponent: Identifiable, Equatable {
    enum Kind: Equatable {
        case plate
        case food(UUID)
    }

    let id = UUID()
    var kind: Kind
    var grams: Int
}

/// A meal built by weighing: the plate, then each food on top of it. Everything is measured on the
/// scale's *gross* weight (tare + net, which keeps growing as things are added); `committedGross`
/// is how much of it already belongs to the plate and the foods in the pile, so what is still
/// unassigned (`pending`) is the weight of the food being weighed now.
@Observable
final class WeighSession {
    private(set) var components: [WeighComponent] = []
    /// The food the weight being added now belongs to (`nil` = none chosen yet).
    private(set) var currentFoodID: UUID?
    private(set) var committedGross = 0

    func pending(gross: Int) -> Int { max(0, gross - committedGross) }

    /// Something was taken off the scale: what is left on it is all that can already be assigned.
    func follow(gross: Int) {
        if gross < committedGross { committedGross = gross }
    }

    func chooseFood(_ id: UUID) {
        currentFoodID = id
    }

    /// Drops the food being weighed (its weight goes back to unassigned).
    func clearCurrentFood() {
        currentFoodID = nil
    }

    /// Closes the food being weighed (its weight so far goes to the pile).
    func commitCurrentFood(gross: Int) {
        let grams = pending(gross: gross)
        if let id = currentFoodID, grams > 0 {
            components.append(WeighComponent(kind: .food(id), grams: grams))
            committedGross += grams
        }
        currentFoodID = nil
    }

    /// Adds the plate: whatever is on the scale now (after the tare) is its weight.
    func addPlate(gross: Int) {
        commitCurrentFood(gross: gross)
        components.append(WeighComponent(kind: .plate, grams: pending(gross: gross)))
        committedGross = gross
    }

    func remove(_ component: WeighComponent) {
        components.removeAll { $0.id == component.id }
    }

    /// The foods of the pile as diary amounts (in doses of each food).
    func items(foods: [FoodItem], gross: Int) -> [RecipeItem] {
        var all = components
        if let id = currentFoodID, pending(gross: gross) > 0 {
            all.append(WeighComponent(kind: .food(id), grams: pending(gross: gross)))
        }
        return all.compactMap { component in
            guard case .food(let id) = component.kind,
                  let food = foods.first(where: { $0.id == id }), food.baseDoseAmount > 0 else { return nil }
            return RecipeItem(foodItemID: id, quantity: food.quantity(forGrams: Double(component.grams)))
        }
    }
}
