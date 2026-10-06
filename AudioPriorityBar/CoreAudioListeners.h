#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, APBSystemListener) {
    APBSystemListenerDevices,
    APBSystemListenerDefaultInput,
    APBSystemListenerDefaultOutput,
};

typedef NS_ENUM(NSInteger, APBDeviceListenerKind) {
    APBDeviceListenerKindMute,
    APBDeviceListenerKindVolume,
    APBDeviceListenerKindInputVolume,
    APBDeviceListenerKindRunning,
};

/// One per-device property listener. Compared by value.
@interface APBDeviceListener : NSObject <NSCopying>

@property (nonatomic, readonly) APBDeviceListenerKind kind;
@property (nonatomic, readonly) AudioObjectID deviceID;
/// Mute listeners only.
@property (nonatomic, readonly) APBDeviceRole role;
/// Mute listeners only.
@property (nonatomic, readonly) AudioObjectPropertyElement element;

+ (instancetype)muteWithID:(AudioObjectID)deviceID role:(APBDeviceRole)role element:(AudioObjectPropertyElement)element;
+ (instancetype)volumeWithID:(AudioObjectID)deviceID;
+ (instancetype)inputVolumeWithID:(AudioObjectID)deviceID;
+ (instancetype)runningWithID:(AudioObjectID)deviceID;

@end

/// Registers and unregisters CoreAudio listeners through injected blocks, so
/// the bookkeeping can be tested without hardware.
@interface APBCoreAudioListenerLifecycle : NSObject

@property (nonatomic, readonly) BOOL isListening;

- (instancetype)initWithAddSystem:(BOOL (^)(APBSystemListener listener))addSystem
                     removeSystem:(void (^)(APBSystemListener listener))removeSystem
                        deviceIDs:(NSArray<NSNumber *> *(^)(void))deviceIDs
                        addDevice:(BOOL (^)(APBDeviceListener *listener))addDevice
                     removeDevice:(void (^)(APBDeviceListener *listener))removeDevice NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)start;
- (void)rebuildDeviceListeners;
- (void)stop;

@end

typedef NS_ENUM(NSInteger, APBCoreAudioEventKind) {
    APBCoreAudioEventDevicesChanged,
    APBCoreAudioEventDefaultChanged,
    APBCoreAudioEventMuteOrVolumeChanged,
};

/// Lets CoreAudio's callback threads reach the observer only while it is
/// listening.
@interface APBCoreAudioCallbackGate : NSObject

/// `role` applies to `APBCoreAudioEventDefaultChanged` only.
- (instancetype)initWithHandler:(void (^)(APBCoreAudioEventKind kind, APBDeviceRole role))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setActive:(BOOL)active;
- (void)send:(APBCoreAudioEventKind)kind role:(APBDeviceRole)role;

@end

NS_ASSUME_NONNULL_END
