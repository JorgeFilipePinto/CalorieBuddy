import Foundation

/// Builds the "Plano Alimentar Junho 26" meal plan (Cláudia Maranhoto, prescribed 06/07/2026),
/// with one recipe per option and the catalog foods those recipes need.
///
/// Nutrition values are generic reference values (per 100 g/ml unless noted) — they're meant to
/// be adjusted in the catalog to the actual brands bought.
enum MealPlanSeed {
    struct Result {
        /// Foods that didn't exist in the catalog yet and must be added.
        var newFoods: [FoodItem]
        var recipes: [Recipe]
        var plan: MealPlan
    }

    static func build(existingFoods: [FoodItem]) -> Result {
        var catalog = FoodResolver(existingFoods: existingFoods)

        // MARK: Foods

        let leite = catalog.food("Leite Meio-Gordo", .milliliter, dose: 200, calories: 46, protein: 3.3, carbs: 4.8, fat: 1.6)
        let leiteProteico = catalog.food("Leite Proteico", .milliliter, dose: 330, calories: 54, protein: 6, carbs: 4.8, fat: 1.2)
        let iogurte = catalog.food("Iogurte Proteico", .gram, dose: 200, calories: 58, protein: 10, carbs: 4, fat: 0.2)
        let whey = catalog.food("Proteína em Pó (Whey)", .gram, dose: 30, calories: 390, protein: 78, carbs: 7, fat: 5.5)
        let fruta = catalog.food("Fruta (peça média)", .unit, dose: 1, basis: .perDose, calories: 80, protein: 0.6, carbs: 19, fat: 0.3)
        let banana = catalog.food("Banana", .unit, dose: 1, basis: .perDose, calories: 105, protein: 1.3, carbs: 27, fat: 0.3)
        let sopa = catalog.food("Sopa de Legumes", .gram, dose: 300, calories: 35, protein: 1.3, carbs: 5, fat: 1)
        let frango = catalog.food("Peito de Frango (cru)", .gram, dose: 125, calories: 110, protein: 23, carbs: 0, fat: 2)
        let pescada = catalog.food("Pescada (crua)", .gram, dose: 140, calories: 78, protein: 17, carbs: 0, fat: 1)
        let arroz = catalog.food("Arroz Cozido", .gram, dose: 150, calories: 130, protein: 2.7, carbs: 28, fat: 0.3)
        let massa = catalog.food("Massa Cozida", .gram, dose: 150, calories: 150, protein: 5.5, carbs: 30, fat: 0.9)
        let batata = catalog.food("Batata Cozida", .gram, dose: 250, calories: 78, protein: 1.9, carbs: 17, fat: 0.1)
        let vegetais = catalog.food("Vegetais Variados", .gram, dose: 150, calories: 30, protein: 2, carbs: 4, fat: 0.3)
        let sementes = catalog.food("Mix de Sementes (abóbora, girassol, linhaça, chia)", .gram, dose: 10, calories: 550, protein: 22, carbs: 10, fat: 45)
        let azeite = catalog.food("Azeite", .gram, dose: 5, calories: 900, protein: 0, carbs: 0, fat: 100)
        let psyllium = catalog.food("Psyllium", .gram, dose: 5, calories: 200, protein: 1.5, carbs: 1.5, fat: 0.6)
        let canela = catalog.food("Canela em Pó", .gram, dose: 2, calories: 250, protein: 4, carbs: 55, fat: 1.2)
        let ovo = catalog.food("Ovo", .unit, dose: 1, basis: .perDose, calories: 78, protein: 6.5, carbs: 0.5, fat: 5.5)
        let claras = catalog.food("Claras de Ovo", .gram, dose: 100, calories: 48, protein: 10.5, carbs: 0.7, fat: 0.2)
        let pao = catalog.food("Pão Integral (fatia)", .gram, dose: 35, calories: 245, protein: 10, carbs: 41, fat: 3.5)
        let queijo = catalog.food("Queijo Flamengo Light (fatia)", .gram, dose: 20, calories: 270, protein: 30, carbs: 0, fat: 17)
        let bolachas = catalog.food("Bolachas de Arroz", .gram, dose: 8, calories: 385, protein: 8, carbs: 80, fat: 3)
        let aveia = catalog.food("Aveia", .gram, dose: 40, calories: 370, protein: 13, carbs: 60, fat: 7)
        let amendoim = catalog.food("Manteiga de Amendoim", .gram, dose: 15, calories: 600, protein: 25, carbs: 15, fat: 50)
        let chocolate = catalog.food("Chocolate Negro 60% Cacau", .gram, dose: 30, calories: 550, protein: 7, carbs: 45, fat: 36)
        let mel = catalog.food("Mel", .gram, dose: 10, calories: 304, protein: 0.3, carbs: 82, fat: 0)

        // MARK: Recipes

        var recipes: [Recipe] = []
        /// Creates a recipe from `(food, amount)` pairs, where amount is in the food's base unit
        /// (g, ml or units) — converted to a number of doses of that food.
        func recipe(_ name: String, _ ingredients: [(FoodItem, Double)]) -> UUID {
            let recipe = Recipe(
                name: name,
                items: ingredients.map { food, amount in
                    RecipeItem(foodItemID: food.id, quantity: amount / (food.doseSize * food.unit.baseMultiplier))
                }
            )
            recipes.append(recipe)
            return recipe.id
        }

        let galao = recipe("Galão", [(leite, 200)])

        let mmIogurte = recipe("Fruta + Iogurte Proteico", [(fruta, 1), (iogurte, 200)])
        let mmWhey = recipe("Fruta + Proteína em Pó", [(fruta, 1), (whey, 30)])
        let mmLeite = recipe("Fruta + Leite Proteico", [(fruta, 1), (leiteProteico, 330)])

        let proteins: [(name: String, food: FoodItem, amount: Double)] = [
            ("Frango", frango, 125),
            ("Pescada", pescada, 140)
        ]
        let sides: [(name: String, food: FoodItem, amount: Double)] = [
            ("Arroz", arroz, 150),
            ("Massa", massa, 150),
            ("Batata", batata, 250)
        ]
        let plateBase: [(FoodItem, Double)] = [(vegetais, 150), (sementes, 10), (azeite, 5)]

        var lunchOptions: [MealPlanOption] = []
        var dinnerOptions: [MealPlanOption] = []
        for protein in proteins {
            for side in sides {
                let plate = [(protein.food, protein.amount), (side.food, side.amount)] + plateBase
                let dishName = "\(protein.name) com \(side.name)"
                let details = "\(Int(protein.amount)) g \(protein.name.lowercased()) + \(Int(side.amount)) g \(side.name.lowercased()) + vegetais com sementes"
                lunchOptions.append(MealPlanOption(
                    label: dishName,
                    details: "Sopa + " + details,
                    recipeID: recipe("Almoço: \(dishName)", [(sopa, 300)] + plate)
                ))
                dinnerOptions.append(MealPlanOption(
                    label: dishName,
                    details: details,
                    recipeID: recipe("Jantar: \(dishName)", plate)
                ))
            }
        }

        let batido = recipe("Batido Proteico", [(whey, 30), (psyllium, 5), (fruta, 1), (canela, 2)])
        let ovosPao = recipe("Ovos e Claras com Pão Integral e Queijo", [(ovo, 2), (claras, 100), (pao, 35), (queijo, 20)])
        let leiteBolachas = recipe("Leite Proteico com Bolachas de Arroz", [(leiteProteico, 100), (bolachas, 24)])
        let aveiaNoturna = recipe("Aveia Noturna", [(aveia, 20), (amendoim, 10), (whey, 30), (fruta, 1)])
        let mousse = recipe("Mousse de Chocolate Proteica", [(ovo, 2), (leiteProteico, 100), (chocolate, 30)])
        let paoBanana = recipe("Pão com Banana e Mel", [(pao, 70), (banana, 1), (mel, 10)])

        let psylliumNoite = recipe("Psyllium", [(psyllium, 5)])

        // MARK: Plan

        let plan = MealPlan(
            name: "Plano Alimentar Junho 26",
            author: "Cláudia Maranhoto (ON 1386D)",
            prescribedAt: DateComponents(calendar: .current, year: 2026, month: 7, day: 6).date,
            notes: "Intra-treinos: isotónico feito em casa ou comprado. Géis: 30 g a 60 g por hora (ir testando).\n2 l de água por dia.",
            meals: [
                PlannedMeal(
                    name: "Pequeno-almoço",
                    mealType: .breakfast,
                    proteinTarget: 7, carbsTarget: 10, fatTarget: 3,
                    options: [MealPlanOption(label: "Galão", recipeID: galao)]
                ),
                PlannedMeal(
                    name: "Meio da Manhã",
                    mealType: .snack,
                    proteinTarget: 23, carbsTarget: 25,
                    notes: "1 fruta (≈25 g HC) + iogurte proteico, proteína em pó ou leite proteico (≈23 g proteína).",
                    options: [
                        MealPlanOption(label: "Fruta + Iogurte Proteico", recipeID: mmIogurte),
                        MealPlanOption(label: "Fruta + Proteína em Pó", recipeID: mmWhey),
                        MealPlanOption(label: "Fruta + Leite Proteico", recipeID: mmLeite)
                    ]
                ),
                PlannedMeal(
                    name: "Almoço",
                    mealType: .lunch,
                    proteinTarget: 35, carbsTarget: 45, fatTarget: 15,
                    notes: "Sopa. 125 g carne ou 140 g peixe — atenção ao azeite. Arroz ou massa 150 g, ou 250 g batata. Vegetais variados com sementes (abóbora, girassol, linhaça, chia).",
                    options: lunchOptions
                ),
                PlannedMeal(
                    name: "Lanche",
                    mealType: .snack,
                    proteinTarget: 23, carbsTarget: 30, fatTarget: 10,
                    options: [
                        MealPlanOption(label: "Batido Proteico", details: "Batido com proteína + 1 c. chá psyllium + 1 fruta + canela", recipeID: batido),
                        MealPlanOption(label: "Ovos com Pão e Queijo", details: "2 ovos + 100 g claras + 1 fatia pão integral com queijo", recipeID: ovosPao),
                        MealPlanOption(label: "Leite Proteico com Bolachas", details: "100 ml leite proteico + bolachas de arroz/grão", recipeID: leiteBolachas),
                        MealPlanOption(label: "Aveia Noturna", details: "2 c. sopa aveia + manteiga de amendoim + 1 dose de proteína + fruta", recipeID: aveiaNoturna),
                        MealPlanOption(label: "Mousse de Chocolate", details: "2 ovos + 100 ml leite proteico + 30 g chocolate 60% cacau", recipeID: mousse),
                        MealPlanOption(label: "Dias de Treino", details: "2 fatias pão + 1 banana + fio de mel", recipeID: paoBanana)
                    ]
                ),
                PlannedMeal(
                    name: "Jantar",
                    mealType: .dinner,
                    proteinTarget: 23, carbsTarget: 55, fatTarget: 10,
                    notes: "125 g carne ou 140 g peixe — atenção ao azeite. Arroz ou massa 150 g, ou 250 g batata. Vegetais variados com sementes. 1 fruta se treinares.",
                    options: dinnerOptions
                ),
                PlannedMeal(
                    name: "Noite",
                    mealType: .snack,
                    notes: "Só se treinares de tarde.",
                    options: [MealPlanOption(label: "Psyllium", details: "1 c. chá psyllium", recipeID: psylliumNoite)]
                )
            ]
        )

        return Result(newFoods: catalog.newFoods, recipes: recipes, plan: plan)
    }

    /// Hands out catalog foods by name, reusing an existing one with the same name and a
    /// compatible unit (so e.g. the example "Aveia" isn't duplicated) or creating a new one.
    private struct FoodResolver {
        let existingFoods: [FoodItem]
        private(set) var newFoods: [FoodItem] = []

        init(existingFoods: [FoodItem]) {
            self.existingFoods = existingFoods
        }

        mutating func food(
            _ name: String,
            _ unit: MeasurementUnit,
            dose: Double,
            basis: NutritionBasis = .per100,
            calories: Int,
            protein: Double,
            carbs: Double,
            fat: Double
        ) -> FoodItem {
            if let existing = existingFoods.first(where: {
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    && $0.unit.baseUnit == unit.baseUnit
            }) {
                return existing
            }
            let food = FoodItem(
                name: name, unit: unit, doseSize: dose, nutritionBasis: basis,
                calories: calories, protein: protein, carbs: carbs, fat: fat
            )
            newFoods.append(food)
            return food
        }
    }
}
