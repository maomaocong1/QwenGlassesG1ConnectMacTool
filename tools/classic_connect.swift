// 强制 Classic (BR/EDR) 连接 + 认证配对 + SDP 服务发现
// 用法: swift tools/classic_connect.swift [MAC地址]
// 眼镜需处于配对模式（与 Android 系统配对时相同的状态）
import Foundation
import IOBluetooth

let addr = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "C4:D7:DC:40:55:87").uppercased()
let maxAttempts = 35 // 每次间隔 8 秒，约 5 分钟

class SDPWaiter: NSObject {
    var done = false
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        print("[sdp] 完成 status=0x\(String(format: "%08x", status))")
        if let recs = device?.services as? [IOBluetoothSDPServiceRecord] {
            print("[sdp] 服务记录 \(recs.count) 条:")
            for r in recs {
                print("   - \(r.getServiceName() ?? "(无名)")")
            }
        } else {
            print("[sdp] 无服务记录")
        }
        done = true
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

func hex(_ r: IOReturn) -> String { String(format: "0x%08x", r) }

func tryConnect(_ d: IOBluetoothDevice) -> Bool {
    let t = DateFormatter()
    t.dateFormat = "HH:mm:ss"
    print("[\(t.string(from: Date()))] 尝试 BR/EDR page + 认证配对…")
    let r = d.openConnection(nil, withPageTimeout: 0x4000, authenticationRequired: true)
    print("   openConnection -> \(hex(r))  paired=\(d.isPaired()) connected=\(d.isConnected())")
    guard r == kIOReturnSuccess else { return false }

    let w = SDPWaiter()
    let sr = d.performSDPQuery(w)
    print("   performSDPQuery -> \(hex(sr))")
    if sr == kIOReturnSuccess {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            if !w.done { print("[sdp] 超时"); CFRunLoopStop(CFRunLoopGetMain()) }
        }
        CFRunLoopRun()
    }
    return true
}

guard let device = IOBluetoothDevice(addressString: addr) else {
    print("地址无效: \(addr)")
    exit(2)
}

print("== 强制 Classic 连接: \(addr)")
print("== 请让眼镜进入配对模式（与 Android 配对时相同操作），手机蓝牙保持关闭")
print("== 循环重试约 5 分钟…")

for attempt in 1...maxAttempts {
    if tryConnect(device) {
        print("== 成功：Classic 已连接，SDP 完成 (第 \(attempt) 次尝试)")
        print("== 现在检查: 系统设置 > 声音 / 蓝牙，眼镜应出现为音频设备")
        exit(0)
    }
    Thread.sleep(forTimeInterval: 8)
}
print("== 失败：约 5 分钟内 Classic 侧始终不可达")
print("== 确认: 1) 眼镜确实在配对模式（指示灯快闪）2) 手机蓝牙已关 3) 距离足够近")
exit(1)
