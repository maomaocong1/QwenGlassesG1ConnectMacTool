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
    @Published var manualStateText = ""

    // 上次配对成功的设备（用于 forget 后快速重新配对）
    @Published var lastPairedAddress: String = UserDefaults.standard.string(forKey: "lastPairedAddress") ?? ""
    @Published var lastPairedName: String = UserDefaults.standard.string(forKey: "lastPairedName") ?? ""
    @Published var lastDeviceStale = false

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
        // 上次配对设备的陈旧连接检测（forget 后设备用旧绑定回连）
        var stale = false
        if !lastPairedAddress.isEmpty {
            stale = !QGIsPaired(lastPairedAddress) && QGIsConnected(lastPairedAddress)
        }
        DispatchQueue.main.async {
            self.pairedDevices = list.sorted { $0.name < $1.name }
            self.lastDeviceStale = stale
            // 上次设备已被 forget 且未回连时清掉记忆
            if !self.lastPairedAddress.isEmpty,
               !QGIsPaired(self.lastPairedAddress), !QGIsConnected(self.lastPairedAddress),
               !list.contains(where: { $0.address == self.lastPairedAddress }) {
                // 保留记忆（可能只是暂时不在范围内），仅当用户手动清除时删除
            }
        }
    }

    func rememberPairedDevice(address: String) {
        lastPairedAddress = address
        lastPairedName = QGDeviceName(address) ?? ""
        UserDefaults.standard.set(lastPairedAddress, forKey: "lastPairedAddress")
        UserDefaults.standard.set(lastPairedName, forKey: "lastPairedName")
    }

    func forgetLastDevice() {
        lastPairedAddress = ""
        lastPairedName = ""
        lastDeviceStale = false
        UserDefaults.standard.removeObject(forKey: "lastPairedAddress")
        UserDefaults.standard.removeObject(forKey: "lastPairedName")
    }

    func checkManualAddressState() {
        let addr = manualAddress.trimmingCharacters(in: .whitespaces).uppercased()
        guard !addr.isEmpty else {
            manualStateText = "请先输入地址"
            return
        }
        let paired = QGIsPaired(addr)
        let connected = QGIsConnected(addr)
        let name = QGDeviceName(addr) ?? ""
        if paired && connected {
            manualStateText = "\(name) 已配对且已连接 ✓"
        } else if paired {
            manualStateText = "\(name) 已配对，未连接"
        } else if connected {
            manualStateText = "⚠️ \(name) 未配对但仍连接（陈旧链路）——点「配对」将自动断开后重新配对"
        } else {
            manualStateText = "\(name.isEmpty ? "设备" : name) 未配对、未连接（需进入配对模式）"
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

        // forget device 后，眼镜常带着旧绑定自动回连：isConnected=true 但 isPaired=false。
        // 这种陈旧链路会导致配对失败，先断开再配对。
        let stale = !QGIsPaired(addr) && QGIsConnected(addr)
        if stale {
            statusMessage = "检测到陈旧连接（设备用旧绑定回连），正在断开后重新配对…"
            log.log(.sys, tag: "PAIR", "\(addr) 未配对但已连接（陈旧链路），先断开")
            pairEvents.append(PairEventItem(time: Date(), event: "stale_link",
                                            detail: "检测到陈旧连接，正在断开…"))
            let ret = QGDisconnectDevice(addr)
            log.log(.sys, tag: "PAIR", "closeConnection 返回 0x\(String(format: "%08x", ret))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startPairing(addr: addr, name: name)
            }
        } else {
            statusMessage = "正在与 \(name.isEmpty ? addr : name) (\(addr)) 配对…"
            startPairing(addr: addr, name: name)
        }
    }

    private func startPairing(addr: String, name: String) {
        guard phase == .pairing else { return } // 已被取消

        // 策略 1（已验证）：强制 BR/EDR page + authenticationRequired 触发 Just Works 配对，
        // 成功后 SDP 注册 A2DP/HFP —— 双模设备（如 Qwen Glasses G1）成为音频设备的可靠方式。
        pairEvents.append(PairEventItem(time: Date(), event: "classic_page",
                                        detail: "尝试强制 Classic 连接 (BR/EDR + Just Works)…"))
        log.log(.sys, tag: "PAIR", "策略1: 强制 Classic 连接 \(addr)")
        statusMessage = "正在强制 Classic 连接（约需 10-20 秒）…"

        QGOpenClassicConnection(addr, true, 25) { [weak self] a, success, message in
            guard let self, self.phase == .pairing, self.pairingAddress == a else { return }
            let msg = message ?? ""
            self.pairEvents.append(PairEventItem(time: Date(),
                                                 event: success ? "classic_ok" : "classic_fail", detail: msg))
            self.log.log(success ? .sys : .rx, tag: "PAIR", "策略1\(success ? "成功" : "失败"): \(msg)")
            if success {
                self.awaitingPIN = false
                self.awaitingConfirm = false
                self.phase = .success("\(a) Classic 已连接")
                self.statusMessage = "配对成功：\(msg)。眼镜应已出现在 系统设置 > 声音 的输出/输入列表。"
                self.rememberPairedDevice(address: a)
                self.refreshPaired()
            } else {
                // 策略 2 回退：IOBluetoothDevicePair（可能走 LE 通道）
                self.pairEvents.append(PairEventItem(time: Date(), event: "fallback",
                                                     detail: "回退到 IOBluetoothDevicePair 配对…"))
                self.startLegacyPairing(addr: a)
            }
        }
    }

    private func startLegacyPairing(addr: String) {
        guard phase == .pairing else { return }
        statusMessage = "强制 Classic 失败，尝试常规配对…"
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
                self.rememberPairedDevice(address: a)
            } else {
                var hint = ""
                if msg.contains("0x00000005") || msg.lowercased().contains("auth") {
                    hint = "。认证失败通常是眼镜端还存着旧绑定：请让眼镜重新进入配对模式（长按电源键）后再试"
                } else if msg.contains("超时") {
                    hint = "。请确认眼镜处于配对模式；若眼镜仍显示已连接手机，请先在手机 App 中断开/解绑"
                }
                self.phase = .failure(msg)
                self.statusMessage = "配对失败：\(msg)\(hint)"
                self.log.log(.sys, tag: "PAIR", "配对失败: \(a) — \(msg)\(hint)")
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
