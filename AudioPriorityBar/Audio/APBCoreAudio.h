#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

/// What the model needs from the audio system. Replaced by a fake in tests.
@protocol APBAudioOperations <NSObject>
- (NSArray<APBAudioDevice *> *)devices;
/// Zero when there is none.
- (UInt32)defaultDeviceForRole:(APBDeviceRole)role;
- (BOOL)setDefaultDevice:(UInt32)deviceID role:(APBDeviceRole)role;
/// Nil when the current output has no volume.
- (nullable NSNumber *)outputVolume;
- (BOOL)setOutputVolume:(float)value;
- (BOOL)isMuted:(UInt32)deviceID role:(APBDeviceRole)role;
- (BOOL)setMute:(UInt32)deviceID role:(APBDeviceRole)role muted:(BOOL)muted;
- (BOOL)canSetMute:(UInt32)deviceID role:(APBDeviceRole)role;
/// Nil when the device has no input volume.
- (nullable NSNumber *)inputVolume:(UInt32)deviceID;
- (BOOL)setInputVolume:(UInt32)deviceID value:(float)value;
- (BOOL)isRunning:(UInt32)deviceID;
@end

/// The real audio system.
@interface APBCoreAudioProperties : NSObject <APBAudioOperations>

+ (NSArray<NSNumber *> *)deviceIDs;

/// macOS gives a Bluetooth output a headphones terminal even when it is a
/// speaker, such as an Echo, so from Bluetooth that claim is no evidence.
+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals transport:(UInt32)transport;
/// Resolves what a device's streams collectively claim. Streams that disagree
/// are no evidence at all, since preferring one by position would only make
/// stream order look meaningful.
+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals;
/// Maps an audio terminal to a category.
///
/// Two value spaces appear in practice. USB and Bluetooth devices arrive
/// translated into the CoreAudio constants, while built-in devices report the
/// raw code from the USB Audio Terminal Types specification, so both are
/// accepted. Anything unrecognised, including `Unknown`, line level and
/// digital interfaces, declares nothing.
+ (APBOutputCategory)categoryForTerminal:(UInt32)terminal;
/// Sound reaching a monitor or TV over the video cable. The transport says so
/// outright, which a product name cannot: both of the attached Dell panels
/// report HDMI, including the one behind a USB-C hub.
+ (BOOL)isDisplayTransport:(UInt32)transport;

@end

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

@interface APBDeviceListener : NSObject <NSCopying>
@property (nonatomic, readonly) APBDeviceListenerKind kind;
@property (nonatomic, readonly) AudioObjectID deviceID;
/// For a mute listener.
@property (nonatomic, readonly) APBDeviceRole role;
@property (nonatomic, readonly) AudioObjectPropertyElement element;
+ (instancetype)muteWithID:(AudioObjectID)deviceID role:(APBDeviceRole)role element:(AudioObjectPropertyElement)element;
+ (instancetype)listenerWithKind:(APBDeviceListenerKind)kind deviceID:(AudioObjectID)deviceID;
@end

/// Which CoreAudio listeners are installed. Kept apart from CoreAudio so the
/// ordering and rollback can be tested.
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

/// Forwards CoreAudio's callbacks to the main thread while active.
@interface APBCoreAudioObserver : NSObject

@property (nonatomic, copy, nullable) void (^onDevicesChanged)(void);
@property (nonatomic, copy, nullable) void (^onDefaultChanged)(APBDeviceRole role);
@property (nonatomic, copy, nullable) void (^onMuteOrVolumeChanged)(void);

- (BOOL)startListening;
- (void)stopListening;

@end

NS_ASSUME_NONNULL_END
