#import "IOBluetoothShim.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>

#pragma mark - 日志

static void QGLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    static NSDateFormatter *df = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@][shim] %@\n", [df stringFromDate:[NSDate date]], msg];
    NSString *path = @"/tmp/qwenglasses_shim.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - 音频服务检测

BOOL QGHasAudioService(NSString *address) {
    IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
    if (!d) return NO;
    NSArray *records = d.services;
    if (![records isKindOfClass:[NSArray class]] || records.count == 0) return NO;
    IOBluetoothSDPUUID *audioSink = [[IOBluetoothSDPUUID alloc] initWithUUID16:kBluetoothSDPUUID16ServiceClassAudioSink]; // 0x110B A2DP
    IOBluetoothSDPUUID *handsfree = [[IOBluetoothSDPUUID alloc] initWithUUID16:kBluetoothSDPUUID16ServiceClassHandsFree];  // 0x111E HFP

    BOOL (^matchUUID)(IOBluetoothSDPUUID *) = ^BOOL(IOBluetoothSDPUUID *u) {
        return u && ([u isEqualToUUID:audioSink] || [u isEqualToUUID:handsfree]);
    };

    for (IOBluetoothSDPServiceRecord *rec in records) {
        if (![rec isKindOfClass:[IOBluetoothSDPServiceRecord class]]) continue;
        IOBluetoothSDPDataElement *el = [rec getAttributeDataElement:kBluetoothSDPAttributeIdentifierServiceClassIDList];
        if (!el) continue;
        // 实测：ServiceClassIDList 可能是数组，也可能是单个 UUID 数据元素（Qwen Glasses 即后者）
        NSArray *list = [el getArrayValue];
        if (list) {
            for (IOBluetoothSDPDataElement *item in list) {
                if (matchUUID([item getUUIDValue])) return YES;
            }
        } else if (matchUUID([el getUUIDValue])) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - 强制 Classic 连接（唯一验证可靠的连接方式）

@interface QGSDPWaiter : NSObject
@property (nonatomic, assign) IOReturn status;
@property (nonatomic, assign) NSUInteger recordCount;
@end

static NSMutableSet<QGSDPWaiter *> *gSDPWaiters(void) {
    static NSMutableSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}

@implementation QGSDPWaiter
- (void)sdpQueryComplete:(IOBluetoothDevice *)device status:(IOReturn)status {
    self.status = status;
    self.recordCount = device.services.count;
    QGLog(@"SDP 完成 status=0x%08x records=%lu", status, (unsigned long)self.recordCount);
    [gSDPWaiters() removeObject:self];
}
@end

void QGOpenClassicConnection(NSString *address, BOOL authRequired, NSTimeInterval waitTimeout, QGClassicConnectCompletion completion) {
    QGLog(@"QGOpenClassicConnection %@ auth=%d", address, authRequired);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^report)(BOOL, NSString *) = ^(BOOL ok, NSString *msg) {
            QGLog(@"结果 ok=%d msg=%@", ok, msg);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(address, ok, msg); });
            }
        };

        IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
        if (!d) { report(NO, @"地址无效"); return; }

        // BR/EDR page，0x4000 * 0.625ms ≈ 10.24 秒超时；authenticationRequired 触发 Just Works 配对。
        // 已验证：连接+认证成功后 bluetoothd 自动完成 SDP 并注册 A2DP/HFP。
        IOReturn r = [d openConnection:nil withPageTimeout:0x4000 authenticationRequired:authRequired];
        QGLog(@"openConnection -> 0x%08x paired=%d connected=%d", r, [d isPaired], [d isConnected]);
        if (r != kIOReturnSuccess) {
            report(NO, [NSString stringWithFormat:@"BR/EDR 连接失败 (IOReturn=0x%08x)，设备可能不在可连接状态", r]);
            return;
        }

        // fire-and-forget SDP（刷新本地服务记录缓存；waiter 需保持强引用，IOBluetooth 不保留 target）
        QGSDPWaiter *w = [QGSDPWaiter new];
        [gSDPWaiters() addObject:w];
        IOReturn sr = [d performSDPQuery:w];
        QGLog(@"performSDPQuery -> 0x%08x", sr);
        if (sr != kIOReturnSuccess) [gSDPWaiters() removeObject:w];

        // forget 后眼镜会"回连-断开-回连"抖动，单次采样 isConnected 会误判。
        // 轮询采样：连接与音频服务各自一旦观测到即锁定。
        BOOL connected = [d isConnected];
        BOOL hasAudio = connected ? QGHasAudioService(address) : NO;
        NSTimeInterval deadline = waitTimeout > 0 ? waitTimeout : 15;
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:deadline];
        while (!(connected && hasAudio) && [end timeIntervalSinceNow] > 0) {
            [NSThread sleepForTimeInterval:0.5];
            if (!connected) connected = [d isConnected];
            if (connected && !hasAudio) hasAudio = QGHasAudioService(address);
        }
        QGLog(@"轮询结束 connected=%d hasAudio=%d name=%@", connected, hasAudio, d.name);

        if (connected && hasAudio) {
            report(YES, [NSString stringWithFormat:@"已连接 (paired=%d)，A2DP/HFP 音频服务已注册: %@",
                          [d isPaired], d.name ?: @""]);
        } else if (connected) {
            report(NO, [NSString stringWithFormat:@"已连接 (%@) 但未发现音频服务——地址可能不是 Classic 地址",
                          d.name ?: address]);
        } else {
            report(NO, @"openConnection 返回成功但设备始终未稳定连接（连接抖动/被拒），请重试");
        }
    });
}

#pragma mark - 设备状态查询

BOOL QGIsPaired(NSString *address) {
    IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
    return d && [d isPaired];
}

BOOL QGIsConnected(NSString *address) {
    IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
    return d && [d isConnected];
}

NSString *QGDeviceName(NSString *address) {
    IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
    return d.name;
}

NSArray<NSString *> *QGPairedAddresses(void) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id obj in [IOBluetoothDevice pairedDevices]) {
        if ([obj isKindOfClass:[IOBluetoothDevice class]]) {
            IOBluetoothDevice *d = (IOBluetoothDevice *)obj;
            if (d.addressString) [result addObject:d.addressString];
        }
    }
    return result;
}

int32_t QGDisconnectDevice(NSString *address) {
    IOBluetoothDevice *d = [IOBluetoothDevice deviceWithAddressString:address];
    if (!d) return -1;
    return (int32_t)[d closeConnection];
}

#pragma mark - 系统事件监听

@interface QGWatcher : NSObject
@property (nonatomic, copy) NSString *address; // nil = 所有设备
@property (nonatomic, copy) QGConnectionEvent onEvent;
@property (nonatomic, strong) IOBluetoothUserNotification *connNotif;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IOBluetoothUserNotification *> *discNotifs;
@end

@implementation QGWatcher

- (instancetype)init {
    if (self = [super init]) {
        _discNotifs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)matches:(IOBluetoothDevice *)device {
    if (!self.address) return YES;
    return device.addressString &&
           [device.addressString caseInsensitiveCompare:self.address] == NSOrderedSame;
}

- (void)fireEvent:(NSString *)event device:(IOBluetoothDevice *)device {
    if (!self.onEvent || !device) return;
    if (![self matches:device]) return;
    NSString *addr = device.addressString ?: @"?";
    QGConnectionEvent cb = self.onEvent;
    dispatch_async(dispatch_get_main_queue(), ^{ cb(addr, event); });
}

- (void)deviceConnected:(IOBluetoothUserNotification *)notification device:(IOBluetoothDevice *)device {
    if (![self matches:device]) return;
    NSString *addr = device.addressString ?: @"?";
    if (!self.discNotifs[addr]) {
        self.discNotifs[addr] = [device registerForDisconnectNotification:self selector:@selector(deviceDisconnected:device:)];
    }
    [self fireEvent:@"connected" device:device];
}

- (void)deviceDisconnected:(IOBluetoothUserNotification *)notification device:(IOBluetoothDevice *)device {
    [self fireEvent:@"disconnected" device:device];
}

- (void)dealloc {
    [_connNotif unregister];
    for (IOBluetoothUserNotification *n in _discNotifs.allValues) [n unregister];
}

@end

static NSMutableSet<QGWatcher *> *gWatchers = nil;

id QGWatchDevice(NSString *address, QGConnectionEvent onEvent) {
    QGWatcher *w = [QGWatcher new];
    w.address = address;
    w.onEvent = onEvent;
    w.connNotif = [IOBluetoothDevice registerForConnectNotifications:w selector:@selector(deviceConnected:device:)];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gWatchers = [NSMutableSet set]; });
    [gWatchers addObject:w];
    return w;
}

void QGUnwatchDevice(id token) {
    if (!token) return;
    [gWatchers removeObject:(QGWatcher *)token];
}

#pragma mark - 系统设置

void QGOpenBluetoothSettings(void) {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.BluetoothSettings"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

void QGOpenSoundSettings(void) {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.sound"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}
