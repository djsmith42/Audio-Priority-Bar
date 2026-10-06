#import "CoreAudioListeners.h"

@implementation APBDeviceListener

+ (instancetype)listenerWithKind:(APBDeviceListenerKind)kind
                        deviceID:(AudioObjectID)deviceID
                            role:(APBDeviceRole)role
                         element:(AudioObjectPropertyElement)element {
    APBDeviceListener *listener = [[self alloc] init];
    listener->_kind = kind;
    listener->_deviceID = deviceID;
    listener->_role = role;
    listener->_element = element;
    return listener;
}

+ (instancetype)muteWithID:(AudioObjectID)deviceID role:(APBDeviceRole)role element:(AudioObjectPropertyElement)element {
    return [self listenerWithKind:APBDeviceListenerKindMute deviceID:deviceID role:role element:element];
}

+ (instancetype)volumeWithID:(AudioObjectID)deviceID {
    return [self listenerWithKind:APBDeviceListenerKindVolume deviceID:deviceID role:APBDeviceRoleOutput element:0];
}

+ (instancetype)inputVolumeWithID:(AudioObjectID)deviceID {
    return [self listenerWithKind:APBDeviceListenerKindInputVolume deviceID:deviceID role:APBDeviceRoleOutput element:0];
}

+ (instancetype)runningWithID:(AudioObjectID)deviceID {
    return [self listenerWithKind:APBDeviceListenerKindRunning deviceID:deviceID role:APBDeviceRoleOutput element:0];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBDeviceListener.class]) return NO;
    APBDeviceListener *other = object;
    return _kind == other.kind && _deviceID == other.deviceID
        && _role == other.role && _element == other.element;
}

- (NSUInteger)hash {
    return (NSUInteger)_deviceID << 8 ^ (NSUInteger)_kind << 4 ^ (NSUInteger)_role << 2 ^ _element;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<listener kind %ld id %u role %ld element %u>",
            (long)_kind, _deviceID, (long)_role, _element];
}

@end

@implementation APBCoreAudioListenerLifecycle {
    BOOL (^_addSystem)(APBSystemListener);
    void (^_removeSystem)(APBSystemListener);
    NSArray<NSNumber *> *(^_deviceIDs)(void);
    BOOL (^_addDevice)(APBDeviceListener *);
    void (^_removeDevice)(APBDeviceListener *);
    NSMutableSet<APBDeviceListener *> *_deviceListeners;
}

- (instancetype)initWithAddSystem:(BOOL (^)(APBSystemListener))addSystem
                     removeSystem:(void (^)(APBSystemListener))removeSystem
                        deviceIDs:(NSArray<NSNumber *> *(^)(void))deviceIDs
                        addDevice:(BOOL (^)(APBDeviceListener *))addDevice
                     removeDevice:(void (^)(APBDeviceListener *))removeDevice {
    if ((self = [super init])) {
        _addSystem = [addSystem copy];
        _removeSystem = [removeSystem copy];
        _deviceIDs = [deviceIDs copy];
        _addDevice = [addDevice copy];
        _removeDevice = [removeDevice copy];
        _deviceListeners = [NSMutableSet set];
    }
    return self;
}

- (BOOL)start {
    if (_isListening) return YES;
    if (!_addSystem(APBSystemListenerDevices)) return NO;
    if (!_addSystem(APBSystemListenerDefaultInput)) {
        _removeSystem(APBSystemListenerDevices);
        return NO;
    }
    if (!_addSystem(APBSystemListenerDefaultOutput)) {
        _removeSystem(APBSystemListenerDefaultInput);
        _removeSystem(APBSystemListenerDevices);
        return NO;
    }
    _isListening = YES;
    [self rebuildDeviceListeners];
    return YES;
}

- (void)rebuildDeviceListeners {
    if (!_isListening) return;
    [self clearDeviceListeners];
    NSMutableOrderedSet<APBDeviceListener *> *desired = [NSMutableOrderedSet orderedSet];
    for (NSNumber *number in _deviceIDs()) {
        AudioObjectID deviceID = number.unsignedIntValue;
        [desired addObjectsFromArray:@[
            [APBDeviceListener muteWithID:deviceID role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain],
            [APBDeviceListener muteWithID:deviceID role:APBDeviceRoleOutput element:1],
            [APBDeviceListener muteWithID:deviceID role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain],
            [APBDeviceListener muteWithID:deviceID role:APBDeviceRoleInput element:1],
            [APBDeviceListener volumeWithID:deviceID],
            [APBDeviceListener inputVolumeWithID:deviceID],
            [APBDeviceListener runningWithID:deviceID],
        ]];
    }
    for (APBDeviceListener *listener in desired) {
        if (_addDevice(listener)) [_deviceListeners addObject:listener];
    }
}

- (void)stop {
    if (!_isListening) return;
    [self clearDeviceListeners];
    _removeSystem(APBSystemListenerDevices);
    _removeSystem(APBSystemListenerDefaultInput);
    _removeSystem(APBSystemListenerDefaultOutput);
    _isListening = NO;
}

- (void)clearDeviceListeners {
    for (APBDeviceListener *listener in _deviceListeners) _removeDevice(listener);
    [_deviceListeners removeAllObjects];
}

@end

@implementation APBCoreAudioCallbackGate {
    NSLock *_lock;
    BOOL _isActive;
    void (^_handler)(APBCoreAudioEventKind, APBDeviceRole);
}

- (instancetype)initWithHandler:(void (^)(APBCoreAudioEventKind, APBDeviceRole))handler {
    if ((self = [super init])) {
        _lock = [[NSLock alloc] init];
        _handler = [handler copy];
    }
    return self;
}

- (void)setActive:(BOOL)active {
    [_lock lock];
    _isActive = active;
    [_lock unlock];
}

- (void)send:(APBCoreAudioEventKind)kind role:(APBDeviceRole)role {
    [_lock lock];
    BOOL shouldSend = _isActive;
    [_lock unlock];
    if (shouldSend) _handler(kind, role);
}

@end
