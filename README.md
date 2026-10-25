# Qwen Glasses G1 — macOS 连接工具

原生 SwiftUI macOS App（SwiftPM 构建，**无需完整 Xcode**，Command Line Tools 即可）。
只保留实测可靠的连接能力：**强制 Classic (BR/EDR) 连接 + Just Works 配对**，让眼镜成为 macOS 音频设备；外加 BLE 扫描/GATT 调试台。

## 功能

| Tab | 功能 |
|-----|------|
| 连接眼镜 | 状态面板（配对/连接/A2DP-HFP 注册实时刷新）；「连接 / 重新配对」一键完成强制 Classic 连接（forget 后也用它）；断开；跳转系统声音/蓝牙设置；手动指定 MAC 地址 |
| BLE 调试 | CoreBluetooth 扫描（按 qwen/g1/quark/glass 过滤、RSSI 排序、广播 Manufacturer Data dump + 内嵌 MAC 提取）；连接后 GATT 控制台：服务/特征浏览、读 / 写(hex) / 订阅通知 |
| 报文日志 | 全量 ADV/GATT/CONN 日志（hex + ascii），可过滤、复制、清空；同时落盘 /tmp/qwenglasses_app.log |

命令行独立验证工具：`swift tools/classic_connect.swift [MAC]`

## 构建与运行

```bash
./scripts/bundle.sh     # swift build → 组装 build/QwenGlasses.app → ad-hoc 签名
open build/QwenGlasses.app
```

首次运行 macOS 会弹蓝牙授权，点「好」。若误点拒绝：系统设置 → 隐私与安全性 → 蓝牙 → 勾选 QwenGlasses。

> ad-hoc 签名每次重新构建 cdhash 变化，系统可能重新请求蓝牙权限，属正常现象。

## 使用流程

1. 打开 App → 「连接眼镜」Tab → 点「连接 / 重新配对」（地址自动记忆；首次可手动输入或在 BLE 调试 Tab 从广播内嵌 MAC 获取）
2. 约 5-15 秒后状态变绿「已连接（音频可用）」，眼镜出现在 系统设置 → 声音 的输出/输入列表
3. **forget 设备后也用「连接 / 重新配对」恢复**——不要在系统蓝牙设置里直接配对（对这种双模设备会走 LE 通道，产生无音频的"假配对"或弹配对码卡住）
4. 若系统弹配对请求（显示数字码）：直接点「配对/确认」即可，眼镜无屏幕不显示码；要求输 PIN 填 0000

## 已验证的关键结论（Qwen Glasses G1）

- 眼镜是**双模设备**：BLE 走阿里私有 `FEB3` 服务（"WoW" 协议，特征 FED4-FED8，官方 App 数据通道）；音频走 **Classic A2DP/HFP**
- 广播 Manufacturer Data：公司 ID `0x01A8`（Alibaba），内含字符串 "WoW" 与 Classic MAC（小端序，字节 10-15，与设备名后缀一致）
- **坑 1**：普通配对（IOBluetoothDevicePair / 系统设置弹窗）对已有 LE bond 的双模设备会走 LE 通道，产生只绑 BLE 的假配对（`Services: <BLE>`），音频列表不出现
- **解法**：`openConnection + authenticationRequired:YES` 强制 BR/EDR page，触发 Just Works 配对（免配对码，与 Android 系统配对行为一致）；连接后 bluetoothd 自动 SDP 注册 A2DP/HFP
- **坑 2**：forget 后眼镜带旧绑定自动回连（isConnected=true 但 isPaired=false 的"陈旧连接"），需先 closeConnection 再连（工具已自动处理）
- **坑 3**：连接后眼镜会"回连-断开-回连"抖动 1-2 秒，连接判定必须轮询采样，单次采样会误判
- **坑 4**：眼镜 SDP 记录的 ServiceClassIDList 是**单个 UUID 元素**而非数组，解析音频服务时两种形式都要处理
- BLE 连接后读取需加密链路的特征会触发 macOS LE 配对弹窗，故 GATT 控制台不自动读取，手动触发

## 项目结构

```
Package.swift                  # SwiftPM：app target + ObjC shim target
Sources/IOBluetoothShim/       # ObjC：强制 Classic 连接、音频服务检测、状态查询、事件监听
Sources/QwenGlasses/
  AppMain.swift                # @main 入口
  Classic/GlassesConnector.swift  # 连接控制器（唯一连接入口）
  BLE/BLEScanner.swift         # 扫描 + BLE 连接生命周期
  BLE/BLEConnection.swift      # GATT 发现/读/写/通知
  BLE/PacketLog.swift          # LogStore（含文件落盘）+ hex 工具 + 内嵌 MAC 提取
  Views/                       # ConnectView / ScanView / DeviceDetailView / LogView
Resources/Info.plist           # NSBluetoothAlwaysUsageDescription
Resources/entitlements.plist   # com.apple.security.device.bluetooth（未开沙盒）
scripts/bundle.sh              # 一键打包
tools/classic_connect.swift    # CLI：强制 Classic 连接验证工具
```

## 已知限制

- 强制 Classic 连接要求眼镜 Classic 侧可被 page（正常开机即可；个别状态需重进配对模式）
- BLE 私有 FEB3 "WoW" 协议无文档：特征均为 1 字节标志位，设备对盲写只回 `0x00`（未认证）；官方 App 级功能（拍照/AI 等）需逆向握手（Android HCI snoop log + tshark 可分析）
