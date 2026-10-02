import SwiftUI

/// Landing page for everything food-related: today's water and coffee, then the meal plan,
/// recipes, the food catalog and supplements. Each is its own dedicated page; stores and stocks are managed from Settings.
struct FoodLibraryView: View {
    @Environment(HealthKitManager.self) private var healthKit
    @State private var showingLogWater = false

    var body: some View {
        List {
            DrinksSections(showingLogWater: $showingLogWater)

            Section {
                NavigationLink {
                    MealPlanView()
                } label: {
                    Label("Plano Alimentar", systemImage: "list.clipboard")
                }
            } footer: {
                Text("O plano do nutricionista, com cada refeição ligada a uma receita que podes registar diretamente.")
            }

            Section {
                NavigationLink {
                    RecipesListView()
                } label: {
                    Label("Receitas", systemImage: "list.bullet.rectangle")
                }
            }

            Section {
                NavigationLink {
                    FoodCatalogListView()
                } label: {
                    Label("Catálogo de Alimentos", systemImage: "carrot")
                }
            }

            Section {
                NavigationLink {
                    SupplementsListView()
                } label: {
                    Label("Suplementos", systemImage: "pills.fill")
                }
            } footer: {
                Text("Proteínas, géis energéticos, isotónicos, eletrólitos e outros suplementos, com stock e preço. As lojas e os stocks gerem-se nas Definições.")
            }
        }
        .navigationTitle("Alimentos")
        .trackScreen("Alimentos")
        // No refresh on appear: today's water and coffee are already loaded by "Hoje" at launch,
        // and a short refresh here would replace the longer history other tabs loaded.
        .refreshable {
            Haptics.light()
            await healthKit.refresh()
        }
        .sheet(isPresented: $showingLogWater) {
            LogWaterView()
        }
    }
}

#Preview {
    NavigationStack {
        FoodLibraryView()
    }
    .environment(DataStore())
    .environment(HealthKitManager())
}
