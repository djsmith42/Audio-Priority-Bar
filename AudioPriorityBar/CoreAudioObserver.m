#import "CoreAudioObserver.h"
#import <AudioToolbox/AudioToolbox.h>
#import "CoreAudioListeners.h"
#import "CoreAudioProperties.h"

static APBCoreAudioCallbackGate *Gate(void *context) {
    return (__bridge APBCoreAudioCallbackGate *)context;
}

static OSStatus DevicesProc(AudioObjectID objectID, UInt32 count,
                            const AudioObjectPropertyAddress *addresses, void *context) {
    [Gate(context) send:APBCoreAudioEventDevicesChanged role:APBDeviceRoleOutput];
    return noErr;
}

static OSStatus DefaultInputProc(AudioObjectID objectID, UInt32 count,
                                 const AudioObjectPropertyAddress *addresses, void *context) {
    [Gate(context) send:APBCoreAudioEventDefaultChanged role:APBDeviceRoleInput];
    return noErr;
}

static OSStatus DefaultOutputProc(AudioObjectID objectID, UInt32 count,
                                  const AudioObjectPropertyAddress *addresses, void *context) {
    [Gate(context) send:APBCoreAudioEventDefaultChanged role:APBDeviceRoleOutput];
    return noErr;
}

static OSStatus MuteVolumeProc(AudioObjectID objectID, UInt32 count,
                               const AudioObjectPropertyAddress *addresses, void *context) {
    [Gate(context) send:APBCoreAudioEventMuteOrVolumeChanged role:APBDeviceRoleOutput];
    return noErr;
}

@implementation APBCoreAudioObserver {
    APBCoreAudioCallbackGate *_callbackGate;
    APBCoreAudioListenerLifecycle *_listeners;
}

- (instancetype)init {
    if ((self = [super init])) {
        __weak typeof(self) weakSelf = self;
        _callbackGate = [[APBCoreAudioCallbackGate alloc] initWithHandler:^(APBCoreAudioEventKind kind, APBDeviceRole role) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf handle:kind role:role];
            });
        }];
        _listeners = [[APBCoreAudioListenerLifecycle alloc]
            initWithAddSystem:^BOOL(APBSystemListener listener) {
                return [weakSelf addSystemListener:listener];
            }
            removeSystem:^(APBSystemListener listener) {
                [weakSelf removeSystemListener:listener];
            }
            deviceIDs:^NSArray<NSNumber *> *{
                return APBCoreAudioProperties.deviceIDs;
            }
            addDevice:^BOOL(APBDeviceListener *listener) {
                return [weakSelf addDeviceListener:listener];
            }
            removeDevice:^(APBDeviceListener *listener) {
                [weakSelf removeDeviceListener:listener];
            }];
    }
    return self;
}

- (BOOL)startListening {
    [_callbackGate setActive:YES];
    BOOL started = [_listeners start];
    if (!started) [_callbackGate setActive:NO];
    return started;
}

- (void)stopListening {
    [_listeners stop];
    [_callbackGate setActive:NO];
}

- (void)handle:(APBCoreAudioEventKind)kind role:(APBDeviceRole)role {
    if (!_listeners.isListening) return;
    switch (kind) {
        case APBCoreAudioEventDevicesChanged:
            if (_onDevicesChanged) _onDevicesChanged();
            [_listeners rebuildDeviceListeners];
            break;
        case APBCoreAudioEventDefaultChanged:
            if (_onDefaultChanged) _onDefaultChanged(role);
            break;
        case APBCoreAudioEventMuteOrVolumeChanged:
            if (_onMuteOrVolumeChanged) _onMuteOrVolumeChanged();
            break;
    }
}

// The observer owns the gate and removes every listener before either can be
// released, so CoreAudio never outlives this unretained callback context.
- (void *)callbackContext {
    return (__bridge void *)_callbackGate;
}

- (AudioObjectPropertyAddress)systemAddress:(APBSystemListener)listener {
    AudioObjectPropertySelector selector = kAudioHardwarePropertyDevices;
    switch (listener) {
        case APBSystemListenerDevices: selector = kAudioHardwarePropertyDevices; break;
        case APBSystemListenerDefaultInput: selector = kAudioHardwarePropertyDefaultInputDevice; break;
        case APBSystemListenerDefaultOutput: selector = kAudioHardwarePropertyDefaultOutputDevice; break;
    }
    return (AudioObjectPropertyAddress){selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
}

- (AudioObjectPropertyListenerProc)systemProc:(APBSystemListener)listener {
    switch (listener) {
        case APBSystemListenerDevices: return DevicesProc;
        case APBSystemListenerDefaultInput: return DefaultInputProc;
        case APBSystemListenerDefaultOutput: return DefaultOutputProc;
    }
    return DevicesProc;
}

- (BOOL)addSystemListener:(APBSystemListener)listener {
    AudioObjectPropertyAddress address = [self systemAddress:listener];
    return AudioObjectAddPropertyListener(kAudioObjectSystemObject, &address,
                                          [self systemProc:listener], self.callbackContext) == noErr;
}

- (void)removeSystemListener:(APBSystemListener)listener {
    AudioObjectPropertyAddress address = [self systemAddress:listener];
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &address,
                                      [self systemProc:listener], self.callbackContext);
}

- (AudioObjectPropertyAddress)deviceAddress:(APBDeviceListener *)listener {
    switch (listener.kind) {
        case APBDeviceListenerKindMute:
            return (AudioObjectPropertyAddress){
                kAudioDevicePropertyMute,
                listener.role == APBDeviceRoleInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
                listener.element,
            };
        case APBDeviceListenerKindVolume:
            return (AudioObjectPropertyAddress){
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioDevicePropertyScopeOutput,
                kAudioObjectPropertyElementMain,
            };
        case APBDeviceListenerKindInputVolume:
            return (AudioObjectPropertyAddress){
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioDevicePropertyScopeInput,
                kAudioObjectPropertyElementMain,
            };
        case APBDeviceListenerKindRunning:
            return (AudioObjectPropertyAddress){
                kAudioDevicePropertyDeviceIsRunningSomewhere,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain,
            };
    }
}

- (BOOL)addDeviceListener:(APBDeviceListener *)listener {
    AudioObjectPropertyAddress address = [self deviceAddress:listener];
    return AudioObjectAddPropertyListener(listener.deviceID, &address, MuteVolumeProc, self.callbackContext) == noErr;
}

- (void)removeDeviceListener:(APBDeviceListener *)listener {
    AudioObjectPropertyAddress address = [self deviceAddress:listener];
    AudioObjectRemovePropertyListener(listener.deviceID, &address, MuteVolumeProc, self.callbackContext);
}

@end
