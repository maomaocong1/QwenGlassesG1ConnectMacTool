import IOBluetoothShim
import SwiftUI

struct ConnectView: View {
    @ObservedObject var connector: GlassesConnector

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                actionsCard
                manualCard
                helpCard
            }
            .padding(16)
        }
    }

    // MARK: 状态

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundStyle(statusColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(connector.statusTitle).font(.title3.bold())
                    if connector.connected && connector.hasAudio {
                        badge("A2DP/HFP", .green)
                    }
                }
                if connector.hasKnownAddress {
                    Text("\(connector.name.isEmpty ? "(未知名称)" : connector.name)  \(connector.address)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(connector.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if connector.busy { ProgressView() }
        }
        .padding(14)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
    }

    private var statusIcon: String {
        if connector.busy { return "arrow.triangle.2.circlepath" }
        if connector.connected && connector.hasAudio { return "checkmark.circle.fill" }
        if connector.connected { return "exclamationmark.circle.fill" }
        if connector.paired { return "circle.dotted" }
        return "circle.dashed"
    }

    private var statusColor: Color {
        if connector.busy { return .orange }
        if connector.connected && connector.hasAudio { return .green }
        if connector.connected { return .orange }
        return .secondary
    }

    // MARK: 操作

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    connector.connect()
                } label: {
                    Label(connector.hasKnownAddress ? "连接 / 重新配对" : "连接", systemImage: "bolt.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(connector.busy || !connector.hasKnownAddress && connector.manualAddress.isEmpty)

                Button("断开") { connector.disconnect() }
                    .disabled(connector.busy || !connector.connected)

                Button("刷新状态") { connector.refresh() }
                    .disabled(connector.busy)

                Spacer()

                Button("系统声音设置") { QGOpenSoundSettings() }
                Button("系统蓝牙设置") { QGOpenBluetoothSettings() }
            }
            Text("forget 设备后也用「连接 / 重新配对」恢复——不要在系统蓝牙设置里直接配对（会走 LE 通道产生无音频的假配对）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 手动地址

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动指定地址").font(.headline)
            HStack {
                TextField("MAC 地址，如 C4:D7:DC:40:55:87", text: $connector.manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                Button("连接该地址") {
                    connector.connect(to: connector.manualAddress)
                }
                .buttonStyle(.bordered)
                .disabled(connector.busy || connector.manualAddress.isEmpty)
            }
            Text("地址来源：眼镜 BLE 广播 Manufacturer Data 内嵌的 MAC（见「BLE 调试」Tab 扫描结果）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 说明

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("工作原理").font(.headline)
            Text("强制 BR/EDR page + authenticationRequired 触发 Just Works 配对（免配对码），连接后系统自动 SDP 注册 A2DP/HFP，眼镜即出现在 系统设置 > 声音 的输出/输入列表。")
                .font(.caption)
            Text("若系统弹出配对请求（显示数字码）：直接点「配对/确认」即可——眼镜无屏幕、不显示码；要求输 PIN 时填 0000。")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding(14)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
}
