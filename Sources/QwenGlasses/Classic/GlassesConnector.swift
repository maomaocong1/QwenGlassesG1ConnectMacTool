import Foundation
import IOBluetoothShim

/// 眼镜连接控制器：只保留验证可靠的能力——
/// 强制 Classic (BR/EDR) 连接 + Just Works 配对 + 音频服务校验。
final class GlassesConnector: NSObject, ObservableObject {
    @Published var address: String
    @Published var name = ""
    @Published var paired = false
    @Published var connected = false
    @Published var hasAudio = false
    @Published var busy = false
    @Published var message = "就绪"

    @Published var manualAddress = ""

    private var watcher: Any?
    private var pollTimer: Timer?
    private let log = LogStore.shared

    override init() {
        let saved = UserDefaults.standard.string(forKey: "glassesAddress") ?? ""
        address = saved
        super.init()
        refresh()
        watcher = QGWatchDevice(nil) { [weak self] addr, event in
            guard let self else { return }
            self.log.log(.sys, tag: "SYS", "系统事件: \(addr) \(event)")
            self.refresh()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let watcher { QGUnwatchDevice(watcher) }
    }

    var hasKnownAddress: Bool { !address.isEmpty }

    var statusTitle: String {
        if busy { return "连接中…" }
        if !hasKnownAddress { return "未设置眼镜地址" }
        if connected && hasAudio { return "已连接（音频可用）" }
        if connected { return "已连接（无音频服务）" }
        if paired { return "已配对（未连接）" }
        return "未配对"
    }

    func refresh() {
        guard hasKnownAddress else { return }
        let p = QGIsPaired(address)
        let c = QGIsConnected(address)
        let a = c ? QGHasAudioService(address) : false
        let n = QGDeviceName(address) ?? ""
        DispatchQueue.main.async {
            self.paired = p
            self.connected = c
            self.hasAudio = a
            if !n.isEmpty { self.name = n }
        }
    }

    /// 连接/重新配对（唯一入口）。forget 之后也用它。
    func connect(to addr: String? = nil) {
        let raw = addr ?? (manualAddress.isEmpty ? address : manualAddress)
        let target = raw.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else {
            message = "请先输入眼镜的蓝牙 MAC 地址"
            return
        }
        guard !busy else { return }
        address = target
        UserDefaults.standard.set(target, forKey: "glassesAddress")
        busy = true
        message = "正在连接…（约 5-15 秒）"
        log.log(.sys, tag: "CONN", "发起强制 Classic 连接: \(target)")

        // 陈旧链路（forget 后设备带旧绑定回连：connected 但未 paired）先断开
        if !QGIsPaired(target) && QGIsConnected(target) {
            log.log(.sys, tag: "CONN", "检测到陈旧连接，先断开")
            QGDisconnectDevice(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.openClassic(target)
            }
        } else {
            openClassic(target)
        }
    }

    private func openClassic(_ target: String) {
        QGOpenClassicConnection(target, true, 20) { [weak self] _, success, msg in
            guard let self else { return }
            self.busy = false
            self.message = msg ?? ""
            self.log.log(success ? .sys : .rx, tag: "CONN", success ? "连接成功: \(msg ?? "")" : "连接失败: \(msg ?? "")")
            self.refresh()
            if success {
                self.manualAddress = ""
            }
        }
    }

    func disconnect() {
        guard hasKnownAddress else { return }
        log.log(.sys, tag: "CONN", "断开连接: \(address)")
        QGDisconnectDevice(address)
        message = "已断开"
        refresh()
    }
}
