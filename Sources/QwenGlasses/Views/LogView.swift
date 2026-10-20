import SwiftUI

struct LogView: View {
    @ObservedObject var log: LogStore
    @State private var filter = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                TextField("过滤（如 GATT / ADV / hex 值）", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("复制全部") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.exportText(), forType: .string)
                }
                Button("清空", role: .destructive) { log.clear() }
            }
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timeString(entry.time))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        Text(entry.tag.padding(toLength: 6, withPad: " ", startingAt: 0))
                            .font(.caption2.monospaced())
                            .foregroundStyle(tagColor(entry.tag))
                        Text(entry.direction.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(dirColor(entry.direction))
                        Text(entry.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .id(entry.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                }
                .listStyle(.plain)
                .onChange(of: log.entries.last?.id) { _, newID in
                    if let newID { proxy.scrollTo(newID, anchor: .bottom) }
                }
            }
        }
    }

    private var filteredEntries: [LogEntry] {
        guard !filter.isEmpty else { return log.entries }
        return log.entries.filter {
            $0.text.localizedCaseInsensitiveContains(filter) ||
            $0.tag.localizedCaseInsensitiveContains(filter)
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "GATT": return .blue
        case "ADV": return .purple
        case "SCAN": return .teal
        case "CONN": return .orange
        case "PAIR": return .pink
        case "CLASSIC": return .indigo
        default: return .secondary
        }
    }

    private func dirColor(_ d: LogDirection) -> Color {
        switch d {
        case .rx: return .green
        case .tx: return .blue
        case .sys: return .secondary
        }
    }
}
