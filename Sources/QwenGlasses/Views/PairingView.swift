import SwiftUI

struct PairingView: View {
    @ObservedObject var classic: ClassicPairingModel
    @ObservedObject var scanner: BLEScanner
    @State private var showManual = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                if classic.phase == .pairing {
                    pairingPanel
                }
                glassesQuickCard
                discoveredSection
                pairedSection
                manualSection
            }
            .padding(16)
        }
    }

    // MARK: 配对交互面板

    private var pairingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView().controlSize(.small)
                Text("配对进行中：\(classic.pairingAddress)").font(.headline)
                Spacer()
                Button("取消") { classic.cancelPairing(address: classic.pairingAddress) }
                    .tint(.red)
            }

            if classic.awaitingPIN {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundStyle(.orange)
                    Text("设备请求 PIN 码：").font(.callout)
                    TextField("输入 PIN", text: $classic.pinCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .font(.callout.monospaced())
                    Button("发送 PIN") { classic.replyPIN(classic.pinCode) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            if classic.awaitingConfirm {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.blue)
                    Text("设备显示数字「\(classic.confirmValue)」，是否匹配？").font(.callout)
                    Button("确认匹配") { classic.replyConfirmation(true) }
                        .buttonStyle(.borderedProminent)
                    Button("不匹配") { classic.replyConfirmation(false) }
                        .tint(.red)
                }
                .padding(8)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            if !classic.pairEvents.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("配对事件流").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(classic.pairEvents) { e in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(e.time, style: .time)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                    Text("[\(e.event)]")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.blue)
                                    Text(e.detail)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 状态卡片

    private var statusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline)
                Text(classic.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if case .pairing = classic.phase {
                Button("取消") {
                    classic.cancelPairing(address: currentPairingAddress)
                }
                .tint(.red)
            }
            Button("打开系统蓝牙设置") { classic.openSystemSettings() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var currentPairingAddress: String {
        classic.pairingAddress.isEmpty ? classic.manualAddress : classic.pairingAddress
    }

    private var statusIcon: String {
        switch classic.phase {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pairing: return "arrow.triangle.2.circlepath"
        case .idle:
            return classic.glassesPaired != nil ? "checkmark.circle" : "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch classic.phase {
        case .success: return .green
        case .failure: return .red
        case .pairing: return .orange
        case .idle: return classic.glassesPaired != nil ? .green : .secondary
        }
    }

    private var statusTitle: String {
        switch classic.phase {
        case .success: return "配对成功"
        case .failure: return "配对失败"
        case .pairing: return "配对进行中…"
        case .idle:
            if let g = classic.glassesPaired {
                return "已配对：\(g.name) \(g.connected ? "（已连接）" : "（未连接）")"
            }
            return "未配对眼镜设备"
        }
    }

    // MARK: 一键流程

    @ViewBuilder
    private var glassesQuickCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("一键流程").font(.headline)
            Text("1. 让眼镜进入配对模式 → 2. 点击搜索 Classic 设备 → 3. 在下方列表中点击「配对」。若自动配对失败，请用系统蓝牙设置手动配对（工具会自动检测配对成功）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("💡 若系统弹出配对请求（显示一串数字码）：直接点「配对/确认」即可——眼镜无屏幕、不会显示码，属正常现象；若要求输入 PIN，填 0000。")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("⚠️ 部分眼镜需先在 BLE 通道完成 App 握手后才开放 Classic 配对。若配对一直无响应（无 PIN/确认请求），请切到「BLE 扫描 / GATT」Tab 连接后点「全部订阅通知」，观察日志中设备主动推送的数据。")
                .font(.caption)
                .foregroundStyle(.orange)
            HStack {
                Button(classic.inquiryRunning ? "停止搜索" : "搜索 Classic 设备") {
                    classic.inquiryRunning ? classic.stopInquiry() : classic.startInquiry()
                }
                .buttonStyle(.borderedProminent)
                if classic.inquiryRunning { ProgressView().controlSize(.small) }
                if let bleMAC = scanner.devices.compactMap(\.possibleMAC).first {
                    Text("BLE 广播疑似 MAC: \(bleMAC)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("用它配对") {
                        classic.manualAddress = bleMAC
                        classic.pair(address: bleMAC, name: "Qwen Glasses G1")
                    }
                    .buttonStyle(.bordered)
                    .disabled(classic.phase == .pairing)
                }
            }
            if !classic.lastPairedAddress.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(classic.lastDeviceStale ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text("上次配对：\(classic.lastPairedName.isEmpty ? classic.lastPairedAddress : classic.lastPairedName)")
                                .font(.callout)
                            if classic.lastDeviceStale {
                                Text("陈旧连接")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.25), in: Capsule())
                            }
                        }
                        Text(classic.lastPairedAddress)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(classic.lastDeviceStale ? "断开并重新配对" : "重新配对") {
                        classic.pair(address: classic.lastPairedAddress, name: classic.lastPairedName)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(classic.lastDeviceStale ? .orange : .accentColor)
                    .disabled(classic.phase == .pairing)
                    Button {
                        classic.forgetLastDevice()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("清除记忆")
                }
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 搜索到的设备

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("附近 Classic 设备（\(classic.discovered.count)）").font(.headline)
            if classic.discovered.isEmpty {
                Text("尚无结果。眼镜需处于配对模式才可被 Classic 搜索发现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(classic.discovered) { device in
                    ClassicDeviceRow(device: device) {
                        classic.pair(address: device.address, name: device.name)
                    }
                    .disabled(classic.phase == .pairing)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 已配对设备

    private var pairedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已配对设备（\(classic.pairedDevices.count)）").font(.headline)
                Spacer()
                Button("刷新") { classic.refreshPaired() }
                    .buttonStyle(.borderless)
            }
            if classic.pairedDevices.isEmpty {
                Text("（无）").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(classic.pairedDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.isGlassesCandidate ? "eyeglasses" : "desktopcomputer")
                            .foregroundStyle(device.isGlassesCandidate ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name).font(.callout)
                            Text(device.address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(device.connected ? "已连接" : "未连接")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(device.connected ? .green : .secondary)
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 手动配对

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("配对选项").font(.headline)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Text("PIN:").font(.callout)
                    TextField("0000", text: $classic.pinCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .font(.callout.monospaced())
                }
                Toggle("自动回复 PIN", isOn: $classic.autoPIN)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("自动接受数字比较", isOn: $classic.autoConfirm)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text("关闭自动开关后，配对过程中设备请求 PIN / 数字比较时会在此页面弹出输入框，由你手动响应。常用 PIN：0000、1234。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("手动指定地址配对").font(.headline)
            HStack {
                TextField("MAC 地址，如 12:34:56:AB:CD:EF", text: $classic.manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                Button("检查状态") { classic.checkManualAddressState() }
                    .buttonStyle(.bordered)
                Button("配对") {
                    classic.pair(address: classic.manualAddress, name: "")
                }
                .buttonStyle(.borderedProminent)
                .disabled(classic.phase == .pairing)
            }
            if !classic.manualStateText.isEmpty {
                Text(classic.manualStateText)
                    .font(.caption)
                    .foregroundStyle(classic.manualStateText.contains("⚠️") ? .orange : .secondary)
                    .textSelection(.enabled)
            }
            Text("提示：眼镜的 Classic 地址通常与 BLE 广播厂商数据中的 MAC 相同或 ±1。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ClassicDeviceRow: View {
    let device: ClassicDevice
    let onPair: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.isGlassesCandidate ? "eyeglasses" : "wave.3.right")
                .foregroundStyle(device.isGlassesCandidate ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(device.name).font(.callout.weight(device.isGlassesCandidate ? .semibold : .regular))
                    if device.isGlassesCandidate {
                        Text("疑似眼镜")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                    if !device.paired && device.connected {
                        Text("陈旧连接")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.25), in: Capsule())
                            .help("设备未配对但仍连着（forget 后设备用旧绑定回连）。点「配对」会自动先断开再重新配对。")
                    }
                }
                Text(device.address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if device.paired {
                Text("已配对").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("配对", action: onPair)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        Divider()
    }
}
