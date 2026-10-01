import SwiftUI

/// Settings hub. Every row only navigates — nothing here changes data on a single tap; the
/// operations that export, replace or erase data live one level down, in `DataManagementView`.
struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    NutritionPlansListView()
                } label: {
                    SettingsRowLabel(title: "Planos Alimentares", systemImage: "target", color: .red)
                }
            } header: {
                Text("Nutrição")
            } footer: {
                Text("Define os objetivos diários de calorias, macros e água — com valores diferentes para dias de treino e de descanso, tal como no plano do nutricionista.")
            }

            Section {
                NavigationLink {
                    StoresListView()
                } label: {
                    SettingsRowLabel(title: "Lojas", systemImage: "storefront", color: .orange)
                }
                NavigationLink {
                    StocksListView()
                } label: {
                    SettingsRowLabel(title: "Stocks", systemImage: "shippingbox", color: .brown)
                }
            } header: {
                Text("Compras e Stock")
            } footer: {
                Text("As lojas onde registas os preços dos alimentos e suplementos, e o stock de todos os suplementos por local.")
            }

            Section {
                NavigationLink {
                    PlatformSyncView()
                } label: {
                    SettingsRowLabel(title: "Plataforma e Sincronização", systemImage: "arrow.triangle.2.circlepath.icloud", color: .blue)
                }
            } header: {
                Text("Plataforma")
            } footer: {
                Text("Sincroniza o diário, os planos e os dados da app Saúde com o dashboard da plataforma IronMan Project, com backup de toda a base de dados.")
            }

            Section {
                NavigationLink {
                    DataManagementView()
                } label: {
                    SettingsRowLabel(title: "Gestão de Dados", systemImage: "externaldrive", color: .gray)
                }
            } header: {
                Text("Dados")
            } footer: {
                Text("Exportar, importar ou restaurar a base de dados, editar o JSON e eliminar todos os dados.")
            }
        }
        .navigationTitle("Definições")
        .trackScreen("Definições")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(DataStore())
    .environment(PlatformSyncManager())
}
