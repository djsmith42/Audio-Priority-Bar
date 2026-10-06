#import <Foundation/Foundation.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBPriorityStore : NSObject

/// Marks a microphone muted through its mute property rather than by
/// zeroing its input volume.
@property (class, nonatomic, readonly) double mutedByProperty;

/// `legacyDomain` stands in for the pre-rename bundle's settings; when it is
/// nil the standard defaults read them from disk.
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                             now:(NSDate *(^_Nullable)(void))now
                    legacyDomain:(nullable NSDictionary<NSString *, id> *)legacyDomain NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
/// The standard defaults.
- (instancetype)init;

@property (nonatomic, readonly) NSArray<APBStoredDevice *> *knownDevices;
- (void)remember:(NSArray<APBAudioDevice *> *)devices;
/// `role` of nil matches either role.
- (nullable APBStoredDevice *)storedDeviceWithUID:(NSString *)uid role:(nullable NSNumber *)role;
- (void)forgetUID:(NSString *)uid role:(APBDeviceRole)role;

@property (nonatomic) BOOL isManualMode;
/// Whether choosing one device of a paired pair, a headset's microphone
/// or output, selects the other too.
@property (nonatomic) BOOL selectsPairedDevice;
@property (nonatomic) BOOL hideNewDisplayOutputs;
@property (nonatomic) BOOL showsSwitchNotice;
@property (nonatomic) BOOL remindsWhenMuted;
@property (nonatomic) BOOL mutesSpeakersWhenHeadphonesDisconnect;
@property (nonatomic) BOOL outlinesMenuBarIcon;
@property (nonatomic) APBMenuBarDevices menuBarDevices;
@property (nonatomic) BOOL showsMenuBarVolume;

/// Microphones this app muted and has not restored yet, by UID: the input
/// volume to restore, or `mutedByProperty`. Persisted so a crash or an
/// unplugged microphone never leaves one silently muted.
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *appliedMicrophoneMutes;
/// Sets or, with nil, removes one entry of `appliedMicrophoneMutes`.
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
