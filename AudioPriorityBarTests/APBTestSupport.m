#import "APBTestSupport.h"

@implementation APBSelection

- (instancetype)initWithRole:(APBDeviceRole)role deviceID:(UInt32)deviceID {
    self = [super init];
    if (self) {
        _role = role;
        _deviceID = deviceID;
    }
    return self;
}

@end

static NSString *MuteKey(APBDeviceRole role, UInt32 deviceID) {
    return [NSString stringWithFormat:@"%@:%u", APBDeviceRoleName(role), deviceID];
}

@implementation APBFakeAudio

- (instancetype)init {
    self = [super init];
    if (self) {
        _catalog = @[];
        _defaults = [NSMutableDictionary dictionary];
        _muted = [NSMutableSet set];
        _selections = [NSMutableArray array];
        _selectionSucceeds = YES;
        _failedSelectionRoles = [NSMutableSet set];
        _noMuteProperty = [NSMutableSet set];
        _inputVolumes = [NSMutableDictionary dictionary];
        _running = [NSMutableSet set];
    }
    return self;
}

- (NSArray<NSNumber *> *)selectedIDs {
    NSMutableArray *ids = [NSMutableArray array];
    for (APBSelection *selection in _selections) [ids addObject:@(selection.deviceID)];
    return ids;
}

- (NSArray<NSNumber *> *)selectedRoles {
    NSMutableArray *roles = [NSMutableArray array];
    for (APBSelection *selection in _selections) [roles addObject:@(selection.role)];
    return roles;
}

- (void)setDefault:(UInt32)deviceID role:(APBDeviceRole)role {
    _defaults[@(role)] = @(deviceID);
}

- (NSArray<APBAudioDevice *> *)devices {
    return _catalog;
}

- (UInt32)defaultDeviceForRole:(APBDeviceRole)role {
    return _defaults[@(role)].unsignedIntValue;
}

- (BOOL)setDefaultDevice:(UInt32)deviceID role:(APBDeviceRole)role {
    if (!_selectionSucceeds || [_failedSelectionRoles containsObject:@(role)]) return NO;
    _defaults[@(role)] = @(deviceID);
    [_selections addObject:[[APBSelection alloc] initWithRole:role deviceID:deviceID]];
    return YES;
}

- (NSNumber *)outputVolume {
    _volumeReadCount += 1;
    return _volume;
}

- (BOOL)setOutputVolume:(float)value {
    _volume = @(value);
    return YES;
}

- (BOOL)isMuted:(UInt32)deviceID role:(APBDeviceRole)role {
    _muteReadCount += 1;
    return [_muted containsObject:MuteKey(role, deviceID)];
}

- (BOOL)setMute:(UInt32)deviceID role:(APBDeviceRole)role muted:(BOOL)muted {
    if ([_noMuteProperty containsObject:@(deviceID)]) return NO;
    if (muted) {
        [_muted addObject:MuteKey(role, deviceID)];
    } else {
        [_muted removeObject:MuteKey(role, deviceID)];
    }
    return YES;
}

- (BOOL)canSetMute:(UInt32)deviceID role:(APBDeviceRole)role {
    return ![_noMuteProperty containsObject:@(deviceID)];
}

- (NSNumber *)inputVolume:(UInt32)deviceID {
    return _inputVolumes[@(deviceID)];
}

- (BOOL)setInputVolume:(UInt32)deviceID value:(float)value {
    if (!_inputVolumes[@(deviceID)]) return NO;
    _inputVolumes[@(deviceID)] = @(value);
    return YES;
}

- (BOOL)isRunning:(UInt32)deviceID {
    return [_running containsObject:@(deviceID)];
}

@end

APBAudioDevice *APBOutput(UInt32 deviceID, NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:deviceID uid:uid name:name ?: @"Speaker" role:APBDeviceRoleOutput];
}

APBAudioDevice *APBInput(UInt32 deviceID, NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:deviceID uid:uid name:name ?: @"Microphone" role:APBDeviceRoleInput];
}

NSUserDefaults *APBIsolatedDefaults(void) {
    NSString *suite = [NSString stringWithFormat:@"AppModelTests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    return defaults;
}

APBAppModel *APBTestModel(APBFakeAudio *audio,
                          NSUserDefaults *defaults,
                          APBLinkUsable usable,
                          APBLinkStateProvider state,
                          BOOL (^isUserPicking)(void)) {
    return [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] initWithDefaults:defaults]
                                        audio:audio
                                     isUsable:usable ?: ^BOOL(APBAudioDevice *device) { return YES; }
                                    linkState:state ?: ^APBLinkState(APBAudioDevice *device) { return APBLinkStateNone; }
                                      battery:nil
                                 reduceMotion:^BOOL { return NO; }
                                isUserPicking:isUserPicking];
}

BOOL APBWaitUntil(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}

NSArray<NSArray<NSString *> *> *APBUIDLists(NSArray<NSArray<APBAudioDevice *> *> *lists) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSArray<APBAudioDevice *> *list in lists) [result addObject:[list valueForKey:@"uid"]];
    return result;
}
