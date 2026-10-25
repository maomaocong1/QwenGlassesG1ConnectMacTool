import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BLEScanner()
    @StateObject private var connector = GlassesConnector()
    @ObservedObject private var log = LogStore.shared

    var body: some View {
        TabView {
            ConnectView(connector: connector)
                .tabItem { Label("连接眼镜", systemImage: "ear") }

            ScanView(scanner: scanner)
                .tabItem { Label("BLE 调试", systemImage: "antenna.radiowaves.left.and.right") }

            LogView(log: log)
                .tabItem { Label("报文日志", systemImage: "list.bullet.rectangle") }
        }
        .padding(.top, 8)
    }
}

// MARK: - BLE 扫描 + GATT 控制台

struct ScanView: View {
    @ObservedObject var scanner: BLEScanner
    @State private var selection: DiscoveredDevice.ID?

    var body: some View {
        HSplitView {
            deviceList
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            detailPane
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var deviceList: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if scanner.filteredDevices.isEmpty {
                emptyHint
            } else {
                List(scanner.filteredDevices, selection: $selection) { device in
                    DeviceRow(device: device)
                        .tag(device.id)
                        .contextMenu {
                            Button("连接") { scanner.connect(to: device); selection = device.id }
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack {
                Button(scanner.scanning ? "停止扫描" : "开始扫描") {
                    scanner.scanning ? scanner.stopScan() : scanner.startScan()
                }
                .buttonStyle(.borderedProminent)
                TextField("按名称过滤", text: $scanner.filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle("只看疑似眼镜", isOn: $scanner.onlyMatching)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            HStack {
                Circle()
                    .fill(scanner.centralState == .poweredOn ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(scanner.stateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(scanner.filteredDevices.count) 个设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let best = scanner.bestCandidate, scanner.connection == nil {
                Button {
                    scanner.connect(to: best)
                    selection = best.id
                } label: {
                    Label("一键连接 \(best.name)", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .padding(8)
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(scanner.scanning ? "正在扫描…\n请让眼镜进入配对模式（长按电源键）" : "点击「开始扫描」")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if scanner.onlyMatching && scanner.devices.count > scanner.filteredDevices.count {
                Button("发现 \(scanner.devices.count) 个设备但无匹配项，显示全部") {
                    scanner.onlyMatching = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var detailPane: some View {
        if let conn = scanner.connection {
            DeviceDetailView(scanner: scanner, connection: conn)
        } else if let id = selection, let device = scanner.devices.first(where: { $0.id == id }) {
            AdvertisementView(device: device) { scanner.connect(to: device) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("选择左侧设备查看广播详情，或连接后进入 GATT 控制台")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.body.weight(device.isGlassesCandidate ? .semibold : .regular))
                    if device.isGlassesCandidate {
                        Text("疑似眼镜")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text(device.id.uuidString.prefix(13) + "…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                if let mac = device.possibleMAC {
                    Text("厂商数据疑似 MAC: \(mac)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(device.rssi) dBm")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(rssiColor)
                Image(systemName: rssiIcon)
                    .foregroundStyle(rssiColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var rssiColor: Color {
        switch device.rssi {
        case (-55)...0: return .green
        case (-70)...(-56): return .yellow
        default: return .red
        }
    }

    private var rssiIcon: String {
        switch device.rssi {
        case (-55)...0: return "wifi"
        case (-70)...(-56): return "wifi"
        default: return "wifi.exclamationmark"
        }
    }
}

struct AdvertisementView: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name).font(.title2.bold())
                        Text("RSSI \(device.rssi) dBm · 最后出现 \(device.lastSeen, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("连接 (BLE)", action: onConnect)
                        .buttonStyle(.borderedProminent)
                }
                Group {
                    section("广播服务 UUID") {
                        if device.advertisedServices.isEmpty {
                            Text("（无）").foregroundStyle(.secondary)
                        } else {
                            ForEach(device.advertisedServices, id: \.self) { s in
                                Text(s).font(.callout.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    section("厂商数据 (Manufacturer Data)") {
                        if device.manufacturerHex.isEmpty {
                            Text("（无）").foregroundStyle(.secondary)
                        } else {
                            Text(device.manufacturerHex).font(.callout.monospaced()).textSelection(.enabled)
                            if let mac = device.possibleMAC {
                                Text("疑似 MAC: \(mac)").font(.caption).foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    section("原始广播内容") {
                        Text(device.rawAdvDescription)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
