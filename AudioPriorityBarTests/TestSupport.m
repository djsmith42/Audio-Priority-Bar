#import "TestSupport.h"

@implementation APBFakeAudio

- (instancetype)init {
    if ((self = [super init])) {
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

+ (NSString *)muteKeyForRole:(APBDeviceRole)role deviceID:(UInt32)deviceID {
    return [NSString stringWithFormat:@"%@:%u", APBDeviceRoleName(role), deviceID];
}

- (NSArray<NSNumber *> *)selectedRoles {
    NSMutableArray *roles = [NSMutableArray array];
    for (NSArray<NSNumber *> *selection in _selections) [roles addObject:selection[0]];
    return roles;
}

- (NSArray<NSNumber *> *)selectedIDs {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSArray<NSNumber *> *selection in _selections) [ids addObject:selection[1]];
    return ids;
}

- (APBAudioOperations *)operations {
    APBAudioOperations *operations = [[APBAudioOperations alloc] init];
    // The fake outlives every model in a test, so a strong reference is fine.
    APBFakeAudio *fake = self;
    operations.devices = ^{ return fake.catalog; };
    operations.defaultDevice = ^NSNumber *(APBDeviceRole role) { return fake.defaults[@(role)]; };
    operations.setDefault = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
        if (!fake.selectionSucceeds || [fake.failedSelectionRoles containsObject:@(role)]) return NO;
        fake.defaults[@(role)] = @(deviceID);
        [fake.selections addObject:@[@(role), @(deviceID)]];
        return YES;
    };
    operations.outputVolume = ^NSNumber *{
        fake.volumeReadCount += 1;
        return fake.volume;
    };
    operations.setOutputVolume = ^BOOL(float value) {
        fake.volume = @(value);
        return YES;
    };
    operations.isMuted = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
        fake.muteReadCount += 1;
        return [fake.muted containsObject:[APBFakeAudio muteKeyForRole:role deviceID:deviceID]];
    };
    operations.setMute = ^BOOL(APBDeviceRole role, UInt32 deviceID, BOOL muted) {
        if ([fake.noMuteProperty containsObject:@(deviceID)]) return NO;
        NSString *key = [APBFakeAudio muteKeyForRole:role deviceID:deviceID];
        if (muted) {
            [fake.muted addObject:key];
        } else {
            [fake.muted removeObject:key];
        }
        return YES;
    };
    operations.canSetMute = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
        return ![fake.noMuteProperty containsObject:@(deviceID)];
    };
    operations.inputVolume = ^NSNumber *(UInt32 deviceID) { return fake.inputVolumes[@(deviceID)]; };
    operations.setInputVolume = ^BOOL(UInt32 deviceID, float value) {
        if (!fake.inputVolumes[@(deviceID)]) return NO;
        fake.inputVolumes[@(deviceID)] = @(value);
        return YES;
    };
    operations.isRunning = ^BOOL(UInt32 deviceID) { return [fake.running containsObject:@(deviceID)]; };
    return operations;
}

@end

APBAppModel *APBTestModel(APBFakeAudio *audio,
                          NSUserDefaults *defaults,
                          BOOL (^usable)(APBAudioDevice *),
                          APBLinkState (^state)(APBAudioDevice *),
                          BOOL (^isUserPicking)(void)) {
    APBLinkOperations *link = [[APBLinkOperations alloc]
        initWithIsUsable:usable ?: ^BOOL(APBAudioDevice *device) { return YES; }
                   state:state ?: ^APBLinkState(APBAudioDevice *device) { return APBLinkStateNone; }];
    return [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] initWithDefaults:defaults]
                                        audio:audio.operations
                                         link:link
                                      battery:nil
                                 reduceMotion:nil
                                isUserPicking:isUserPicking];
}

APBAudioDevice *APBOutput(UInt32 deviceID, NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:deviceID uid:uid name:name ?: @"Speaker" role:APBDeviceRoleOutput];
}

APBAudioDevice *APBInput(UInt32 deviceID, NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:deviceID uid:uid name:name ?: @"Microphone" role:APBDeviceRoleInput];
}

NSUserDefaults *APBIsolatedDefaults(void) {
    NSString *suite = [@"AppModelTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults removePersistentDomainForName:suite];
    return defaults;
}

void APBDrainMainQueue(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!drained && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}
