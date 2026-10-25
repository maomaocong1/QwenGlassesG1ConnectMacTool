#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 连接结果回调（主线程调用）。success 表示已连接且 A2DP/HFP 音频服务已注册。
typedef void (^QGClassicConnectCompletion)(NSString *address, BOOL success, NSString *_Nullable message);

/// 设备事件回调：event 为 connected / disconnected
typedef void (^QGConnectionEvent)(NSString *address, NSString *event);

/// 唯一验证可靠的连接方式：强制 BR/EDR page + authenticationRequired（Just Works 免配对码），
/// 连接后轮询确认 A2DP/HFP 音频服务注册（系统自动完成 SDP）。
/// waitTimeout: 连接/音频服务轮询上限秒数。
void QGOpenClassicConnection(NSString *address, BOOL authRequired, NSTimeInterval waitTimeout, QGClassicConnectCompletion _Nullable completion);

BOOL QGIsPaired(NSString *address);
BOOL QGIsConnected(NSString *address);

/// SDP 记录中是否含音频服务（A2DP AudioSink 0x110B 或 HFP 0x111E）。
BOOL QGHasAudioService(NSString *address);

NSString *_Nullable QGDeviceName(NSString *address);

/// 已配对设备地址列表。
NSArray<NSString *> *QGPairedAddresses(void);

/// 断开基带连接（返回 0 成功）。
int32_t QGDisconnectDevice(NSString *address);

/// 监听系统级连接/断开事件（address 传 nil 监听所有）。返回 token 供 QGUnwatchDevice 使用。
id _Nullable QGWatchDevice(NSString *_Nullable address, QGConnectionEvent onEvent);
void QGUnwatchDevice(id _Nullable token);

/// 打开系统设置 > 蓝牙。
void QGOpenBluetoothSettings(void);

/// 打开系统设置 > 声音（选择音频输出）。
void QGOpenSoundSettings(void);

NS_ASSUME_NONNULL_END
