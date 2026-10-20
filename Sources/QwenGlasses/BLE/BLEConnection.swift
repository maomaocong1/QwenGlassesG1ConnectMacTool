import CoreBluetooth
import Foundation

struct GattCharItem: Identifiable {
    let id = UUID()
    let cb: CBCharacteristic
    var valueHex: String?
    var notifyError: String?
    var notifying: Bool = false

    var uuid: String { cb.uuid.uuidString }
    var propsString: String {
        var p: [String] = []
        if cb.properties.contains(.read) { p.append("读") }
        if cb.properties.contains(.writeWithoutResponse) { p.append("写(无响应)") }
        if cb.properties.contains(.write) { p.append("写") }
        if cb.properties.contains(.notify) { p.append("通知") }
        if cb.properties.contains(.indicate) { p.append("指示") }
        if cb.properties.contains(.broadcast) { p.append("广播") }
        return p.joined(separator: " ")
    }
}

struct GattServiceItem: Identifiable {
    let id = UUID()
    let cb: CBService
    var chars: [GattCharItem] = []
    var uuid: String { cb.uuid.uuidString }
}

final class BLEConnection: NSObject, ObservableObject {
    @Published var stateText = "未连接"
    @Published var isConnected = false
    @Published var services: [GattServiceItem] = []
    @Published var mtu: Int = 0

    let peripheral: CBPeripheral
    private let log = LogStore.shared

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    var name: String { peripheral.name ?? "未知设备" }

    func read(_ c: CBCharacteristic) {
        log.log(.tx, tag: "GATT", "读取 \(c.uuid.uuidString)")
        peripheral.readValue(for: c)
    }

    func writeHex(_ hex: String, to c: CBCharacteristic, withResponse: Bool) {
        guard let data = Data.from(hexString: hex), !data.isEmpty else {
            log.log(.sys, tag: "GATT", "无效的 hex 输入: \(hex)")
            return
        }
        let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        log.log(.tx, tag: "GATT", "写入 \(c.uuid.uuidString) [\(data.hexString)] (\(data.count) 字节, response=\(withResponse))")
        peripheral.writeValue(data, for: c, type: type)
    }

    func toggleNotify(_ c: CBCharacteristic) {
        let enable = !c.isNotifying
        log.log(.tx, tag: "GATT", "\(enable ? "订阅" : "取消订阅") \(c.uuid.uuidString)")
        peripheral.setNotifyValue(enable, for: c)
    }

    func readAll() {
        for s in services {
            for item in s.chars where item.cb.properties.contains(.read) {
                read(item.cb)
            }
        }
    }

    func subscribeAllNotifications() {
        var count = 0
        for s in services {
            for item in s.chars
            where (item.cb.properties.contains(.notify) || item.cb.properties.contains(.indicate))
                && !item.cb.isNotifying {
                log.log(.tx, tag: "GATT", "订阅 \(item.cb.uuid.uuidString)")
                peripheral.setNotifyValue(true, for: item.cb)
                count += 1
            }
        }
        if count == 0 {
            log.log(.sys, tag: "GATT", "没有可新订阅的通知特征")
        }
    }

    func markConnected() {
        stateText = "已连接"
        isConnected = true
        mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        log.log(.rx, tag: "GATT", "MTU(写上限) = \(mtu) 字节，开始发现服务…")
        peripheral.discoverServices(nil)
    }

    func markDisconnected(_ reason: String?) {
        stateText = reason ?? "已断开"
        isConnected = false
        services = []
    }
}

extension BLEConnection: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log.log(.rx, tag: "GATT", "服务发现失败: \(error.localizedDescription)")
            return
        }
        guard let svcs = peripheral.services else { return }
        log.log(.rx, tag: "GATT", "发现 \(svcs.count) 个服务: \(svcs.map(\.uuid.uuidString).joined(separator: ", "))")
        services = svcs.map { GattServiceItem(cb: $0) }
        for s in svcs {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            log.log(.rx, tag: "GATT", "特征发现失败 \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        guard let idx = services.firstIndex(where: { $0.cb === service || $0.cb.uuid == service.uuid }),
              let chars = service.characteristics else { return }
        log.log(.rx, tag: "GATT", "服务 \(service.uuid.uuidString): \(chars.count) 个特征 [\(chars.map(\.uuid.uuidString).joined(separator: ", "))]")
        services[idx].chars = chars.map { GattCharItem(cb: $0) }
        // 自动读取所有可读特征，便于逆向
        for c in chars where c.properties.contains(.read) {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let idx = characteristicIndex(characteristic) else { return }
        if let error {
            log.log(.rx, tag: "GATT", "读取失败 \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            services[idx.0].chars[idx.1].valueHex = nil
            services[idx.0].chars[idx.1].notifyError = error.localizedDescription
            return
        }
        let data = characteristic.value ?? Data()
        services[idx.0].chars[idx.1].valueHex = data.hexString
        services[idx.0].chars[idx.1].notifyError = nil
        log.log(.rx, tag: "GATT", "值更新 \(characteristic.uuid.uuidString) [\(data.count) 字节]: \(data.hexString) | ascii: \(data.asciiPreview)")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log.log(.rx, tag: "GATT", "写入失败 \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            log.log(.rx, tag: "GATT", "写入成功 \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let idx = characteristicIndex(characteristic) else { return }
        services[idx.0].chars[idx.1].notifying = characteristic.isNotifying
        if let error {
            log.log(.rx, tag: "GATT", "订阅状态更新失败 \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            log.log(.rx, tag: "GATT", "\(characteristic.isNotifying ? "已订阅" : "已退订") \(characteristic.uuid.uuidString)")
        }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        objectWillChange.send()
    }

    private func characteristicIndex(_ c: CBCharacteristic) -> (Int, Int)? {
        for (si, s) in services.enumerated() {
            if let ci = s.chars.firstIndex(where: { $0.cb === c }) {
                return (si, ci)
            }
        }
        return nil
    }
}
