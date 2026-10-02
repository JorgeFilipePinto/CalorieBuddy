import SwiftUI
#if canImport(VisionKit) && os(iOS)
import VisionKit
#endif

/// Presents a live camera view for scanning a barcode. Falls back to manual text entry when
/// scanning isn't supported on this device (e.g. the Simulator, or a platform without a camera).
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void
    /// Whether a successful scan dismisses this view on its own. Defaults to `true`, matching
    /// every call site that presents this as its own standalone sheet. Pass `false` when this
    /// view is instead swapped out for other content by a parent driving a multi-step flow
    /// (e.g. `ScanAndLogEntryView`) — there, dismissing here would close the whole flow instead
    /// of advancing to its next step.
    var dismissesAfterScan: Bool = true

    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            Group {
                #if canImport(VisionKit) && os(iOS)
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable(onScan: handleScan)
                        .ignoresSafeArea()
                } else {
                    manualEntryForm
                }
                #else
                manualEntryForm
                #endif
            }
            .navigationTitle("Digitalizar Código")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private var manualEntryForm: some View {
        Form {
            Section {
                Text("A câmara não está disponível para digitalizar códigos de barras. Introduz o código manualmente.")
                    .foregroundStyle(.secondary)
            }
            Section("Código de Barras") {
                TextField("Ex: 5601234567890", text: $manualCode)
                    .keyboardType(.numberPad)
            }
            Section {
                Button("Usar Código") {
                    handleScan(manualCode.trimmingCharacters(in: .whitespaces))
                }
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func handleScan(_ code: String) {
        guard !code.isEmpty else { return }
        onScan(code)
        if dismissesAfterScan {
            dismiss()
        }
    }
}

#if canImport(VisionKit) && os(iOS)
private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var didDeliver = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didDeliver else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didDeliver = true
                    onScan(payload)
                    break
                }
            }
        }
    }
}
#endif

#Preview {
    BarcodeScannerView { _ in }
}
