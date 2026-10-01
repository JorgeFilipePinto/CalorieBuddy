import SwiftUI

/// A Settings row label in the style of the system Settings app: a white symbol on a coloured
/// rounded square, then the title in the primary text colour. The app's accent is the IRONMAN red,
/// so plain buttons would all render red and look destructive; this keeps red for what really is.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var isDestructive = false

    /// The forced text colour would otherwise hide that a button is disabled.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(isEnabled ? (isDestructive ? Color.red : Color.primary) : Color.secondary)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

#Preview {
    List {
        SettingsRowLabel(title: "Lojas", systemImage: "storefront", color: .orange)
        SettingsRowLabel(title: "Eliminar Todos os Dados", systemImage: "trash.fill", color: .red, isDestructive: true)
    }
}
