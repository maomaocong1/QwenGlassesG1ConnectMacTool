# Qwen Glasses G1 — macOS 搜索与配对工具

原生 SwiftUI macOS App（SwiftPM 构建，**无需完整 Xcode**，Command Line Tools 即可），用于搜索、连接并配对 Qwen Glasses G1。

## 功能

| Tab | 功能 |
|-----|------|
| BLE 扫描 / GATT | CoreBluetooth 实时扫描，按名称过滤（qwen/g1/quark/glass），RSSI 排序；连接后自动发现全部服务/特征并读取，GATT 控制台支持 读 / 写(hex) / 订阅通知，全部报文进日志（逆向用） |
| 音频配对 (Classic) | Classic 设备搜索（IOBluetoothDeviceInquiry）；程序化配对（`IOBluetoothDevicePair`，自动回 PIN `0000`、自动确认数字比较）；失败时一键跳转系统蓝牙设置；实时监控已配对/连接状态 |
| 报文日志 | 全量 ADV/GATT/CONN/PAIR 日志，hex + ascii，可过滤、复制、清空 |

## 构建与运行

```bash
./scripts/bundle.sh     # swift build → 组装 build/QwenGlasses.app → ad-hoc 签名
open build/QwenGlasses.app
```

首次运行 macOS 会弹出蓝牙授权，点「好」。若误点拒绝：系统设置 → 隐私与安全性 → 蓝牙 → 勾选 QwenGlasses。

> 注意：ad-hoc 签名每次重新构建 cdhash 变化，系统可能重新请求蓝牙权限，属正常现象。

## 使用流程

1. 让眼镜进入配对模式（通常是长按电源键，指示灯快闪）
2. **BLE**：打开 App 自动开始扫描，找到 "Qwen Glasses G1" → 「一键连接」→ 在 GATT 控制台浏览/读写特征值
3. **音频 (Classic)**：切到「音频配对」Tab → 「搜索 Classic 设备」→ 对眼镜点「配对」
   - 自动配对失败时点「打开系统蓝牙设置」手动配对，本工具会自动检测到配对成功并刷新状态
4. 配对成功后在 系统设置 → 声音 中即可将眼镜选为音频输出

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
```

## 已知限制

- Classic 程序化配对是尽力而为：部分 macOS 版本/设备组合下系统仍会弹自己的配对面板，此时按系统提示操作即可，工具会自动感知结果
- 眼镜若不在配对模式，Classic 搜索无法发现它（不可发现状态）
- 无协议文档，GATT 控制台只提供原始读写能力；特征值含义需结合「报文日志」Tab 自行分析
