import Combine
import CoreBluetooth
import Foundation

final class BluetoothManager: NSObject, ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionStateDescription: String = "Starting Bluetooth"
    @Published private(set) var cadenceRpm: Double = 0
    @Published private(set) var speedKph: Double = 0
    @Published private(set) var hasSpeedReading: Bool = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var connectedBikeName: String = ""
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var lastKnownBikeName: String = ""

    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let indoorBikeDataUUID = CBUUID(string: "2AD2")
    private let lastBikeKey = "lastBikeUUID"
    private let lastBikeNameKey = "lastBikeName"

    private var centralManager: CBCentralManager?
    private var bikePeripheral: CBPeripheral?
    private var dataTimeoutTimer: Timer?
    private var lastDataTimestamp: Date?
    private var lastCadenceChangeDate: Date?

    override init() {
        super.init()
        lastKnownBikeName = UserDefaults.standard.string(forKey: lastBikeNameKey) ?? ""
        centralManager = CBCentralManager(delegate: self, queue: nil)
#if DEBUG
        BLELogger.shared.log("BluetoothManager init; log file: \(BLELogger.shared.fileURL.path)")
#endif
        dataTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForStaleData()
        }
    }

    func reconnect() {
        guard let centralManager else { return }
        if centralManager.state == .poweredOn {
            autoConnectOrScan()
        }
    }

    func disconnect() {
        guard let centralManager, let bikePeripheral else { return }
        centralManager.cancelPeripheralConnection(bikePeripheral)
    }

    private func autoConnectOrScan() {
        guard let centralManager else { return }
        if let knownUUIDString = UserDefaults.standard.string(forKey: lastBikeKey),
           let knownUUID = UUID(uuidString: knownUUIDString) {
            let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [knownUUID])
            if let known = knownPeripherals.first {
                connect(to: known)
                return
            }
        }
        startScanning()
    }

    private func startScanning() {
        guard let centralManager else { return }
        updateState(isConnected: false, description: "Scanning for bike")
        centralManager.scanForPeripherals(withServices: [ftmsServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(to peripheral: CBPeripheral) {
        guard let centralManager else { return }
        bikePeripheral = peripheral
        bikePeripheral?.delegate = self
        updateState(isConnected: false, description: "Connecting to \(peripheral.name ?? "Bike")")
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    private func handleCadenceUpdate(_ rpm: Double) {
        DispatchQueue.main.async {
            if abs(self.cadenceRpm - rpm) > 0.1 {
                self.lastCadenceChangeDate = Date()
            }
            self.cadenceRpm = rpm
        }
    }

    private func handleSpeedUpdate(_ kph: Double) {
        DispatchQueue.main.async {
            self.speedKph = kph
            self.hasSpeedReading = true
        }
    }

    private func updateState(isConnected: Bool, description: String) {
        DispatchQueue.main.async {
            self.isConnected = isConnected
            self.connectionStateDescription = description
        }
    }

    private func updateConnectedBikeName(_ name: String) {
        DispatchQueue.main.async {
            self.connectedBikeName = name
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async {
            self.lastErrorMessage = message
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
        }
#if DEBUG
        BLELogger.shared.log("Central state: \(central.state.rawValue)")
#endif
        switch central.state {
        case .poweredOn:
            updateState(isConnected: false, description: "Bluetooth ready")
            autoConnectOrScan()
        case .poweredOff:
            updateState(isConnected: false, description: "Bluetooth off")
        case .unauthorized:
            updateState(isConnected: false, description: "Bluetooth unauthorized")
        case .unsupported:
            updateState(isConnected: false, description: "Bluetooth unsupported")
        default:
            updateState(isConnected: false, description: "Bluetooth unavailable")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
#if DEBUG
        BLELogger.shared.log("Discovered peripheral: \(peripheral.name ?? "Unknown") rssi=\(RSSI)")
#endif
        let knownUUIDString = UserDefaults.standard.string(forKey: lastBikeKey)
        if let knownUUIDString, let knownUUID = UUID(uuidString: knownUUIDString) {
            if peripheral.identifier == knownUUID {
                connect(to: peripheral)
            }
        } else {
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastBikeKey)
        let bikeName = peripheral.name ?? "Bike"
        UserDefaults.standard.set(bikeName, forKey: lastBikeNameKey)
        DispatchQueue.main.async {
            self.lastKnownBikeName = bikeName
        }
        updateConnectedBikeName(bikeName)
        updateState(isConnected: true, description: "Connected to \(bikeName)")
#if DEBUG
        BLELogger.shared.log("Connected to \(bikeName)")
#endif
        peripheral.discoverServices([ftmsServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        setError(error?.localizedDescription ?? "Failed to connect")
        updateState(isConnected: false, description: "Connection failed")
#if DEBUG
        BLELogger.shared.log("Connect failed: \(error?.localizedDescription ?? "unknown")")
#endif
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            setError(error.localizedDescription)
#if DEBUG
            BLELogger.shared.log("Disconnected with error: \(error.localizedDescription)")
#endif
        } else {
#if DEBUG
            BLELogger.shared.log("Disconnected")
#endif
        }
        updateState(isConnected: false, description: "Disconnected")
        lastDataTimestamp = nil
        handleSpeedUpdate(0)
        handleCadenceUpdate(0)
        startScanning()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            setError(error.localizedDescription)
            return
        }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == ftmsServiceUUID {
            peripheral.discoverCharacteristics([indoorBikeDataUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            setError(error.localizedDescription)
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == indoorBikeDataUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            setError(error.localizedDescription)
#if DEBUG
            BLELogger.shared.log("Characteristic error: \(error.localizedDescription)")
#endif
            return
        }
        guard characteristic.uuid == indoorBikeDataUUID, let data = characteristic.value else { return }
        guard data.count >= 4 else { return }

#if DEBUG
        BLELogger.shared.log("IndoorBikeData len=\(data.count) hex=\(data.hexString())")
#endif
        lastDataTimestamp = Date()
        guard let flags = data.readUInt16LE(at: 0) else { return }
        let moreData = (flags & 0x0001) != 0
        var index = 2

        func readUInt16() -> UInt16? {
            guard let value = data.readUInt16LE(at: index) else { return nil }
            index += 2
            return value
        }

        func skip(bytes: Int) -> Bool {
            guard index + bytes <= data.count else { return false }
            index += bytes
            return true
        }

        var speedKph: Double?
        var cadenceRpm: Double?

        // FTMS Indoor Bike Data: instantaneous speed is omitted when the More Data bit is set.
        if !moreData {
            guard let speedRaw = readUInt16() else { return }
            speedKph = Double(speedRaw) / 100.0
        }

        if (flags & 0x0002) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x0004) != 0 {
            guard let raw = readUInt16() else { return }
            cadenceRpm = Double(raw) / 2.0
        }

        if (flags & 0x0008) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x0010) != 0 {
            guard skip(bytes: 3) else { return }
        }

        if (flags & 0x0020) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x0040) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x0080) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x0100) != 0 {
            guard skip(bytes: 5) else { return }
        }

        if (flags & 0x0200) != 0 {
            guard skip(bytes: 1) else { return }
        }

        if (flags & 0x0400) != 0 {
            guard skip(bytes: 1) else { return }
        }

        if (flags & 0x0800) != 0 {
            guard readUInt16() != nil else { return }
        }

        if (flags & 0x1000) != 0 {
            guard readUInt16() != nil else { return }
        }

        if let speedKph {
            handleSpeedUpdate(speedKph)
        }
        if let cadenceRpm {
            handleCadenceUpdate(cadenceRpm)
        }

#if DEBUG
        var parts: [String] = [
            "flags=0x" + String(format: "%04X", flags),
            "moreData=\(moreData ? 1 : 0)"
        ]
        if let speedKph { parts.append(String(format: "speed=%.2fkmh", speedKph)) }
        if let cadenceRpm { parts.append(String(format: "cadence=%.1frpm", cadenceRpm)) }
        BLELogger.shared.log("Parsed " + parts.joined(separator: " "))
#endif
    }

    private func checkForStaleData() {
        guard isConnected, let lastDataTimestamp else { return }
        if Date().timeIntervalSince(lastDataTimestamp) > 2.0 {
            if cadenceRpm != 0 || speedKph != 0 {
                handleCadenceUpdate(0)
                handleSpeedUpdate(0)
#if DEBUG
                BLELogger.shared.log("Stale data -> reset cadence/speed to 0")
#endif
            }
        }

        if speedKph == 0, cadenceRpm > 0 {
            let lastChange = lastCadenceChangeDate ?? lastDataTimestamp
            if Date().timeIntervalSince(lastChange) > 2.0 {
                handleCadenceUpdate(0)
#if DEBUG
                BLELogger.shared.log("Cadence held with zero speed -> reset cadence to 0")
#endif
            }
        }
    }
}

final class BLELogger {
    static let shared = BLELogger()

    let fileURL: URL
    private let queue = DispatchQueue(label: "bikeapp.ble.logger")
    private let formatter = ISO8601DateFormatter()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        fileURL = caches[0].appendingPathComponent("BikeApp-ble-log.txt")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? "BikeApp BLE Log\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } catch {
                        // Swallow write errors to avoid impacting app behavior
                    }
                    do { try handle.close() } catch { /* ignore close errors */ }
                } else {
                    try line.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                // Swallow errors to keep logger non-fatal
            }
        }
    }
}
