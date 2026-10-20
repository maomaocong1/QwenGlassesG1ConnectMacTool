#import "IOBluetoothShim.h"
#import <IOBluetooth/IOBluetooth.h>
#import <AppKit/AppKit.h>

#pragma mark - 配对任务

@interface QGBridge : NSObject
+ (NSMutableSet *)agents;
+ (void)removeAgent:(id)agent;
@end

@interface QGPairAgent : NSObject <IOBluetoothDevicePairDelegate>
@property (nonatomic, strong) IOBluetoothDevice *device;
@property (nonatomic, strong) IOBluetoothDevicePair *pair;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, copy) QGPairCompletion completion;
@property (nonatomic, copy) QGPairEvent onEvent;
@property (nonatomic, copy) NSString *autoPIN;      // nil/空 = 等待手动回复
@property (nonatomic, assign) BOOL autoConfirm;
@property (nonatomic, assign) BOOL awaitingPIN;
@property (nonatomic, assign) BOOL awaitingConfirm;
@property (nonatomic, copy) NSString *lastEvent;
@end

static QGPairAgent *gCurrentPairTask = nil;

@implementation QGPairAgent

- (void)emit:(NSString *)event detail:(NSString *)detail {
    self.lastEvent = detail ? [NSString stringWithFormat:@"%@: %@", event, detail] : event;
    if (self.onEvent) {
        QGPairEvent cb = self.onEvent;
        dispatch_async(dispatch_get_main_queue(), ^{ cb(event, detail); });
    }
}

- (void)finishWithSuccess:(BOOL)success message:(NSString *)message {
    if (self.finished) return;
    self.finished = YES;
    if (gCurrentPairTask == self) gCurrentPairTask = nil;
    [QGBridge removeAgent:self];
    [self emit:success ? @"finished" : @"failed" detail:message];
    if (self.completion) {
        NSString *addr = self.device.addressString ?: @"";
        QGPairCompletion cb = self.completion;
        self.completion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ cb(addr, success, message); });
    }
}

- (void)devicePairingStarted:(id)sender {
    [self emit:@"started" detail:@"配对流程已启动"];
}

- (void)devicePairingConnecting:(id)sender {
    [self emit:@"connecting" detail:@"正在建立基带连接…"];
}

- (void)devicePairingConnected:(id)sender {
    [self emit:@"connected" detail:@"基带已连接，等待认证…"];
}

- (void)devicePairingPINCodeRequest:(id)sender {
    if (self.autoPIN.length > 0) {
        [self emit:@"pin_request" detail:[NSString stringWithFormat:@"设备请求 PIN，自动回复「%@」", self.autoPIN]];
        [self replyPINString:self.autoPIN sender:sender];
    } else {
        self.awaitingPIN = YES;
        [self emit:@"pin_request" detail:@"设备请求 PIN，请在 App 配对面板手动输入"];
    }
}

- (void)replyPINString:(NSString *)pin sender:(id)sender {
    BluetoothPINCode code;
    memset(&code, 0, sizeof(code));
    const char *utf8 = [pin UTF8String] ?: "";
    ByteCount size = (ByteCount)MIN(strlen(utf8), sizeof(code.data));
    memcpy(code.data, utf8, size);
    [(IOBluetoothDevicePair *)sender replyPINCode:size PINCode:&code];
    self.awaitingPIN = NO;
}

- (void)devicePairingUserConfirmationRequest:(id)sender numericValue:(BluetoothNumericValue)numericValue {
    NSString *valueStr = [NSString stringWithFormat:@"%u", (unsigned)numericValue];
    if (self.autoConfirm) {
        [self emit:@"confirm_request" detail:[NSString stringWithFormat:@"数字比较 %@，自动接受", valueStr]];
        [(IOBluetoothDevicePair *)sender replyUserConfirmation:YES];
        self.awaitingConfirm = NO;
    } else {
        self.awaitingConfirm = YES;
        [self emit:@"confirm_request" detail:[NSString stringWithFormat:@"等待确认数字: %@", valueStr]];
    }
}

- (void)devicePairingUserPasskeyNotification:(id)sender passkey:(BluetoothPasskey)passkey {
    [self emit:@"passkey_notify" detail:[NSString stringWithFormat:@"Passkey: %u", (unsigned)passkey]];
}

- (void)devicePairingFinished:(id)sender error:(IOReturn)error {
    BOOL ok = (error == kIOReturnSuccess) || [self.device isPaired];
    NSString *msg = ok ? @"配对成功"
                       : [NSString stringWithFormat:@"配对失败 (IOReturn=0x%08x)%@", error,
                            self.lastEvent.length ? [NSString stringWithFormat:@"，最后事件: %@", self.lastEvent] : @""];
    [self finishWithSuccess:ok message:msg];
}

- (void)deviceSimplePairingComplete:(id)sender status:(BluetoothHCIEventStatus)status {
    if (status != 0) {
        [self emit:@"simple_pairing" detail:[NSString stringWithFormat:@"Simple Pairing 失败 status=%d", status]];
        [self finishWithSuccess:NO message:[NSString stringWithFormat:@"Simple Pairing 失败 (status=%d)", status]];
    } else {
        [self emit:@"simple_pairing" detail:@"Simple Pairing 完成"];
    }
}

@end

@implementation QGBridge
+ (NSMutableSet<QGPairAgent *> *)agents {
    static NSMutableSet *set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}
+ (void)removeAgent:(QGPairAgent *)agent { [self.agents removeObject:agent]; }
@end

int32_t QGStartPairing(NSString *address,
                       NSString *autoPIN,
                       BOOL autoConfirm,
                       NSTimeInterval timeoutSeconds,
                       QGPairEvent onEvent,
                       QGPairCompletion completion) {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    if (!device) {
        if (completion) completion(address, NO, @"无法创建 IOBluetoothDevice（地址无效）");
        return -1;
    }

    QGPairAgent *agent = [QGPairAgent new];
    agent.device = device;
    agent.completion = completion;
    agent.onEvent = onEvent;
    agent.autoPIN = autoPIN;
    agent.autoConfirm = autoConfirm;
    agent.pair = [IOBluetoothDevicePair pairWithDevice:device];
    agent.pair.delegate = agent;

    IOReturn ret = [agent.pair start];
    if (ret != kIOReturnSuccess) {
        NSString *msg = [NSString stringWithFormat:@"配对无法启动 (IOReturn=0x%08x)，设备可能不在配对模式", ret];
        if (completion) completion(address, NO, msg);
        return -2;
    }

    [QGBridge.agents addObject:agent];
    gCurrentPairTask = agent;

    // 超时兜底
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (agent.awaitingPIN || agent.awaitingConfirm) {
            [agent emit:@"timeout" detail:@"等待用户响应超时"];
            [agent finishWithSuccess:[device isPaired] message:@"配对超时：等待 PIN/确认响应"];
        } else {
            [agent emit:@"timeout" detail:nil];
            [agent finishWithSuccess:[device isPaired] message:@"配对超时（设备可能未在配对模式，或需要先在 BLE 通道完成握手）"];
        }
    });
    return 0;
}

void QGCancelPairing(NSString *address) {
    for (QGPairAgent *agent in [QGBridge.agents copy]) {
        if ([agent.device.addressString caseInsensitiveCompare:address] == NSOrderedSame) {
            [agent.pair stop];
            [agent emit:@"cancelled" detail:nil];
            [agent finishWithSuccess:NO message:@"已取消"];
        }
    }
}

void QGPairReplyPIN(NSString *pin) {
    QGPairAgent *agent = gCurrentPairTask;
    if (agent && agent.awaitingPIN && !agent.finished) {
        [agent emit:@"pin_reply" detail:[NSString stringWithFormat:@"手动回复 PIN「%@」", pin]];
        [agent replyPINString:pin sender:agent.pair];
    }
}

void QGPairReplyConfirmation(BOOL accept) {
    QGPairAgent *agent = gCurrentPairTask;
    if (agent && agent.awaitingConfirm && !agent.finished) {
        agent.awaitingConfirm = NO;
        [agent emit:@"confirm_reply" detail:accept ? @"手动接受" : @"手动拒绝"];
        [agent.pair replyUserConfirmation:accept];
    }
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
