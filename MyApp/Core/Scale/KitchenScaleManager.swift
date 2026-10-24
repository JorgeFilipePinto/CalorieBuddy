import Foundation
import Observation

#if canImport(CoreBluetooth) && os(iOS)
import CoreBluetooth
#endif

/// One 6-byte notification of the Prozis Bit Scale: `06 | battery % | battery mV (BE) | grams (i16 BE)`.
/// Protocol reverse-engineered from the official app's Bluetooth traffic.
struct KitchenScaleReading: Equatable {
    var grams: Int
    var batteryPercent: Int
    var batteryMillivolts: Int

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count == 6, b[0] == 0x06 else { return nil }
        batteryPercent = Int(b[1])
        batteryMillivolts = Int(b[2]) << 8 | Int(b[3])
        grams = Int(Int16(bitPattern: UInt16(b[4]) << 8 | UInt16(b[5])))
    }
}

enum KitchenScaleState: Equatable {
    case unavailable(String)
    case idle
    case scanning
    case connecting
    case connected

    var title: String {
        switch self {
        case .unavailable(let reason): return reason
        case .idle: return "Desligada"
        case .scanning: return "A procurar a balança…"
        case .connecting: return "A ligar…"
        case .connected: return "Ligada"
        }
    }
}

#if canImport(CoreBluetooth) && os(iOS)

/// Talks to the Prozis Bit Scale over the Nordic UART Service: enable notifications on TX, write
/// `"gwc"` on RX to start the weight stream, `"st"` to tare. The scale only sends while the weight
/// changes, in bursts of ~90 ms; the last value of a burst is the stable one.
@Observable
final class KitchenScaleManager: NSObject {
    private(set) var state: KitchenScaleState = .idle
    private(set) var reading: KitchenScaleReading?
    private(set) var scaleName: String?

    var isConnected: Bool { state == .connected }
    /// Weight in grams, `nil` until the scale has sent one.
    var grams: Int? { reading?.grams }
    /// Grams tared away so far: the scale zeroes itself on every tare, so the sum is tracked here.
    private(set) var tareGrams = 0
    /// Tare + the scale's (net) reading: where the weight sits on the whole 0–2 kg scale.
    var grossGrams: Int { max(0, tareGrams + (reading?.grams ?? 0)) }
    /// The total to tare once the scale confirms with its next reading (it sends 0 about a second later).
    private var pendingTare: Int?

    private static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    private static let rxUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private static let txUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
    private static let lastScaleKey = "CalorieBuddy.kitchenScaleID"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    /// A connection was asked for before Bluetooth was ready.
    private var wantsConnection = false

    /// Starts looking for the scale (asks for Bluetooth permission the first time).
    func connect() {
        wantsConnection = true
        guard let central else {
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        startIfReady(central)
    }

    func disconnect() {
        wantsConnection = false
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        rx = nil
        reading = nil
        tareGrams = 0
        pendingTare = nil
        state = central?.state == .poweredOn ? .idle : state
    }

    /// Zeroes the scale itself; the readings that follow are already net.
    func tare() {
        guard reading != nil else { return }
        pendingTare = grossGrams
        write("st")
    }

    /// Forget every tare and take whatever is on the scale now as zero (the scale zeroes itself too).
    func resetToZero() {
        guard var current = reading else { return }
        current.grams = 0
        reading = current
        tareGrams = 0
        pendingTare = 0
        write("st")
    }

    private func write(_ command: String) {
        guard let peripheral, let rx else { return }
        peripheral.writeValue(Data(command.utf8), for: rx, type: .withResponse)
    }

    private func startIfReady(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard wantsConnection, state != .connected, state != .connecting else { return }
            if let id = UserDefaults.standard.string(forKey: Self.lastScaleKey).flatMap(UUID.init(uuidString:)),
               let known = central.retrievePeripherals(withIdentifiers: [id]).first {
                open(known)
            } else if let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
                .first(where: Self.isScale) {
                open(connected)
            } else {
                state = .scanning
                central.scanForPeripherals(withServices: [Self.serviceUUID])
            }
        case .unauthorized:
            state = .unavailable("Sem permissão de Bluetooth. Ativa-a nas Definições do iPhone.")
        case .poweredOff:
            state = .unavailable("O Bluetooth está desligado.")
        case .unsupported:
            state = .unavailable("Este aparelho não suporta Bluetooth.")
        default:
            break
        }
    }

    nonisolated private static func isScale(_ peripheral: CBPeripheral) -> Bool {
        peripheral.name?.localizedCaseInsensitiveContains("Bit Scale") ?? false
    }

    private func open(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        scaleName = peripheral.name
        state = .connecting
        central?.stopScan()
        central?.connect(peripheral)
    }

    private func lost() {
        peripheral = nil
        rx = nil
        reading = nil
        tareGrams = 0
        pendingTare = nil
        state = .idle
    }
}

extension KitchenScaleManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state != .poweredOn, state == .connected || state == .connecting { lost() }
            startIfReady(central)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil, wantsConnection else { return }
            open(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastScaleKey)
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated { lost() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            let retry = wantsConnection && error != nil
            lost()
            // The scale switches itself off when idle; reconnect only when it was not us who left.
            if retry { startIfReady(central) }
        }
    }
}

extension KitchenScaleManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                state = .unavailable("Esta balança não é uma Prozis Bit Scale.")
                return
            }
            peripheral.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let tx = service.characteristics?.first(where: { $0.uuid == Self.txUUID }),
                  let rx = service.characteristics?.first(where: { $0.uuid == Self.rxUUID }) else { return }
            self.rx = rx
            peripheral.setNotifyValue(true, for: tx)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, characteristic.isNotifying else { return }
            // Without this command the scale stays silent.
            write("gwc")
            state = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == Self.txUUID, let data = characteristic.value,
                  let next = KitchenScaleReading(data) else { return }
            reading = next
            if let pendingTare {
                tareGrams = pendingTare
                self.pendingTare = nil
            }
        }
    }
}

#else

/// Bluetooth scales are iOS-only; elsewhere the manager does nothing.
@Observable
final class KitchenScaleManager {
    private(set) var state: KitchenScaleState = .unavailable("Disponível apenas no iPhone.")
    private(set) var reading: KitchenScaleReading?
    private(set) var scaleName: String?
    var isConnected: Bool { false }
    var grams: Int? { nil }
    var tareGrams: Int { 0 }
    var grossGrams: Int { 0 }
    func connect() {}
    func disconnect() {}
    func tare() {}
    func resetToZero() {}
}

#endif
