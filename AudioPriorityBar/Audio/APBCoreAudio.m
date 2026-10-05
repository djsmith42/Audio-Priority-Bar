#import "APBCoreAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <os/lock.h>

static AudioObjectPropertyAddress Property(AudioObjectPropertySelector selector,
                                           AudioObjectPropertyScope scope,
                                           AudioObjectPropertyElement element) {
    return (AudioObjectPropertyAddress){ selector, scope, element };
}

static OSStatus Read(AudioObjectID objectID,
                     AudioObjectPropertySelector selector,
                     AudioObjectPropertyScope scope,
                     AudioObjectPropertyElement element,
                     void *value,
                     UInt32 size) {
    AudioObjectPropertyAddress address = Property(selector, scope, element);
    return AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, value);
}

static OSStatus Write(AudioObjectID objectID,
                      AudioObjectPropertySelector selector,
                      AudioObjectPropertyScope scope,
                      AudioObjectPropertyElement element,
                      const void *value,
                      UInt32 size) {
    AudioObjectPropertyAddress address = Property(selector, scope, element);
    return AudioObjectSetPropertyData(objectID, &address, 0, NULL, size, value);
}

static AudioObjectPropertyScope ScopeForRole(APBDeviceRole role) {
    return role == APBDeviceRoleInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput;
}

static AudioObjectPropertySelector DefaultSelector(APBDeviceRole role) {
    return role == APBDeviceRoleInput
        ? kAudioHardwarePropertyDefaultInputDevice
        : kAudioHardwarePropertyDefaultOutputDevice;
}

@implementation APBCoreAudioProperties

+ (NSArray<NSNumber *> *)objectIDs:(AudioObjectID)objectID
                          selector:(AudioObjectPropertySelector)selector
                             scope:(AudioObjectPropertyScope)scope {
    AudioObjectPropertyAddress address = Property(selector, scope, kAudioObjectPropertyElementMain);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(objectID, &address, 0, NULL, &size) != noErr || size == 0) return @[];
    NSUInteger count = size / sizeof(AudioObjectID);
    AudioObjectID *ids = calloc(count, sizeof(AudioObjectID));
    if (!ids) return @[];
    NSMutableArray *result = [NSMutableArray array];
    if (AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, ids) == noErr) {
        NSUInteger read = size / sizeof(AudioObjectID);
        for (NSUInteger index = 0; index < MIN(read, count); index++) [result addObject:@(ids[index])];
    }
    free(ids);
    return result;
}

+ (NSArray<NSNumber *> *)deviceIDs {
    return [self objectIDs:kAudioObjectSystemObject
                  selector:kAudioHardwarePropertyDevices
                     scope:kAudioObjectPropertyScopeGlobal];
}

- (NSArray<APBAudioDevice *> *)devices {
    NSMutableArray *devices = [NSMutableArray array];
    for (NSNumber *deviceID in APBCoreAudioProperties.deviceIDs) {
        for (NSNumber *role in @[ @(APBDeviceRoleInput), @(APBDeviceRoleOutput) ]) {
            APBAudioDevice *device = [APBCoreAudioProperties makeDevice:deviceID.unsignedIntValue
                                                                   role:role.integerValue];
            if (device) [devices addObject:device];
        }
    }
    return devices;
}

- (UInt32)defaultDeviceForRole:(APBDeviceRole)role {
    AudioObjectID deviceID = 0;
    if (Read(kAudioObjectSystemObject, DefaultSelector(role), kAudioObjectPropertyScopeGlobal,
             kAudioObjectPropertyElementMain, &deviceID, sizeof deviceID) != noErr
        || deviceID == kAudioObjectUnknown) {
        return 0;
    }
    return deviceID;
}

- (BOOL)setDefaultDevice:(UInt32)deviceID role:(APBDeviceRole)role {
    AudioObjectID value = deviceID;
    return Write(kAudioObjectSystemObject, DefaultSelector(role), kAudioObjectPropertyScopeGlobal,
                 kAudioObjectPropertyElementMain, &value, sizeof value) == noErr;
}

- (NSNumber *)outputVolume {
    UInt32 deviceID = [self defaultDeviceForRole:APBDeviceRoleOutput];
    if (deviceID == 0) return nil;
    Float32 volume = 0;
    if (Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput,
             kAudioObjectPropertyElementMain, &volume, sizeof volume) != noErr) {
        return nil;
    }
    return @(volume);
}

- (BOOL)setOutputVolume:(float)value {
    UInt32 deviceID = [self defaultDeviceForRole:APBDeviceRoleOutput];
    if (deviceID == 0) return NO;
    Float32 volume = value;
    return Write(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput,
                 kAudioObjectPropertyElementMain, &volume, sizeof volume) == noErr;
}

+ (float)deviceVolume:(AudioObjectID)deviceID {
    Float32 volume = 0;
    if (Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput,
             kAudioObjectPropertyElementMain, &volume, sizeof volume) != noErr) {
        return 1;
    }
    return volume;
}

- (BOOL)isMuted:(UInt32)deviceID role:(APBDeviceRole)role {
    AudioObjectPropertyScope scope = ScopeForRole(role);
    for (AudioObjectPropertyElement element = kAudioObjectPropertyElementMain; element <= 1; element++) {
        UInt32 muted = 0;
        if (Read(deviceID, kAudioDevicePropertyMute, scope, element, &muted, sizeof muted) == noErr && muted != 0) {
            return YES;
        }
    }
    return role == APBDeviceRoleOutput && [APBCoreAudioProperties deviceVolume:deviceID] < 0.01;
}

/// Sets the mute property, trying the main element before channel 1. NO when
/// the device has no settable mute, so the caller can fall back to zero input
/// volume.
- (BOOL)setMute:(UInt32)deviceID role:(APBDeviceRole)role muted:(BOOL)muted {
    UInt32 value = muted ? 1 : 0;
    for (AudioObjectPropertyElement element = kAudioObjectPropertyElementMain; element <= 1; element++) {
        if (Write(deviceID, kAudioDevicePropertyMute, ScopeForRole(role), element, &value, sizeof value) == noErr) {
            return YES;
        }
    }
    return NO;
}

/// Whether the mute property can be set, on the main element or channel 1,
/// matching where `setMute` writes it.
- (BOOL)canSetMute:(UInt32)deviceID role:(APBDeviceRole)role {
    for (AudioObjectPropertyElement element = kAudioObjectPropertyElementMain; element <= 1; element++) {
        AudioObjectPropertyAddress address = Property(kAudioDevicePropertyMute, ScopeForRole(role), element);
        Boolean settable = false;
        if (AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable) return YES;
    }
    return NO;
}

- (NSNumber *)inputVolume:(UInt32)deviceID {
    Float32 volume = 0;
    if (Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput,
             kAudioObjectPropertyElementMain, &volume, sizeof volume) != noErr) {
        return nil;
    }
    return @(volume);
}

- (BOOL)setInputVolume:(UInt32)deviceID value:(float)value {
    Float32 volume = value;
    return Write(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput,
                 kAudioObjectPropertyElementMain, &volume, sizeof volume) == noErr;
}

/// Whether any process is using the device, which for a microphone means some
/// app is recording from it.
- (BOOL)isRunning:(UInt32)deviceID {
    UInt32 running = 0;
    return Read(deviceID, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain, &running, sizeof running) == noErr && running != 0;
}

+ (APBAudioDevice *)makeDevice:(AudioObjectID)deviceID role:(APBDeviceRole)role {
    NSArray<NSNumber *> *streams = [self objectIDs:deviceID
                                          selector:kAudioDevicePropertyStreams
                                             scope:ScopeForRole(role)];
    if (streams.count == 0) return nil;
    NSString *name = [self stringProperty:deviceID selector:kAudioDevicePropertyDeviceNameCFString];
    NSString *uid = [self stringProperty:deviceID selector:kAudioDevicePropertyDeviceUID];
    if (!name || !uid) return nil;
    UInt32 transport = [self transport:deviceID];
    BOOL isOutput = role == APBDeviceRoleOutput;
    return [[APBAudioDevice alloc]
        initWithPlatformID:deviceID
                       uid:uid
                      name:name
                      role:role
               isConnected:YES
                 isVirtual:transport == kAudioDeviceTransportTypeVirtual
                           || transport == kAudioDeviceTransportTypeAggregate
          // Input terminals describe a microphone, which says nothing about
          // where output should go.
          declaredCategory:isOutput ? [self declaredCategoryForStreams:streams transport:transport] : APBOutputCategoryNone
           isDisplayOutput:isOutput && [self isDisplayTransport:transport]
             transportType:transport];
}

/// The category a device claims for itself, or `None` when it claims nothing
/// usable. Aggregate devices report `Unknown` and HDMI reports its own
/// terminal, so the caller still needs a fallback.
+ (APBOutputCategory)declaredCategoryForStreams:(NSArray<NSNumber *> *)streams transport:(UInt32)transport {
    NSMutableArray *terminals = [NSMutableArray array];
    for (NSNumber *stream in streams) {
        UInt32 terminal = 0;
        // AudioStream has only a global scope.
        if (Read(stream.unsignedIntValue, kAudioStreamPropertyTerminalType, kAudioObjectPropertyScopeGlobal,
                 kAudioObjectPropertyElementMain, &terminal, sizeof terminal) == noErr) {
            [terminals addObject:@(terminal)];
        }
    }
    return [self categoryForTerminals:terminals transport:transport];
}

+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals transport:(UInt32)transport {
    APBOutputCategory declared = [self categoryForTerminals:terminals];
    BOOL isBluetooth = transport == kAudioDeviceTransportTypeBluetooth
        || transport == kAudioDeviceTransportTypeBluetoothLE;
    return isBluetooth && declared == APBOutputCategoryHeadphone ? APBOutputCategoryNone : declared;
}

+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals {
    NSMutableSet *declared = [NSMutableSet set];
    for (NSNumber *terminal in terminals) {
        APBOutputCategory category = [self categoryForTerminal:terminal.unsignedIntValue];
        if (category != APBOutputCategoryNone) [declared addObject:@(category)];
    }
    return declared.count == 1 ? [declared.anyObject integerValue] : APBOutputCategoryNone;
}

+ (APBOutputCategory)categoryForTerminal:(UInt32)terminal {
    switch (terminal) {
        case kAudioStreamTerminalTypeHeadphones:
        case 0x0302: // Headphones
        case 0x0303: // Head mounted display audio
        case 0x0401: // Handset
        case 0x0402: // Headset
            return APBOutputCategoryHeadphone;
        case kAudioStreamTerminalTypeSpeaker:
        case kAudioStreamTerminalTypeLFESpeaker:
        case kAudioStreamTerminalTypeReceiverSpeaker:
        case 0x0301: // Speaker
        case 0x0304: // Desktop speaker
        case 0x0305: // Room speaker
        case 0x0306: // Communication speaker
        case 0x0307: // Low frequency effects speaker
        case 0x0403: // Speakerphone, no echo reduction
        case 0x0404: // Echo suppressing speakerphone
        case 0x0405: // Echo cancelling speakerphone
            return APBOutputCategorySpeaker;
        default:
            return APBOutputCategoryNone;
    }
}

+ (UInt32)transport:(AudioObjectID)deviceID {
    UInt32 transport = 0;
    if (Read(deviceID, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal,
             kAudioObjectPropertyElementMain, &transport, sizeof transport) != noErr) {
        return kAudioDeviceTransportTypeUnknown;
    }
    return transport;
}

+ (BOOL)isDisplayTransport:(UInt32)transport {
    return transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort;
}

+ (NSString *)stringProperty:(AudioObjectID)deviceID selector:(AudioObjectPropertySelector)selector {
    CFStringRef value = NULL;
    if (Read(deviceID, selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain,
             &value, sizeof value) != noErr || value == NULL) {
        return nil;
    }
    return (__bridge_transfer NSString *)value;
}

@end

#pragma mark - Listener lifecycle

@implementation APBDeviceListener

+ (instancetype)muteWithID:(AudioObjectID)deviceID role:(APBDeviceRole)role element:(AudioObjectPropertyElement)element {
    APBDeviceListener *listener = [[self alloc] init];
    listener->_kind = APBDeviceListenerKindMute;
    listener->_deviceID = deviceID;
    listener->_role = role;
    listener->_element = element;
    return listener;
}

+ (instancetype)listenerWithKind:(APBDeviceListenerKind)kind deviceID:(AudioObjectID)deviceID {
    APBDeviceListener *listener = [[self alloc] init];
    listener->_kind = kind;
    listener->_deviceID = deviceID;
    listener->_role = APBDeviceRoleOutput;
    listener->_element = kAudioObjectPropertyElementMain;
    return listener;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBDeviceListener.class]) return NO;
    APBDeviceListener *other = object;
    return _kind == other->_kind && _deviceID == other->_deviceID
        && _role == other->_role && _element == other->_element;
}

- (NSUInteger)hash {
    return ((NSUInteger)_deviceID << 8) ^ ((NSUInteger)_kind << 4) ^ ((NSUInteger)_role << 2) ^ _element;
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
    self = [super init];
    if (self) {
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
    NSMutableOrderedSet *desired = [NSMutableOrderedSet orderedSet];
    for (NSNumber *number in _deviceIDs()) {
        AudioObjectID deviceID = number.unsignedIntValue;
        [desired addObject:[APBDeviceListener muteWithID:deviceID role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain]];
        [desired addObject:[APBDeviceListener muteWithID:deviceID role:APBDeviceRoleOutput element:1]];
        [desired addObject:[APBDeviceListener muteWithID:deviceID role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain]];
        [desired addObject:[APBDeviceListener muteWithID:deviceID role:APBDeviceRoleInput element:1]];
        [desired addObject:[APBDeviceListener listenerWithKind:APBDeviceListenerKindVolume deviceID:deviceID]];
        [desired addObject:[APBDeviceListener listenerWithKind:APBDeviceListenerKindInputVolume deviceID:deviceID]];
        [desired addObject:[APBDeviceListener listenerWithKind:APBDeviceListenerKindRunning deviceID:deviceID]];
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

#pragma mark - Observer

typedef NS_ENUM(NSInteger, APBCoreAudioEvent) {
    APBCoreAudioEventDevicesChanged,
    APBCoreAudioEventDefaultInputChanged,
    APBCoreAudioEventDefaultOutputChanged,
    APBCoreAudioEventMuteOrVolumeChanged,
};

/// The context CoreAudio calls back with. Only forwards while active, so a
/// callback racing `stop` is dropped.
@interface APBCoreAudioCallbackGate : NSObject
@property (nonatomic, copy) void (^handler)(APBCoreAudioEvent event);
- (void)setActive:(BOOL)active;
- (void)send:(APBCoreAudioEvent)event;
@end

@implementation APBCoreAudioCallbackGate {
    os_unfair_lock _lock;
    BOOL _isActive;
}

- (instancetype)init {
    self = [super init];
    if (self) _lock = OS_UNFAIR_LOCK_INIT;
    return self;
}

- (void)setActive:(BOOL)active {
    os_unfair_lock_lock(&_lock);
    _isActive = active;
    os_unfair_lock_unlock(&_lock);
}

- (void)send:(APBCoreAudioEvent)event {
    os_unfair_lock_lock(&_lock);
    BOOL shouldSend = _isActive;
    os_unfair_lock_unlock(&_lock);
    if (shouldSend) _handler(event);
}

@end

static OSStatus DevicesProc(AudioObjectID objectID, UInt32 count, const AudioObjectPropertyAddress *addresses, void *context) {
    [(__bridge APBCoreAudioCallbackGate *)context send:APBCoreAudioEventDevicesChanged];
    return noErr;
}

static OSStatus DefaultInputProc(AudioObjectID objectID, UInt32 count, const AudioObjectPropertyAddress *addresses, void *context) {
    [(__bridge APBCoreAudioCallbackGate *)context send:APBCoreAudioEventDefaultInputChanged];
    return noErr;
}

static OSStatus DefaultOutputProc(AudioObjectID objectID, UInt32 count, const AudioObjectPropertyAddress *addresses, void *context) {
    [(__bridge APBCoreAudioCallbackGate *)context send:APBCoreAudioEventDefaultOutputChanged];
    return noErr;
}

static OSStatus MuteVolumeProc(AudioObjectID objectID, UInt32 count, const AudioObjectPropertyAddress *addresses, void *context) {
    [(__bridge APBCoreAudioCallbackGate *)context send:APBCoreAudioEventMuteOrVolumeChanged];
    return noErr;
}

@implementation APBCoreAudioObserver {
    APBCoreAudioCallbackGate *_gate;
    APBCoreAudioListenerLifecycle *_listeners;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        __weak typeof(self) weakSelf = self;
        _gate = [[APBCoreAudioCallbackGate alloc] init];
        _gate.handler = ^(APBCoreAudioEvent event) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handle:event];
            });
        };
        // The observer owns the gate and removes every listener before either
        // can be released, so CoreAudio never outlives this unretained context.
        void *context = (__bridge void *)_gate;
        _listeners = [[APBCoreAudioListenerLifecycle alloc]
            initWithAddSystem:^BOOL(APBSystemListener listener) {
                AudioObjectPropertyAddress address = [APBCoreAudioObserver addressForSystem:listener];
                return AudioObjectAddPropertyListener(kAudioObjectSystemObject, &address,
                                                      [APBCoreAudioObserver procForSystem:listener], context) == noErr;
            }
            removeSystem:^(APBSystemListener listener) {
                AudioObjectPropertyAddress address = [APBCoreAudioObserver addressForSystem:listener];
                AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &address,
                                                  [APBCoreAudioObserver procForSystem:listener], context);
            }
            deviceIDs:^NSArray<NSNumber *> *{
                return APBCoreAudioProperties.deviceIDs;
            }
            addDevice:^BOOL(APBDeviceListener *listener) {
                AudioObjectPropertyAddress address = [APBCoreAudioObserver addressForDevice:listener];
                return AudioObjectAddPropertyListener(listener.deviceID, &address, MuteVolumeProc, context) == noErr;
            }
            removeDevice:^(APBDeviceListener *listener) {
                AudioObjectPropertyAddress address = [APBCoreAudioObserver addressForDevice:listener];
                AudioObjectRemovePropertyListener(listener.deviceID, &address, MuteVolumeProc, context);
            }];
    }
    return self;
}

- (void)dealloc {
    [self stopListening];
}

- (BOOL)startListening {
    [_gate setActive:YES];
    BOOL started = [_listeners start];
    if (!started) [_gate setActive:NO];
    return started;
}

- (void)stopListening {
    [_listeners stop];
    [_gate setActive:NO];
}

- (void)handle:(APBCoreAudioEvent)event {
    if (!_listeners.isListening) return;
    switch (event) {
        case APBCoreAudioEventDevicesChanged:
            if (_onDevicesChanged) _onDevicesChanged();
            [_listeners rebuildDeviceListeners];
            break;
        case APBCoreAudioEventDefaultInputChanged:
            if (_onDefaultChanged) _onDefaultChanged(APBDeviceRoleInput);
            break;
        case APBCoreAudioEventDefaultOutputChanged:
            if (_onDefaultChanged) _onDefaultChanged(APBDeviceRoleOutput);
            break;
        case APBCoreAudioEventMuteOrVolumeChanged:
            if (_onMuteOrVolumeChanged) _onMuteOrVolumeChanged();
            break;
    }
}

+ (AudioObjectPropertyAddress)addressForSystem:(APBSystemListener)listener {
    AudioObjectPropertySelector selector = kAudioHardwarePropertyDevices;
    if (listener == APBSystemListenerDefaultInput) selector = kAudioHardwarePropertyDefaultInputDevice;
    if (listener == APBSystemListenerDefaultOutput) selector = kAudioHardwarePropertyDefaultOutputDevice;
    return Property(selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain);
}

+ (AudioObjectPropertyListenerProc)procForSystem:(APBSystemListener)listener {
    switch (listener) {
        case APBSystemListenerDevices: return DevicesProc;
        case APBSystemListenerDefaultInput: return DefaultInputProc;
        case APBSystemListenerDefaultOutput: return DefaultOutputProc;
    }
    return DevicesProc;
}

+ (AudioObjectPropertyAddress)addressForDevice:(APBDeviceListener *)listener {
    switch (listener.kind) {
        case APBDeviceListenerKindMute:
            return Property(kAudioDevicePropertyMute, ScopeForRole(listener.role), listener.element);
        case APBDeviceListenerKindVolume:
            return Property(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput,
                            kAudioObjectPropertyElementMain);
        case APBDeviceListenerKindInputVolume:
            return Property(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput,
                            kAudioObjectPropertyElementMain);
        case APBDeviceListenerKindRunning:
            return Property(kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal,
                            kAudioObjectPropertyElementMain);
    }
}

@end
