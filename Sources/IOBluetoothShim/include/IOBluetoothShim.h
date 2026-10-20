#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 配对结果回调（主线程调用）。success 表示最终是否已配对/已连接。
typedef void (^QGPairCompletion)(NSString *address, BOOL success, NSString *_Nullable message);

/// 配对过程事件回调（主线程调用）。
/// event 取值: started / connecting / connected / pin_request / confirm_request /
///            passkey_notify / finished / simple_pairing / timeout / cancelled
/// detail 为事件说明（confirm_request 时 detail 为数字值字符串）。
typedef void (^QGPairEvent)(NSString *event, NSString *_Nullable detail);

/// 设备事件回调：event 为 connected / disconnected
typedef void (^QGConnectionEvent)(NSString *address, NSString *event);

/// 发起配对。
/// autoPIN: 设备请求 PIN 时自动回复的 PIN（传 nil 则不自动回复，等待 QGPairReplyPIN 手动回复）。
/// autoConfirm: 数字比较请求是否自动接受（NO 则等待 QGPairReplyConfirmation）。
/// 返回 0 表示配对流程已启动；负值表示无法启动（详见 completion 的 message）。
int32_t QGStartPairing(NSString *address,
                       NSString *_Nullable autoPIN,
                       BOOL autoConfirm,
                       NSTimeInterval timeoutSeconds,
                       QGPairEvent _Nullable onEvent,
                       QGPairCompletion _Nullable completion);

/// 取消进行中的配对尝试。
void QGCancelPairing(NSString *address);

/// 手动回复 PIN（当 autoPIN 为 nil 且收到 pin_request 事件后调用）。
void QGPairReplyPIN(NSString *pin);

/// 手动回复数字比较确认（当 autoConfirm 为 NO 且收到 confirm_request 事件后调用）。
void QGPairReplyConfirmation(BOOL accept);

BOOL QGIsPaired(NSString *address);
BOOL QGIsConnected(NSString *address);
NSString *_Nullable QGDeviceName(NSString *address);

/// 断开与设备的基带连接（用于 forget 之后设备用旧绑定自动回连的陈旧连接）。
/// 返回 0 表示成功。
int32_t QGDisconnectDevice(NSString *address);

/// 对已连接设备主动发起认证（无链路键时会触发系统配对流程）。
/// 返回 0 表示成功。
int32_t QGRequestAuthentication(NSString *address);

/// 强制 Classic (BR/EDR) 连接 + 认证配对回调（主线程）。
typedef void (^QGClassicConnectCompletion)(NSString *address, BOOL success, NSString *_Nullable message);

/// 强制走 Classic 通道：BR/EDR page（约10秒超时）+ authenticationRequired（触发 Just Works 配对），
/// 成功后执行 SDP 服务发现（注册 A2DP/HFP，使设备出现在音频列表）。
/// 这是让双模设备（BLE+Classic）在 macOS 上成为音频设备的可靠方式。
void QGOpenClassicConnection(NSString *address, BOOL authRequired, NSTimeInterval sdpTimeout, QGClassicConnectCompletion _Nullable completion);

/// 已配对设备的地址列表。
NSArray<NSString *> *QGPairedAddresses(void);

/// 监听系统级蓝牙设备事件（address 传 nil 表示监听所有设备）。
/// 返回 token，传给 QGUnwatchDevice 停止监听。
id _Nullable QGWatchDevice(NSString *_Nullable address, QGConnectionEvent onEvent);
void QGUnwatchDevice(id _Nullable token);

/// 打开 系统设置 > 蓝牙。
void QGOpenBluetoothSettings(void);

NS_ASSUME_NONNULL_END
