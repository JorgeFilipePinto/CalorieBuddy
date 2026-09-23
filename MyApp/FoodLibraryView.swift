import SwiftUI

/// Landing page for everything food-related: recipes, the food catalog, supplements and the
/// stores/prices behind the light financial tracking. Each is its own dedicated page.
struct FoodLibraryView: View {
    var body: some View {
        List {
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
                Text("Proteínas, géis energéticos, isotónicos, eletrólitos e outros suplementos, com stock e preço.")
            }

            Section {
                NavigationLink {
                    StocksListView()
                } label: {
                    Label("Stocks", systemImage: "shippingbox")
                }
            } footer: {
                Text("Todos os stocks de todos os suplementos, num só sítio.")
            }

            Section {
                NavigationLink {
                    StoresListView()
                } label: {
                    Label("Lojas", systemImage: "storefront")
                }
            } footer: {
                Text("Cria, edita ou elimina as lojas onde registas preços dos alimentos e suplementos.")
            }
        }
        .navigationTitle("Alimentos")
    }
}

#Preview {
    NavigationStack {
        FoodLibraryView()
    }
    .environment(DataStore())
}
