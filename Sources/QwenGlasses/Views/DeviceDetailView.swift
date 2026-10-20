import CoreBluetooth
import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var scanner: BLEScanner
    @ObservedObject var connection: BLEConnection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if connection.services.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(connection.isConnected ? "正在发现服务与特征…" : connection.stateText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($connection.services) { $service in
                        ServiceSection(service: $service, connection: connection)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(connection.name).font(.headline)
                    statusBadge
                }
                Text("MTU 写上限: \(connection.mtu) 字节 · \(connection.services.count) 个服务 · ⚠️ 读取加密特征会触发系统配对弹窗")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("全部重读") { connection.readAll() }
                .disabled(!connection.isConnected)
            Button("全部订阅通知") { connection.subscribeAllNotifications() }
                .disabled(!connection.isConnected)
            Button("断开") { scanner.disconnect() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .padding(10)
    }

    private var statusBadge: some View {
        Text(connection.stateText)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(connection.isConnected ? .green.opacity(0.2) : .secondary.opacity(0.2), in: Capsule())
    }
}

struct ServiceSection: View {
    @Binding var service: GattServiceItem
    let connection: BLEConnection

    var body: some View {
        DisclosureGroup {
            ForEach($service.chars) { $char in
                CharacteristicRow(char: $char, connection: connection)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.blue)
                Text(service.uuid).font(.callout.monospaced().weight(.medium))
                Text("\(service.chars.count) 个特征")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CharacteristicRow: View {
    @Binding var char: GattCharItem
    let connection: BLEConnection

    @State private var writeText = ""
    @State private var withResponse = true
    @State private var showWrite = false

    private var canWrite: Bool {
        char.cb.properties.contains(.write) || char.cb.properties.contains(.writeWithoutResponse)
    }
    private var canNotify: Bool {
        char.cb.properties.contains(.notify) || char.cb.properties.contains(.indicate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(char.uuid)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text(char.propsString)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15), in: Capsule())
                Spacer()
                if char.cb.properties.contains(.read) {
                    Button {
                        connection.read(char.cb)
                    } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("读取")
                }
                if canNotify {
                    Button {
                        connection.toggleNotify(char.cb)
                    } label: {
                        Image(systemName: char.notifying ? "bell.fill" : "bell")
                            .foregroundStyle(char.notifying ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(char.notifying ? "取消订阅通知" : "订阅通知")
                }
                if canWrite {
                    Button {
                        showWrite.toggle()
                    } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.borderless)
                        .help("写入")
                }
            }

            if let hex = char.valueHex {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hex)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                    Text("ascii: \(Data.from(hexString: hex)?.asciiPreview ?? "")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            } else if let err = char.notifyError {
                Text("读取失败: \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showWrite && canWrite {
                HStack(spacing: 6) {
                    TextField("hex，如 01 A0 FF", text: $writeText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    Toggle("响应", isOn: $withResponse)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Button("发送") {
                        connection.writeHex(writeText, to: char.cb, withResponse: withResponse)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
