import Foundation
import SwiftUI

enum LogDirection: String {
    case rx = "← RX"
    case tx = "→ TX"
    case sys = "• SYS"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let tag: String
    let direction: LogDirection
    let text: String
}

final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ direction: LogDirection, tag: String, _ text: String) {
        let entry = LogEntry(time: Date(), tag: tag, direction: direction, text: text)
        if Thread.isMainThread {
            append(entry)
        } else {
            DispatchQueue.main.async { self.append(entry) }
        }
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > 3000 { entries.removeFirst(entries.count - 3000) }
    }

    func clear() { entries.removeAll() }

    func exportText() -> String {
        entries.map {
            "[\(Self.timeFormatter.string(from: $0.time))] [\($0.tag.padding(toLength: 6, withPad: " ", startingAt: 0))][\($0.direction.rawValue)] \($0.text)"
        }.joined(separator: "\n")
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var asciiPreview: String {
        map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }
            .joined()
    }

    static func from(hexString: String) -> Data? {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

/// 从广播 Manufacturer Data 中启发式提取疑似 MAC 地址的字符串（用于关联 Classic 地址）
func extractPossibleMAC(from data: Data) -> String? {
    guard data.count >= 6 else { return nil }
    let bytes = [UInt8](data)
    // 常见布局：尾部 6 字节为 MAC（可能正序或倒序）
    let tail = Array(bytes.suffix(6))
    let candidates = [tail, tail.reversed()]
    for c in candidates {
        // 排除全 0 / 全 FF 等退化值
        if Set(c).count <= 1 { continue }
        return c.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    return nil
}
