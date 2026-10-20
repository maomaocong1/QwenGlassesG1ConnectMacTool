import CoreBluetooth
import Foundation

struct DiscoveredDevice: Identifiable {
    let id: UUID // peripheral.identifier（CoreBluetooth 随机 UUID，非 MAC）
    var name: String
    var rssi: Int
    var connectable: Bool
    var advertisedServices: [String]
    var manufacturerHex: String
    var possibleMAC: String?
    var rawAdvDescription: String
    var lastSeen: Date
    let peripheral: CBPeripheral

    var isGlassesCandidate: Bool {
        let n = name.lowercased()
        return n.contains("qwen") || n.contains("g1") || n.contains("quark") || n.contains("glass")
    }
}

final class BLEScanner: NSObject, ObservableObject {
    @Published var centralState: CBManagerState = .unknown
    @Published var devices: [DiscoveredDevice] = []
    @Published var scanning = false
    @Published var filterText = ""
    @Published var onlyMatching = true
    @Published var connection: BLEConnection?

    private var central: CBCentralManager!
    private let log = LogStore.shared

    var filteredDevices: [DiscoveredDevice] {
        devices
            .filter { d in
                if onlyMatching && !d.isGlassesCandidate { return false }
                if filterText.isEmpty { return true }
                return d.name.localizedCaseInsensitiveContains(filterText)
            }
            .sorted { $0.rssi > $1.rssi }
    }

    var bestCandidate: DiscoveredDevice? {
        filteredDevices.filter(\.isGlassesCandidate).max { $0.rssi < $1.rssi }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var stateMessage: String {
        switch centralState {
        case .poweredOn: return "蓝牙就绪"
        case .poweredOff: return "蓝牙已关闭，请在系统设置中打开蓝牙"
        case .unauthorized: return "未获得蓝牙权限，请在 系统设置 > 隐私与安全性 > 蓝牙 中允许本 App"
        case .unsupported: return "此设备不支持蓝牙 LE"
        case .resetting: return "蓝牙重置中…"
        default: return "蓝牙状态未知…"
        }
    }

    func startScan() {
        guard centralState == .poweredOn else {
            log.log(.sys, tag: "SCAN", "无法扫描：\(stateMessage)")
            return
        }
        devices.removeAll()
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        scanning = true
        log.log(.sys, tag: "SCAN", "开始 BLE 扫描…")
    }

    func stopScan() {
        central.stopScan()
        scanning = false
        log.log(.sys, tag: "SCAN", "停止扫描")
    }

    func connect(to device: DiscoveredDevice) {
        if let existing = connection, existing.peripheral.identifier != device.peripheral.identifier {
            disconnect()
        }
        let conn = BLEConnection(peripheral: device.peripheral)
        connection = conn
        conn.stateText = "连接中…"
        log.log(.sys, tag: "CONN", "正在连接 \(device.name) (\(device.peripheral.identifier.uuidString))…")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let conn = connection else { return }
        log.log(.sys, tag: "CONN", "主动断开 \(conn.name)")
        central.cancelPeripheralConnection(conn.peripheral)
        connection = nil
    }
}

extension BLEScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        centralState = central.state
        log.log(.sys, tag: "SCAN", "中央管理器状态: \(central.state.rawValue) (\(stateMessage))")
        if central.state == .poweredOn && !scanning {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "(未知名称)"

        var services: [String] = []
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            services = uuids.map(\.uuidString)
        }

        var manufacturerHex = ""
        var possibleMAC: String?
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            manufacturerHex = mfg.hexString
            possibleMAC = extractPossibleMAC(from: mfg)
        }

        var rawParts: [String] = []
        for (key, value) in advertisementData.sorted(by: { $0.key < $1.key }) {
            let v: String
            if let d = value as? Data { v = d.hexString }
            else if let arr = value as? [CBUUID] { v = arr.map(\.uuidString).joined(separator: ",") }
            else { v = String(describing: value) }
            rawParts.append("\(key)=\(v)")
        }

        if let idx = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[idx].rssi = RSSI.intValue
            devices[idx].lastSeen = Date()
            devices[idx].name = name
        } else {
            log.log(.rx, tag: "ADV", "\(name) RSSI=\(RSSI) services=[\(services.joined(separator: ","))] mfg=[\(manufacturerHex)]")
            devices.append(DiscoveredDevice(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true,
                advertisedServices: services,
                manufacturerHex: manufacturerHex,
                possibleMAC: possibleMAC,
                rawAdvDescription: rawParts.joined(separator: "\n"),
                lastSeen: Date(),
                peripheral: peripheral
            ))
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.log(.sys, tag: "CONN", "连接失败: \(error?.localizedDescription ?? "未知错误")")
        if connection?.peripheral.identifier == peripheral.identifier {
            connection?.markDisconnected("连接失败")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.log(.sys, tag: "CONN", "已连接 \(peripheral.name ?? peripheral.identifier.uuidString)")
        if connection?.peripheral.identifier == peripheral.identifier {
            connection?.markConnected()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.log(.sys, tag: "CONN", "连接断开 \(peripheral.name ?? "")\(error != nil ? ": \(error!.localizedDescription)" : "")")
        if connection?.peripheral.identifier == peripheral.identifier {
            connection?.markDisconnected("已断开")
            connection = nil
        }
    }
}
