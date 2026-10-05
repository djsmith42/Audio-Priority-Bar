#import <Foundation/Foundation.h>
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBHeadphoneDetection : NSObject
+ (BOOL)isHeadphone:(NSString *)name;
/// A product known to be a speaker regardless of what it reports about
/// itself. CoreAudio has no speakerphone terminal type, so a speakerphone may
/// describe itself as headphones, and only the product line settles it.
+ (BOOL)isKnownSpeaker:(NSString *)name;
@end

typedef NS_ENUM(NSInteger, APBURLCommand) {
    APBURLCommandNone,
    APBURLCommandToggleMicMute,
    APBURLCommandMuteMic,
    APBURLCommandUnmuteMic,
};

FOUNDATION_EXPORT NSString *const APBURLCommandScheme;
/// Every command, in the order the Settings window lists them.
FOUNDATION_EXPORT NSArray<NSNumber *> *APBURLCommandAll(void);
FOUNDATION_EXPORT NSString *APBURLCommandRawValue(APBURLCommand command);
/// An `audioprioritybar://` URL, as opened by Shortcuts, Raycast or a Stream
/// Deck. Any app or web page can open one, so only these exact forms are
/// accepted: no path, query, fragment, user or port.
FOUNDATION_EXPORT APBURLCommand APBURLCommandFromURL(NSURL *url);

@interface APBPriorityStore : NSObject

/// Marks a microphone muted through its mute property rather than by zeroing
/// its input volume.
@property (class, nonatomic, readonly) double mutedByProperty;

- (instancetype)init;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                             now:(NSDate *(^_Nullable)(void))now
                    legacyDomain:(nullable NSDictionary<NSString *, id> *)legacyDomain NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSArray<APBStoredDevice *> *knownDevices;
- (void)rememberDevices:(NSArray<APBAudioDevice *> *)devices;
- (nullable APBStoredDevice *)storedDeviceWithUID:(NSString *)uid;
- (nullable APBStoredDevice *)storedDeviceWithUID:(NSString *)uid role:(APBDeviceRole)role;
- (void)forgetUID:(NSString *)uid role:(APBDeviceRole)role;

@property (nonatomic) BOOL isManualMode;
/// Whether choosing one device of a paired pair, a headset's microphone or
/// output, selects the other too.
@property (nonatomic) BOOL selectsPairedDevice;
@property (nonatomic) BOOL hideNewDisplayOutputs;
@property (nonatomic) BOOL showsSwitchNotice;
@property (nonatomic) BOOL remindsWhenMuted;
@property (nonatomic) BOOL outlinesMenuBarIcon;
@property (nonatomic) APBMenuBarDevices menuBarDevices;
@property (nonatomic) BOOL showsMenuBarVolume;

/// Microphones this app muted and has not restored yet, by UID: the input
/// volume to restore, or `mutedByProperty`. Persisted so a crash or an
/// unplugged microphone never leaves one silently muted.
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *appliedMicrophoneMutes;
- (nullable NSNumber *)appliedMicrophoneMuteForUID:(NSString *)uid;
- (void)setAppliedMicrophoneMute:(nullable NSNumber *)level forUID:(NSString *)uid;

- (APBOutputCategory)categoryForDevice:(APBAudioDevice *)device;
- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device;

- (BOOL)isNeverUse:(APBAudioDevice *)device;
- (void)setNeverUse:(APBAudioDevice *)device value:(BOOL)value;

- (BOOL)isHidden:(APBAudioDevice *)device;
- (BOOL)isHidden:(APBAudioDevice *)device inCategory:(APBOutputCategory)category;
- (void)hide:(APBAudioDevice *)device;
- (void)hide:(APBAudioDevice *)device inCategory:(APBOutputCategory)category;
- (void)unhide:(APBAudioDevice *)device;
- (void)unhide:(APBAudioDevice *)device fromCategory:(APBOutputCategory)category;

- (NSArray<APBAudioDevice *> *)sorted:(NSArray<APBAudioDevice *> *)devices role:(APBDeviceRole)role;
- (NSArray<APBAudioDevice *> *)sorted:(NSArray<APBAudioDevice *> *)devices category:(APBOutputCategory)category;
- (void)savePriorities:(NSArray<APBAudioDevice *> *)devices role:(APBDeviceRole)role;
- (void)savePriorities:(NSArray<APBAudioDevice *> *)devices category:(APBOutputCategory)category;

- (nullable APBAudioDevice *)firstSelectableIn:(NSArray<APBAudioDevice *> *)devices
                                      isUsable:(BOOL (^)(APBAudioDevice *device))isUsable;

+ (NSArray<NSString *> *)mergeVisibleOrder:(NSArray<NSString *> *)visible
                                      into:(NSArray<NSString *> *)stored;

@end

NS_ASSUME_NONNULL_END
