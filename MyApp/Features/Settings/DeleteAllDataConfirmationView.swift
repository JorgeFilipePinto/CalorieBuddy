import SwiftUI

/// A destructive confirmation that can't be triggered by an accidental tap: "Sim" only fires
/// after being held down continuously for 5 seconds, with a visible countdown ring so the user
/// always knows exactly how much longer to hold.
struct DeleteAllDataConfirmationView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let holdDuration: Double = 5
    @State private var elapsed: Double = 0
    @State private var pressTask: Task<Void, Never>?
    @State private var didDelete = false

    private var isHolding: Bool { pressTask != nil }

    private var remainingSeconds: Int {
        max(0, Int((holdDuration - elapsed).rounded(.up)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .padding(.top, 12)

                Text("Eliminar Todos os Dados?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Isto elimina permanentemente todos os alimentos, receitas, suplementos, lojas, preços e registos guardados nesta app, incluindo o backup. Esta ação não pode ser desfeita.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                holdToConfirmButton

                Text(
                    didDelete
                        ? "Eliminado."
                        : isHolding
                            ? "A confirmar em \(remainingSeconds)s — larga para cancelar."
                            : "Mantém premido \"Sim\" durante 5 segundos para confirmar."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                Spacer()

                Button("Não, Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(didDelete)
            }
            .padding()
            .navigationTitle("Zona de Perigo")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isHolding)
        }
    }

    private var holdToConfirmButton: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.25), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(elapsed / holdDuration, 1))
                .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: elapsed)

            if didDelete {
                Image(systemName: "checkmark")
                    .font(.title.bold())
                    .foregroundStyle(.red)
            } else if isHolding {
                Text("\(remainingSeconds)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.red)
            } else {
                Text("Sim")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 110, height: 110)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startPressIfNeeded() }
                .onEnded { _ in cancelPress() }
        )
    }

    private func startPressIfNeeded() {
        guard pressTask == nil, !didDelete else { return }
        elapsed = 0
        pressTask = Task {
            let tick = 0.05
            while elapsed < holdDuration {
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                if Task.isCancelled { return }
                elapsed += tick
            }
            store.deleteEverything()
            didDelete = true
            pressTask = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }

    private func cancelPress() {
        guard !didDelete else { return }
        pressTask?.cancel()
        pressTask = nil
        elapsed = 0
    }
}

#Preview {
    DeleteAllDataConfirmationView()
        .environment(DataStore())
}
