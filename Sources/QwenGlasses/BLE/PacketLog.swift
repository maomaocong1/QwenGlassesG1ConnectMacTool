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
        mirrorToFile(entry)
    }

    private static let fileLogURL = URL(fileURLWithPath: "/tmp/qwenglasses_app.log")
    private static let fileTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func mirrorToFile(_ entry: LogEntry) {
        let line = "[\(Self.fileTimeFormatter.string(from: entry.time))][\(entry.tag)][\(entry.direction.rawValue)] \(entry.text)\n"
        if let data = line.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: Self.fileLogURL) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: Self.fileLogURL)
            }
        }
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

/// 从 Qwen Glasses 广播 Manufacturer Data 中提取 Classic MAC。
/// 已实测的阿里布局（Company ID 0x01A8，小端 A8 01）：
///   A8 01 | 57 6F 57 ("WoW") | 14 D9 21 | 00 00 | 87 55 40 DC D7 C4 (MAC 小端) | 0A 03
/// 非此布局一律返回 nil——避免把随机设备的厂商数据尾字节误当 MAC（曾导致配错地址）。
func extractPossibleMAC(from data: Data) -> String? {
    let bytes = [UInt8](data)
    guard bytes.count >= 16, bytes[0] == 0xA8, bytes[1] == 0x01 else { return nil }
    return bytes[10...15].reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
}
