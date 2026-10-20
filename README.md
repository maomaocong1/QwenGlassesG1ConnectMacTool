# Qwen Glasses G1 — macOS 搜索与配对工具

原生 SwiftUI macOS App（SwiftPM 构建，**无需完整 Xcode**，Command Line Tools 即可），用于搜索、连接并配对 Qwen Glasses G1。

## 功能

| Tab | 功能 |
|-----|------|
| BLE 扫描 / GATT | CoreBluetooth 实时扫描，按名称过滤（qwen/g1/quark/glass），RSSI 排序；连接后自动发现全部服务/特征并读取，GATT 控制台支持 读 / 写(hex) / 订阅通知 / 一键全部订阅，全部报文进日志（逆向用） |
| 音频配对 (Classic) | **强制 BR/EDR 连接**（`openConnection + authenticationRequired`，Just Works 免配对码）→ SDP 注册 A2DP/HFP → 设备出现在音频列表；失败回退 `IOBluetoothDevicePair`（支持手动 PIN/数字比较响应）；陈旧连接自动断开重配；实时监控配对/连接状态 |
| 报文日志 | 全量 ADV/GATT/CONN/PAIR 日志，hex + ascii，可过滤、复制、清空 |

## 已验证的关键结论（Qwen Glasses G1）

- 眼镜是**双模设备**：BLE 走阿里私有 `FEB3` 服务（"WoW" 协议，特征 FED4-FED8，App 数据通道）；音频走 **Classic A2DP/HFP**
- 广播 Manufacturer Data：公司 ID `0x01A8`（Alibaba），内含 MAC（小端序，与设备名后缀一致）
- **坑**：普通配对（IOBluetoothDevicePair / 系统弹窗）对已有 LE bond 的双模设备会走 LE 通道，产生"只绑 BLE"的假配对（`Services: <BLE>`），音频列表不出现
- **解法**：强制 BR/EDR page + `authenticationRequired:YES` 触发 Just Works 配对（无需配对码，与 Android 系统配对行为一致），连接后 SDP 自动注册 A2DP/HFP → 出现在 系统设置 > 声音
- forget device 后眼镜会带旧绑定自动回连（isConnected=true 但 isPaired=false 的"陈旧连接"），需先断开再配对（工具已自动处理）
- **系统弹出"配对码"弹窗时直接点「配对/确认」**：眼镜无屏幕不显示码；要求输 PIN 时填 0000
- BLE 连接后**不要盲目读取特征**：读需要加密链路的特征会触发 macOS 的 LE 配对弹窗，产生"只绑 BLE"的假配对（工具已改为手动触发读取）
- 命令行独立验证工具：`swift tools/classic_connect.swift [MAC]`

## 构建与运行

```bash
./scripts/bundle.sh     # swift build → 组装 build/QwenGlasses.app → ad-hoc 签名
open build/QwenGlasses.app
```

首次运行 macOS 会弹出蓝牙授权，点「好」。若误点拒绝：系统设置 → 隐私与安全性 → 蓝牙 → 勾选 QwenGlasses。

> 注意：ad-hoc 签名每次重新构建 cdhash 变化，系统可能重新请求蓝牙权限，属正常现象。

## 使用流程

1. **音频 (Classic)**：切到「音频配对」Tab → 直接点上次配对设备的「重新配对」，或「搜索 Classic 设备」后点「配对」
   - 工具优先走**强制 BR/EDR 连接**（已验证，约 10-20 秒，Just Works 无需配对码）
   - 若眼镜在系统设置里被 forget 过又自动回连，工具会先断开陈旧连接再配对
   - 成功后眼镜即出现在 系统设置 → 声音 的输出/输入列表
2. **BLE 数据通道**：「BLE 扫描」Tab → 找到 "Qwen Glasses G1" → 「一键连接」→ GATT 控制台浏览/读写 FEB3 服务特征
3. 命令行快速验证音频链路：`swift tools/classic_connect.swift C4:D7:DC:40:55:87`

## BLE ↔ Classic 地址关联

CoreBluetooth 隐藏真实 MAC（只给随机 UUID）。工具会：
- dump 广播中的 Manufacturer Data（hex），并启发式提取尾部 6 字节作为疑似 MAC 显示
- Classic 搜索直接按名称匹配，通常无需手动关联
- 也可在「手动指定地址配对」中输入地址（Classic 地址常与 BLE 地址相同或 ±1）

## 项目结构

```
Package.swift                  # SwiftPM：app target + ObjC shim target
Sources/IOBluetoothShim/       # ObjC：IOBluetoothDevicePair 配对、连接事件监听、状态查询
Sources/QwenGlasses/
  AppMain.swift                # @main 入口
  BLE/BLEScanner.swift         # 扫描 + 连接生命周期（CBCentralManager 唯一 delegate）
  BLE/BLEConnection.swift      # GATT 发现/读/写/通知（CBPeripheralDelegate）
  BLE/PacketLog.swift          # LogStore + hex 工具
  Classic/ClassicPairing.swift # Inquiry + 配对流程 + 已配对列表
  Views/                       # ScanView / DeviceDetailView / PairingView / LogView
Resources/Info.plist           # NSBluetoothAlwaysUsageDescription
Resources/entitlements.plist   # com.apple.security.device.bluetooth（未开沙盒）
scripts/bundle.sh              # 一键打包
tools/classic_connect.swift    # CLI：强制 Classic 连接验证工具
```

## 已知限制

- 强制 Classic 连接要求眼镜 Classic 侧可被 page（正常开机即可；若刚 forget 过，可能需重新进配对模式）
- BLE 私有 FEB3 "WoW" 协议无文档：FED4-FED8 均为 1 字节标志位，设备对盲写只回 `0x00`（未认证），完整 App 级功能（拍照/AI 等）需逆向官方 App 握手（可用 Android HCI snoop log + tshark 分析）
- GATT 控制台只提供原始读写能力；特征值含义需结合「报文日志」Tab 自行分析
