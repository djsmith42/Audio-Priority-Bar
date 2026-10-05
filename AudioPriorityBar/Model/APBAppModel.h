#import <Foundation/Foundation.h>
#import "APBBluetoothBattery.h"
#import "APBCoreAudio.h"
#import "APBModels.h"
#import "APBPriorityStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted once per run loop turn after anything the views show has changed.
FOUNDATION_EXPORT NSNotificationName const APBAppModelDidChangeNotification;

typedef BOOL (^APBLinkUsable)(APBAudioDevice *device);
/// `None` when the device is not monitored.
typedef APBLinkState (^APBLinkStateProvider)(APBAudioDevice *device);

typedef NS_ENUM(NSInteger, APBOutputSkipReason) {
    APBOutputSkipReasonOff,
    APBOutputSkipReasonNeverAutoSelect,
};

@interface APBSkippedOutput : NSObject
@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) APBOutputSkipReason reason;
@end

@interface APBAutomaticOutputDecision : NSObject
@property (nonatomic, readonly, nullable) APBAudioDevice *target;
@property (nonatomic, readonly, nullable) APBSkippedOutput *skipped;
/// A candidate is still being checked, so no choice should be applied yet.
@property (nonatomic, readonly) BOOL isDeferred;
@end

@interface APBAppModel : NSObject

@property (nonatomic, readonly, copy) NSArray<APBAudioDevice *> *inputDevices;
@property (nonatomic, readonly, copy) NSArray<APBAudioDevice *> *speakerDevices;
@property (nonatomic, readonly, copy) NSArray<APBAudioDevice *> *headphoneDevices;
@property (nonatomic, readonly, copy) NSArray<APBAudioDevice *> *hiddenSpeakerDevices;
@property (nonatomic, readonly, copy) NSArray<APBAudioDevice *> *hiddenHeadphoneDevices;
/// Zero when there is none.
@property (nonatomic, readonly) UInt32 currentInputID;
@property (nonatomic, readonly) UInt32 currentOutputID;
@property (nonatomic, readonly) float volume;
@property (nonatomic, readonly) BOOL isVolumeControllable;
/// The current output has a settable mute property. Some, like TVs and audio
/// interfaces, have neither a volume nor a mute.
@property (nonatomic, readonly) BOOL isOutputMutable;
/// The current microphone's input level. While it is muted by zeroing, this
/// is the level unmuting will restore rather than zero.
@property (nonatomic, readonly) float microphoneLevel;
@property (nonatomic, readonly) BOOL isMicrophoneLevelControllable;
/// The current microphone can be muted, by its mute property or by zeroing
/// its level.
@property (nonatomic, readonly) BOOL isMicrophoneMutable;
@property (nonatomic) BOOL showAll;
@property (nonatomic, readonly) BOOL isManualMode;
@property (nonatomic, readonly) BOOL selectsPairedDevice;
@property (nonatomic, readonly) BOOL hideNewDisplayOutputs;
@property (nonatomic, readonly) BOOL isActiveOutputMuted;
@property (nonatomic, readonly) BOOL isActiveInputMuted;
@property (nonatomic, readonly) BOOL micFlashState;
/// The microphone mute the user asked for, carried to whichever microphone is
/// current.
@property (nonatomic, readonly) BOOL isMicrophoneMuted;
/// Some app is recording from the current microphone.
@property (nonatomic, readonly) BOOL isInputRecording;
@property (nonatomic, readonly) BOOL showsSwitchNotice;
@property (nonatomic, readonly) BOOL remindsWhenMuted;
@property (nonatomic, readonly) BOOL outlinesMenuBarIcon;
@property (nonatomic, readonly) APBMenuBarDevices menuBarDevices;
@property (nonatomic, readonly) BOOL showsMenuBarVolume;
/// Called with the devices Automatic mode just switched to because the
/// hardware changed, output first. Never for the user's own choices.
@property (nonatomic, copy, nullable) void (^onAutomaticSwitch)(NSArray<APBAudioDevice *> *devices);

@property (nonatomic, readonly) APBPriorityStore *store;
@property (nonatomic, readonly) id<APBAudioOperations> audio;
@property (nonatomic, readonly) APBBluetoothBatteryMonitor *battery;

/// Keeps "Output only" intact when CoreAudio echoes our own default change.
/// Held by UID because platform IDs are recycled across devices.
@property (nonatomic, copy, nullable) NSString *selectedOnlyOutputUID;
/// Devices picked in Control Center or Sound Settings, or that macOS keeps
/// switching to, by role and UID. Automatic mode keeps them until a device
/// connects or disconnects.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSString *> *keptPicks;
/// When the app last switched each role back after macOS or another app moved
/// it.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSNumber *> *switchedBackAt;
/// The device macOS moved each role to again soon after a switch back, by
/// UID. The app leaves it there and names it in the panel.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSString *> *takeoverUIDs;

- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(id<APBAudioOperations>)audio
                     isUsable:(APBLinkUsable)isUsable
                    linkState:(APBLinkStateProvider)linkState
                      battery:(nullable APBBluetoothBatteryMonitor *)battery
                 reduceMotion:(nullable BOOL (^)(void))reduceMotion
                isUserPicking:(nullable BOOL (^)(void))isUserPicking NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

- (void)handleDevicesChanged;
/// The Jabra monitor reached a new verdict for some dongle.
- (void)handleLinkChanged;
- (void)handleDefaultChanged:(APBDeviceRole)role;
- (void)handleMuteOrVolumeChanged;

- (void)refreshDevices;
- (void)refreshVolume;
- (void)refreshMute;

/// The device macOS keeps switching to, while it is still current, output
/// first.
@property (nonatomic, readonly, nullable) APBAudioDevice *takeoverDevice;
@property (nonatomic, readonly, nullable) APBAudioDevice *currentInputDevice;
@property (nonatomic, readonly, nullable) APBAudioDevice *currentOutputDevice;
/// `None` when no output is current.
@property (nonatomic, readonly) APBOutputCategory activeOutputCategory;
/// Audio is routed to a device we know cannot play it. Automatic switching
/// moves away on its own, so this only persists in manual mode or when there
/// is nothing better to fall back to.
@property (nonatomic, readonly) BOOL isActiveOutputLinkDown;
@property (nonatomic, readonly) APBAutomaticOutputDecision *automaticOutputDecision;

- (BOOL)isMuted:(APBAudioDevice *)device;
/// AirPods battery levels, read again when devices come or go and whenever
/// the panel opens.
- (nullable APBBatteryLevels *)batteryLevelsForDevice:(APBAudioDevice *)device;
/// `None` for a disconnected or unmonitored device.
- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device;
- (BOOL)isLinkUsable:(APBAudioDevice *)device;

- (void)applyHighestPriorityDevices;
- (void)applyHighestPriorityInput;
- (void)applyHighestPriorityOutput;

- (BOOL)select:(APBAudioDevice *)device;
- (BOOL)select:(APBAudioDevice *)device automatically:(BOOL)automatically includesPairedDevice:(BOOL)includesPairedDevice;
/// Selects the paired counterpart of `device`, when `selectsPairedDevice`
/// covers both. Reaching from a microphone to its output only happens on a
/// direct pick (`automatically == NO`): automatic mode already anchors
/// microphone selection to the current output, so letting a priority-ranked
/// microphone reach back here would fight that output's own decision. The
/// already-current guard is what stops an output-to-mic-to-output cycle.
- (void)selectPairedDeviceOf:(APBAudioDevice *)device automatically:(BOOL)automatically;
/// The connected counterpart of `device` that shares its physical identity
/// (`pairingKey`), if any: the input half for an output, or the output half
/// for an input. Not gated by `selectsPairedDevice`, which only governs the
/// automatic selection in `selectPairedDeviceOf:`; the explicit
/// `selectWithPairedDevice:`/`selectOnly:` actions use this directly.
- (nullable APBAudioDevice *)pairedDeviceFor:(APBAudioDevice *)device;

#pragma mark Actions

- (void)setManualMode:(BOOL)enabled;
- (void)setSelectsPairedDevice:(BOOL)enabled;
- (void)setHideNewDisplayOutputs:(BOOL)enabled;
- (void)setShowsSwitchNotice:(BOOL)enabled;
- (void)setRemindsWhenMuted:(BOOL)enabled;
- (void)setOutlinesMenuBarIcon:(BOOL)enabled;
- (void)setMenuBarDevices:(APBMenuBarDevices)devices;
- (void)setShowsMenuBarVolume:(BOOL)enabled;
- (void)setMicrophoneMuted:(BOOL)muted;
- (void)performCommand:(APBURLCommand)command;
/// Moving the level while muted unmutes, as the macOS volume keys do.
- (void)setMicrophoneLevel:(float)value;
- (void)setOutputMuted:(BOOL)muted;
- (void)selectManually:(APBAudioDevice *)device;
/// Selects a device with its paired counterpart, regardless of
/// `selectsPairedDevice`. Output goes first so a failed output selection,
/// like a plain manual selection, never moves the microphone.
- (void)selectWithPairedDevice:(APBAudioDevice *)device;
/// Selects one device only, regardless of `selectsPairedDevice`.
- (void)selectOnly:(APBAudioDevice *)device;
- (void)setVolume:(float)value;
- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device;
/// Hides a device everywhere: from Microphones, or from both Speakers and
/// Headphones, so one command has one meaning regardless of which output list
/// a device currently sits in.
- (void)hide:(APBAudioDevice *)device;
- (void)unhide:(APBAudioDevice *)device;
- (BOOL)isHidden:(APBAudioDevice *)device;
- (BOOL)isNeverUse:(APBAudioDevice *)device;
- (void)setNeverUse:(APBAudioDevice *)device enabled:(BOOL)enabled;
- (void)forget:(APBAudioDevice *)device;
- (void)moveInputFrom:(NSInteger)source to:(NSInteger)destination;
- (void)moveOutputInCategory:(APBOutputCategory)category from:(NSInteger)source to:(NSInteger)destination;
/// `category` is `None` for the microphone list.
- (BOOL)dropDevice:(NSString *)identifier intoCategory:(APBOutputCategory)category at:(NSInteger)destination;

@end

NS_ASSUME_NONNULL_END
