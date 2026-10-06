#import "CoreAudioProperties.h"
#import <AudioToolbox/AudioToolbox.h>

static const AudioObjectID SystemObject = kAudioObjectSystemObject;

static AudioObjectPropertyAddress Property(AudioObjectPropertySelector selector,
                                          AudioObjectPropertyScope scope,
                                          AudioObjectPropertyElement element) {
    return (AudioObjectPropertyAddress){selector, scope, element};
}

static AudioObjectPropertyAddress GlobalProperty(AudioObjectPropertySelector selector) {
    return Property(selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain);
}

static OSStatus Read(AudioObjectID objectID, AudioObjectPropertySelector selector,
                     AudioObjectPropertyScope scope, AudioObjectPropertyElement element,
                     void *value, UInt32 size) {
    AudioObjectPropertyAddress address = Property(selector, scope, element);
    return AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, value);
}

static OSStatus Write(AudioObjectID objectID, AudioObjectPropertySelector selector,
                      AudioObjectPropertyScope scope, AudioObjectPropertyElement element,
                      const void *value, UInt32 size) {
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

static NSArray<NSNumber *> *ObjectList(AudioObjectID objectID, AudioObjectPropertyAddress address) {
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(objectID, &address, 0, NULL, &size) != noErr || size == 0) {
        return @[];
    }
    NSMutableData *buffer = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, buffer.mutableBytes) != noErr) {
        return @[];
    }
    const AudioObjectID *ids = buffer.bytes;
    NSUInteger count = size / sizeof(AudioObjectID);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) [result addObject:@(ids[index])];
    return result;
}

static NSString *StringProperty(AudioObjectID objectID, AudioObjectPropertySelector selector) {
    CFStringRef value = NULL;
    if (Read(objectID, selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain,
             &value, sizeof value) != noErr || !value) {
        return nil;
    }
    return CFBridgingRelease(value);
}

@implementation APBCoreAudioProperties

+ (NSArray<APBAudioDevice *> *)devices {
    NSMutableArray *devices = [NSMutableArray array];
    for (NSNumber *deviceID in self.deviceIDs) {
        for (NSNumber *role in @[@(APBDeviceRoleInput), @(APBDeviceRoleOutput)]) {
            APBAudioDevice *device = [self makeDevice:deviceID.unsignedIntValue role:role.integerValue];
            if (device) [devices addObject:device];
        }
    }
    return devices;
}

+ (NSArray<NSNumber *> *)deviceIDs {
    return ObjectList(SystemObject, GlobalProperty(kAudioHardwarePropertyDevices));
}

+ (AudioObjectID)defaultDevice:(APBDeviceRole)role {
    AudioObjectID deviceID = 0;
    if (Read(SystemObject, DefaultSelector(role), kAudioObjectPropertyScopeGlobal,
             kAudioObjectPropertyElementMain, &deviceID, sizeof deviceID) != noErr
        || deviceID == kAudioObjectUnknown) {
        return 0;
    }
    return deviceID;
}

+ (BOOL)setDefault:(AudioObjectID)deviceID role:(APBDeviceRole)role {
    return Write(SystemObject, DefaultSelector(role), kAudioObjectPropertyScopeGlobal,
                 kAudioObjectPropertyElementMain, &deviceID, sizeof deviceID) == noErr;
}

+ (NSNumber *)outputVolume {
    AudioObjectID deviceID = [self defaultDevice:APBDeviceRoleOutput];
    if (!deviceID) return nil;
    Float32 volume = 0;
    OSStatus status = Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                           kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain,
                           &volume, sizeof volume);
    return status == noErr ? @(volume) : nil;
}

+ (BOOL)setOutputVolume:(float)value {
    AudioObjectID deviceID = [self defaultDevice:APBDeviceRoleOutput];
    if (!deviceID) return NO;
    Float32 volume = value;
    return Write(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                 kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain,
                 &volume, sizeof volume) == noErr;
}

+ (float)deviceVolume:(AudioObjectID)deviceID {
    Float32 volume = 0;
    OSStatus status = Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                           kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain,
                           &volume, sizeof volume);
    return status == noErr ? volume : 1;
}

+ (BOOL)isMuted:(AudioObjectID)deviceID role:(APBDeviceRole)role {
    AudioObjectPropertyScope scope = ScopeForRole(role);
    UInt32 muted = 0;
    if (Read(deviceID, kAudioDevicePropertyMute, scope, kAudioObjectPropertyElementMain,
             &muted, sizeof muted) == noErr && muted != 0) {
        return YES;
    }
    muted = 0;
    if (Read(deviceID, kAudioDevicePropertyMute, scope, 1, &muted, sizeof muted) == noErr
        && muted != 0) {
        return YES;
    }
    return role == APBDeviceRoleOutput && [self deviceVolume:deviceID] < 0.01;
}

+ (BOOL)setMute:(AudioObjectID)deviceID role:(APBDeviceRole)role muted:(BOOL)muted {
    AudioObjectPropertyScope scope = ScopeForRole(role);
    UInt32 value = muted ? 1 : 0;
    for (AudioObjectPropertyElement element = kAudioObjectPropertyElementMain; element <= 1; element++) {
        if (Write(deviceID, kAudioDevicePropertyMute, scope, element, &value, sizeof value) == noErr) {
            return YES;
        }
    }
    return NO;
}

+ (NSNumber *)inputVolume:(AudioObjectID)deviceID {
    Float32 volume = 0;
    OSStatus status = Read(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                           kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain,
                           &volume, sizeof volume);
    return status == noErr ? @(volume) : nil;
}

+ (BOOL)setInputVolume:(AudioObjectID)deviceID value:(float)value {
    Float32 volume = value;
    return Write(deviceID, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                 kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain,
                 &volume, sizeof volume) == noErr;
}

+ (BOOL)canSetMute:(AudioObjectID)deviceID role:(APBDeviceRole)role {
    for (AudioObjectPropertyElement element = kAudioObjectPropertyElementMain; element <= 1; element++) {
        AudioObjectPropertyAddress address = Property(kAudioDevicePropertyMute, ScopeForRole(role), element);
        Boolean settable = false;
        if (AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isRunningSomewhere:(AudioObjectID)deviceID {
    UInt32 running = 0;
    return Read(deviceID, kAudioDevicePropertyDeviceIsRunningSomewhere,
                kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain,
                &running, sizeof running) == noErr && running != 0;
}

+ (APBAudioDevice *)makeDevice:(AudioObjectID)deviceID role:(APBDeviceRole)role {
    NSArray<NSNumber *> *streams = ObjectList(deviceID, Property(kAudioDevicePropertyStreams,
                                                                 ScopeForRole(role),
                                                                 kAudioObjectPropertyElementMain));
    if (streams.count == 0) return nil;
    NSString *name = StringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);
    NSString *uid = StringProperty(deviceID, kAudioDevicePropertyDeviceUID);
    if (!name || !uid) return nil;
    UInt32 transport = [self transport:deviceID];
    BOOL isOutput = role == APBDeviceRoleOutput;
    return [[APBAudioDevice alloc] initWithPlatformID:deviceID
                                                  uid:uid
                                                 name:name
                                                 role:role
                                          isConnected:YES
                                            isVirtual:[self isVirtualTransport:transport]
                                     // Input terminals describe a microphone,
                                     // which says nothing about where output
                                     // should go.
                                     declaredCategory:isOutput
                                                      ? [self declaredCategoryForStreams:streams transport:transport]
                                                      : APBOutputCategoryNone
                                      isDisplayOutput:isOutput && [self isDisplayTransport:transport]
                                        transportType:transport];
}

/// The category a device claims for itself, or none when it claims nothing
/// usable. Aggregate devices report `Unknown` and HDMI reports its own
/// terminal, so the caller still needs a fallback.
+ (APBOutputCategory)declaredCategoryForStreams:(NSArray<NSNumber *> *)streams transport:(UInt32)transport {
    NSMutableArray<NSNumber *> *terminals = [NSMutableArray array];
    for (NSNumber *stream in streams) {
        UInt32 terminal = 0;
        // AudioStream has only a global scope.
        if (Read(stream.unsignedIntValue, kAudioStreamPropertyTerminalType,
                 kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain,
                 &terminal, sizeof terminal) == noErr) {
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
    NSMutableSet<NSNumber *> *declared = [NSMutableSet set];
    for (NSNumber *terminal in terminals) {
        APBOutputCategory category = [self categoryForTerminal:terminal.unsignedIntValue];
        if (category != APBOutputCategoryNone) [declared addObject:@(category)];
    }
    return declared.count == 1 ? declared.anyObject.integerValue : APBOutputCategoryNone;
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

/// CoreAudio reports software devices as virtual or aggregate transports,
/// which separates Krisp and Multi-Output from real hardware without
/// matching on names.
+ (BOOL)isVirtualTransport:(UInt32)transport {
    return transport == kAudioDeviceTransportTypeVirtual
        || transport == kAudioDeviceTransportTypeAggregate;
}

+ (BOOL)isDisplayTransport:(UInt32)transport {
    return transport == kAudioDeviceTransportTypeHDMI
        || transport == kAudioDeviceTransportTypeDisplayPort;
}

@end
