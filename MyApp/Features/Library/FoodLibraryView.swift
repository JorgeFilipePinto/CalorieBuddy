import SwiftUI

/// Landing page for everything food-related: today's water and coffee, then the meal plan,
/// recipes, the food catalog and supplements. Each is its own dedicated page; stores and stocks are managed from Settings.
struct FoodLibraryView: View {
    @Environment(PlatformSyncManager.self) private var platform
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
                    PantryHubView()
                } label: {
                    Label("Despensa e Marmitas", systemImage: "refrigerator")
                }
            } footer: {
                Text("O stock de comida em casa, com validades, e o planeamento de marmitas com a lista de compras.")
            }

            Section {
                NavigationLink {
                    KitchenScaleView()
                } label: {
                    Label("Balança", systemImage: "scalemass")
                }
            } footer: {
                Text("Liga a balança de cozinha Prozis Bit Scale por Bluetooth para pesar os alimentos ao registá-los.")
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
            await platform.refresh()
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
