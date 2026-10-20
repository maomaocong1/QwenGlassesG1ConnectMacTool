import Foundation
import IOBluetooth
import IOBluetoothShim

struct ClassicDevice: Identifiable, Equatable {
    let id: String // MAC 地址
    var name: String
    var address: String
    var paired: Bool
    var connected: Bool

    var isGlassesCandidate: Bool {
        let n = name.lowercased()
        return n.contains("qwen") || n.contains("g1") || n.contains("quark") || n.contains("glass")
    }
}

enum PairingPhase: Equatable {
    case idle
    case pairing
    case success(String)
    case failure(String)
}

struct PairEventItem: Identifiable {
    let id = UUID()
    let time: Date
    let event: String
    let detail: String
}

final class ClassicPairingModel: NSObject, ObservableObject {
    @Published var pairedDevices: [ClassicDevice] = []
    @Published var discovered: [ClassicDevice] = []
    @Published var inquiryRunning = false
    @Published var manualAddress = ""
    @Published var phase: PairingPhase = .idle
    @Published var statusMessage = "就绪"

    // 配对交互选项
    @Published var pinCode = "0000"
    @Published var autoPIN = true
    @Published var autoConfirm = true

    // 配对过程实时状态
    @Published var pairEvents: [PairEventItem] = []
    @Published var awaitingPIN = false
    @Published var awaitingConfirm = false
    @Published var confirmValue = ""
    @Published var pairingAddress = ""

    private var inquiry: IOBluetoothDeviceInquiry?
    private var watcher: Any?
    private let log = LogStore.shared

    override init() {
        super.init()
        refreshPaired()
        // 监听系统级连接/断开事件（所有设备），刷新状态
        watcher = QGWatchDevice(nil) { [weak self] address, event in
            guard let self else { return }
            self.log.log(.sys, tag: "CLASSIC", "系统事件: \(address) \(event)")
            self.refreshPaired()
            if case .pairing = self.phase, event == "connected" {
                // 连接成功通常意味着配对完成，completion 回调也会到达，这里仅提示
                self.statusMessage = "\(address) 已连接"
            }
        }
    }

    deinit {
        if let watcher { QGUnwatchDevice(watcher) }
        if let inquiry { inquiry.stop() }
    }

    var glassesPaired: ClassicDevice? {
        pairedDevices.first(where: \.isGlassesCandidate)
    }

    func refreshPaired() {
        var list: [ClassicDevice] = []
        for addr in QGPairedAddresses() {
            list.append(ClassicDevice(
                id: addr,
                name: QGDeviceName(addr) ?? "(无名称)",
                address: addr,
                paired: true,
                connected: QGIsConnected(addr)
            ))
        }
        DispatchQueue.main.async {
            self.pairedDevices = list.sorted { $0.name < $1.name }
        }
    }

    // MARK: - Inquiry（Classic 搜索）

    func startInquiry() {
        guard !inquiryRunning else { return }
        discovered.removeAll()
        let q = IOBluetoothDeviceInquiry()
        q.delegate = self
        q.inquiryLength = 20 // 秒
        q.updateNewDeviceNames = true
        inquiry = q
        let ret = q.start()
        if ret == kIOReturnSuccess {
            inquiryRunning = true
            statusMessage = "正在搜索附近 Classic 蓝牙设备（20 秒）…请确保眼镜处于配对模式"
            log.log(.sys, tag: "CLASSIC", "开始 Classic 设备搜索")
        } else {
            statusMessage = "Classic 搜索启动失败 (IOReturn=0x\(String(format: "%08x", ret)))"
            log.log(.sys, tag: "CLASSIC", statusMessage)
        }
    }

    func stopInquiry() {
        inquiry?.stop()
        inquiry = nil
        inquiryRunning = false
        statusMessage = "已停止搜索"
    }

    // MARK: - 配对

    func pair(address: String, name: String) {
        let addr = address.trimmingCharacters(in: .whitespaces).uppercased()
        guard !addr.isEmpty else {
            statusMessage = "请输入有效的蓝牙 MAC 地址"
            return
        }
        guard phase != .pairing else {
            statusMessage = "已有配对进行中"
            return
        }
        phase = .pairing
        pairingAddress = addr
        pairEvents.removeAll()
        awaitingPIN = false
        awaitingConfirm = false
        confirmValue = ""
        statusMessage = "正在与 \(name.isEmpty ? addr : name) (\(addr)) 配对…"
        log.log(.sys, tag: "PAIR", "发起配对: \(addr) autoPIN=\(autoPIN ? pinCode : "手动") autoConfirm=\(autoConfirm)")

        let autoPINValue: String? = (autoPIN && !pinCode.isEmpty) ? pinCode : nil
        let eventHandler: QGPairEvent = { [weak self] event, detail in
            guard let self else { return }
            let d = detail ?? ""
            self.pairEvents.append(PairEventItem(time: Date(), event: event, detail: d))
            self.log.log(.rx, tag: "PAIR", "[\(event)] \(d)")
            switch event {
            case "pin_request":
                self.awaitingPIN = (autoPINValue == nil)
            case "confirm_request":
                if !self.autoConfirm {
                    self.awaitingConfirm = true
                    self.confirmValue = d.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? d
                }
            default:
                break
            }
        }
        let completionHandler: QGPairCompletion = { [weak self] a, success, message in
            guard let self else { return }
            let msg = message ?? ""
            self.awaitingPIN = false
            self.awaitingConfirm = false
            if success {
                self.phase = .success("\(a) 配对成功 \(msg)")
                self.statusMessage = "配对成功：\(a)。现在可在 系统设置 > 声音 中将眼镜设为音频输出。"
                self.log.log(.sys, tag: "PAIR", "配对成功: \(a)")
            } else {
                self.phase = .failure(msg)
                self.statusMessage = "配对失败：\(msg)"
                self.log.log(.sys, tag: "PAIR", "配对失败: \(a) — \(msg)")
            }
            self.refreshPaired()
        }
        QGStartPairing(addr, autoPINValue, autoConfirm, 90, eventHandler, completionHandler)
    }

    func replyPIN(_ pin: String) {
        guard !pin.isEmpty else { return }
        log.log(.tx, tag: "PAIR", "手动回复 PIN「\(pin)」")
        QGPairReplyPIN(pin)
        awaitingPIN = false
    }

    func replyConfirmation(_ accept: Bool) {
        log.log(.tx, tag: "PAIR", "手动\(accept ? "接受" : "拒绝")数字比较 \(confirmValue)")
        QGPairReplyConfirmation(accept)
        awaitingConfirm = false
    }

    func cancelPairing(address: String) {
        QGCancelPairing(address.uppercased())
        phase = .idle
        statusMessage = "已取消配对"
    }

    func openSystemSettings() {
        log.log(.sys, tag: "PAIR", "打开系统蓝牙设置")
        QGOpenBluetoothSettings()
    }

    func unpair(_ device: ClassicDevice) {
        // IOBluetoothDevice 无公开移除 API，引导用户到系统设置
        statusMessage = "移除设备请在系统蓝牙设置中操作"
        openSystemSettings()
    }
}

extension ClassicPairingModel: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device else { return }
        let addr = device.addressString ?? "?"
        let name = device.name ?? "(未知名称)"
        let dev = ClassicDevice(
            id: addr,
            name: name,
            address: addr,
            paired: device.isPaired(),
            connected: device.isConnected()
        )
        log.log(.rx, tag: "CLASSIC", "发现 Classic 设备: \(name) [\(addr)] paired=\(dev.paired) classOfDevice=\(String(format: "0x%06X", device.classOfDevice))")
        DispatchQueue.main.async {
            if let idx = self.discovered.firstIndex(where: { $0.address == addr }) {
                self.discovered[idx] = dev
            } else {
                self.discovered.append(dev)
            }
        }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        DispatchQueue.main.async {
            self.inquiryRunning = false
            if aborted {
                self.statusMessage = "搜索已中止"
            } else if error == kIOReturnSuccess {
                self.statusMessage = "搜索完成，共发现 \(self.discovered.count) 个设备"
            } else {
                self.statusMessage = "搜索结束 (IOReturn=0x\(String(format: "%08x", error)))，发现 \(self.discovered.count) 个设备"
            }
            self.log.log(.sys, tag: "CLASSIC", self.statusMessage)
        }
    }
}
