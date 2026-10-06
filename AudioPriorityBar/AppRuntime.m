#import "AppRuntime.h"
#import <AppKit/AppKit.h>
#import "CoreAudioObserver.h"
#import "CoreAudioProperties.h"
#import "JabraHIDMonitor.h"
#import "KeyboardShortcuts.h"

@implementation APBSystemSoundPicker

+ (BOOL)isInUse {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    NSMutableSet<NSNumber *> *pids = [NSMutableSet set];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.controlcenter"]) {
        [pids addObject:@(app.processIdentifier)];
    }
    return [self isInUseWithWindows:windows ?: @[]
                  controlCenterPIDs:pids
                  frontmostBundleID:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
}

+ (BOOL)isInUseWithWindows:(NSArray<NSDictionary<NSString *, id> *> *)windows
         controlCenterPIDs:(NSSet<NSNumber *> *)controlCenterPIDs
         frontmostBundleID:(NSString *)frontmostBundleID {
    if ([frontmostBundleID isEqualToString:@"com.apple.systempreferences"]) return YES;
    NSInteger menuBarLayer = CGWindowLevelForKey(kCGStatusWindowLevelKey);
    for (NSDictionary *window in windows) {
        id pid = window[(__bridge NSString *)kCGWindowOwnerPID];
        id layer = window[(__bridge NSString *)kCGWindowLayer];
        BOOL isControlCenter = [pid isKindOfClass:NSNumber.class] && [controlCenterPIDs containsObject:@([pid intValue])];
        BOOL isMenuBarLayer = [layer isKindOfClass:NSNumber.class] && [layer integerValue] == menuBarLayer;
        if (isControlCenter && !isMenuBarLayer) return YES;
    }
    return NO;
}

@end

@implementation APBAppRuntime {
    APBCoreAudioObserver *_audioObserver;
    APBJabraHIDMonitor *_jabra;
}

- (instancetype)init {
    if ((self = [super init])) {
        _audioObserver = [[APBCoreAudioObserver alloc] init];
        APBJabraHIDMonitor *jabra = [[APBJabraHIDMonitor alloc] init];
        _jabra = jabra;

        APBAudioOperations *audio = [[APBAudioOperations alloc] init];
        audio.devices = ^{ return APBCoreAudioProperties.devices; };
        audio.defaultDevice = ^NSNumber *(APBDeviceRole role) {
            AudioObjectID deviceID = [APBCoreAudioProperties defaultDevice:role];
            return deviceID ? @(deviceID) : nil;
        };
        audio.setDefault = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
            return [APBCoreAudioProperties setDefault:deviceID role:role];
        };
        audio.outputVolume = ^{ return APBCoreAudioProperties.outputVolume; };
        audio.setOutputVolume = ^BOOL(float value) { return [APBCoreAudioProperties setOutputVolume:value]; };
        audio.isMuted = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
            return [APBCoreAudioProperties isMuted:deviceID role:role];
        };
        audio.setMute = ^BOOL(APBDeviceRole role, UInt32 deviceID, BOOL muted) {
            return [APBCoreAudioProperties setMute:deviceID role:role muted:muted];
        };
        audio.canSetMute = ^BOOL(APBDeviceRole role, UInt32 deviceID) {
            return [APBCoreAudioProperties canSetMute:deviceID role:role];
        };
        audio.inputVolume = ^NSNumber *(UInt32 deviceID) { return [APBCoreAudioProperties inputVolume:deviceID]; };
        audio.setInputVolume = ^BOOL(UInt32 deviceID, float value) {
            return [APBCoreAudioProperties setInputVolume:deviceID value:value];
        };
        audio.isRunning = ^BOOL(UInt32 deviceID) { return [APBCoreAudioProperties isRunningSomewhere:deviceID]; };

        __weak APBJabraHIDMonitor *weakJabra = jabra;
        APBLinkOperations *link = [[APBLinkOperations alloc]
            initWithIsUsable:^BOOL(APBAudioDevice *device) {
                return device.isConnected && [weakJabra isUsable:device];
            }
            state:^APBLinkState(APBAudioDevice *device) {
                return [weakJabra monitoredStateForDevice:device];
            }];
        link.battery = ^NSNumber *(APBAudioDevice *device) { return [weakJabra batteryLevelForDevice:device]; };

        _model = [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] init]
                                              audio:audio
                                               link:link
                                            battery:[[APBBluetoothBatteryMonitor alloc] init]
                                       reduceMotion:nil
                                      isUserPicking:^BOOL { return APBSystemSoundPicker.isInUse; }];
        __weak APBAppModel *weakModel = _model;
        _updates = [[APBUpdateChecker alloc] initWithIsIdle:^BOOL {
            APBAppModel *model = weakModel;
            return model ? !model.isMicrophoneMuted && !model.isInputRecording : YES;
        }];

        _audioObserver.onDevicesChanged = ^{ [weakModel handleDevicesChanged]; };
        _audioObserver.onDefaultChanged = ^(APBDeviceRole role) { [weakModel handleDefaultChanged:role]; };
        _audioObserver.onMuteOrVolumeChanged = ^{ [weakModel handleMuteOrVolumeChanged]; };
        jabra.onLinkChange = ^{ [weakModel handleLinkChanged]; };
        jabra.onBatteryChange = ^{ [weakModel handleBatteryChanged]; };
    }
    return self;
}

- (BOOL)start {
    [_jabra start];
    BOOL isListening = [_audioObserver startListening];
    [_model start];
    [_updates start];
    // Starts as Option-Shift-M, which no call app uses for its own mute.
    [APBKeyboardShortcuts setInitialShortcut:APBShortcut.optionShiftM forName:APBToggleMicrophoneMuteShortcut];
    __weak APBAppModel *weakModel = _model;
    [APBKeyboardShortcuts onKeyUpForName:APBToggleMicrophoneMuteShortcut handler:^{
        [weakModel perform:APBURLCommandToggleMicMute];
    }];
    return isListening;
}

- (void)stop {
    // Producers first: once they are down, no callback, timeout or debounce
    // can reach the model and restart work it just tore down.
    [_jabra stop];
    [_audioObserver stopListening];
    [_model stop];
}

@end
