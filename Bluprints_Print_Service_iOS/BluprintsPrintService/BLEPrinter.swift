import Foundation
import Combine
import CoreBluetooth

// CBCentralManager and all timers use the main queue. Swift 5 language mode.
final class BLEPrinter: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
    static let readID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")
    static let writeID = CBUUID(string: "0000ffe3-0000-1000-8000-00805f9b34fb")
    struct Found: Identifiable { let peripheral: CBPeripheral; let name: String; let rssi: Int; var id: UUID { peripheral.identifier } }
    @Published var devices: [Found] = []
    @Published var status = "Bluetooth starting…"
    @Published var ready = false
    @Published var busy = false
    @Published var scanning = false
    @Published var connecting = false
    @Published var poweredOn = false
    @Published var canRead = false
    @Published var progress = 0.0
    @Published var logs: [String] = []
    @Published var selectedName = "No printer"
    @Published var chunkBytes = 20
    @Published var delayMS = 30
    @Published var sentIDs: [String] = UserDefaults.standard.stringArray(forKey: "sentJobIDs") ?? []
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var reader: CBCharacteristic?
    private var packet: Data = Data()
    private var position = 0
    private var pendingLength = 0
    private var activeID = ""
    private var writeType: CBCharacteristicWriteType = .withResponse
    private var writeLimit = 20
    private var gap: Double = 0.03
    private var nextWork: DispatchWorkItem?
    private var deadline: Timer?
    private var scanTimer: Timer?
    private var readPending = false
    var onSent: ((String) -> Void)?

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func log(_ value: String) {
        logs.append(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium) + " " + value)
        if logs.count > 150 { logs.removeFirst(logs.count - 150) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        poweredOn = central.state == .poweredOn
        if poweredOn { status = "Bluetooth ready — scan for your printer" }
        else {
            stopScan(); clearConnection()
            switch central.state {
            case .poweredOff: status = "Turn Bluetooth on in Settings"
            case .unauthorized: status = "Allow Bluetooth for Bluprints in Settings"
            case .unsupported: status = "BLE unavailable on this device"
            default: status = "Bluetooth unavailable"
            }
        }
    }
    func scan() {
        guard poweredOn, !busy, !connecting, !ready else { return }
        stopScan(); devices = []; scanning = true; status = "Scanning for 12 seconds…"
        // Unfiltered scan also finds printers that omit FFE1 from advertisements.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in self?.stopScan() }
    }
    func stopScan() { central?.stopScan(); scanTimer?.invalidate(); scanTimer = nil; scanning = false }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, !devices.contains(where: { $0.id == p.identifier }) else { return }
        devices.append(Found(peripheral: p, name: (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "Unnamed BLE device", rssi: RSSI.intValue))
    }
    func connect(_ item: Found) {
        guard poweredOn, !busy, !connecting, !ready else { return }
        stopScan(); peripheral = item.peripheral; peripheral?.delegate = self; selectedName = item.name
        connecting = true; status = "Connecting to \(item.name)…"
        central.connect(item.peripheral)
        armTimeout(seconds: 20, message: "Connection/service discovery timed out")
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p === peripheral else { return }; status = "Discovering printer service…"; p.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard p === peripheral else { return }; fail(error?.localizedDescription ?? "Connection failed")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p === peripheral else { return }
        let partial = busy; clearConnection(); status = partial ? "Disconnected during transfer — check partial output" : "Disconnected"
        log(status + (error.map { ": " + $0.localizedDescription } ?? ""))
    }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p === peripheral else { return }
        if let error = error { fail(error.localizedDescription); return }
        guard let service = p.services?.first(where: { $0.uuid == Self.service }) else { fail("FFE1 service not found. Select a compatible Bluprints printer."); return }
        p.discoverCharacteristics([Self.readID, Self.writeID], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p === peripheral else { return }
        if let error = error { fail(error.localizedDescription); return }
        writer = service.characteristics?.first(where: { $0.uuid == Self.writeID })
        reader = service.characteristics?.first(where: { $0.uuid == Self.readID })
        guard let w = writer, w.properties.contains(.write) || w.properties.contains(.writeWithoutResponse) else { fail("FFE3 does not support writes"); return }
        writeType = w.properties.contains(.write) ? .withResponse : .withoutResponse
        if let r = reader, r.properties.contains(.notify) || r.properties.contains(.indicate) { p.setNotifyValue(true, for: r) }
        canRead = reader?.properties.contains(.read) == true
        deadline?.invalidate(); deadline = nil; connecting = false; ready = true
        status = "Connected to \(selectedName)"; log(status)
        log("Write mode: \(writeType == .withResponse ? "with response" : "without response")")
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }; log(error.map { "Notifications: " + $0.localizedDescription } ?? "Notification state: \(characteristic.isNotifying)")
    }
    func readOnce() {
        guard ready, !busy, !readPending, let p = peripheral, let r = reader, canRead else { return }
        readPending = true; p.readValue(for: r)
        armTimeout(seconds: 10, message: "Read timed out")
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral else { return }
        if readPending { readPending = false; deadline?.invalidate(); deadline = nil }
        if let error = error { log("Read: " + error.localizedDescription); return }
        if let d = characteristic.value {
            log("RX \(d.count) bytes: " + d.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " ") + (d.count > 256 ? " …" : ""))
        }
    }
    func send(_ job: PrintJob) {
        guard ready, !busy, !readPending, let p = peripheral, writer != nil else { log("Connect first and wait for any read to complete"); return }
        packet = job.bytes; activeID = job.id; position = 0; pendingLength = 0; progress = 0; busy = true
        writeLimit = max(1, min(max(1, min(chunkBytes, 512)), p.maximumWriteValueLength(for: writeType)))
        gap = Double(max(0, min(delayMS, 1000))) / 1000.0
        status = "Sending \(packet.count) bytes…"; log(status)
        armTimeout(seconds: 15, message: "BLE write stalled; check partial output before retrying")
        pump()
    }
    private func pump() {
        guard busy, let p = peripheral, let w = writer, p.state == .connected, pendingLength == 0 else { return }
        if position == packet.count { finish(); return }
        if writeType == .withoutResponse && !p.canSendWriteWithoutResponse { return }
        let length = min(writeLimit, packet.count - position)
        let chunk = packet.subdata(in: position..<(position + length))
        if writeType == .withResponse {
            pendingLength = length; p.writeValue(chunk, for: w, type: .withResponse)
        } else {
            p.writeValue(chunk, for: w, type: .withoutResponse); position += length; progressed(); schedule()
        }
    }
    private func progressed() {
        progress = Double(position) / Double(packet.count)
        armTimeout(seconds: 15, message: "BLE write stalled; check partial output before retrying")
    }
    private func schedule() {
        nextWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pump() }; nextWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard p === peripheral, characteristic.uuid == Self.writeID, busy, pendingLength > 0 else { return }
        if let error = error { fail("Write failed: " + error.localizedDescription + ". Check partial output."); return }
        position += pendingLength; pendingLength = 0; progressed(); schedule()
    }
    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        guard p === peripheral, busy, writeType == .withoutResponse else { return }; schedule()
    }
    private func finish() {
        deadline?.invalidate(); deadline = nil; nextWork?.cancel(); busy = false; progress = 1
        let id = activeID
        sentIDs.removeAll { $0 == id }; sentIDs.append(id); if sentIDs.count > 100 { sentIDs.removeFirst(sentIDs.count - 100) }
        UserDefaults.standard.set(sentIDs, forKey: "sentJobIDs")
        packet = Data(); activeID = ""
        status = writeType == .withResponse ? "BLE transfer completed — verify printed output" : "Bytes queued to BLE — verify printed output"
        log(status); onSent?(id)
    }
    func disconnect() {
        stopScan(); let old = peripheral; let partial = busy; clearConnection()
        if let old = old { central.cancelPeripheralConnection(old) }
        status = partial ? "Transfer cancelled — some bytes may already have printed" : "Disconnected"; log(status)
    }
    private func clearConnection() {
        nextWork?.cancel(); nextWork = nil; deadline?.invalidate(); deadline = nil
        ready = false; busy = false; connecting = false; canRead = false; readPending = false
        pendingLength = 0; packet = Data(); activeID = ""; writer = nil; reader = nil; peripheral = nil
    }
    private func fail(_ message: String) {
        let old = peripheral; clearConnection(); if let old = old { central.cancelPeripheralConnection(old) }; status = message; log(message)
    }
    private func armTimeout(seconds: Double, message: String) {
        deadline?.invalidate(); deadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.fail(message) }
    }
    func enteredBackground() {
        stopScan()
        if busy || connecting { fail("App moved to background. Transfer/connection stopped; check partial output before retrying.") }
    }
}
