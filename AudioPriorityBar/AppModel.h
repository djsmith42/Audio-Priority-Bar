#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread, coalesced, after any state the UI shows changes.
FOUNDATION_EXPORT NSNotificationName const APBAppModelDidChangeNotification;

/// The CoreAudio calls the model makes, injected so tests can fake them.
@interface APBAudioOperations : NSObject

@property (nonatomic, copy) NSArray<APBAudioDevice *> *(^devices)(void);
/// Nil when the role has no default device.
@property (nonatomic, copy) NSNumber *_Nullable (^defaultDevice)(APBDeviceRole role);
@property (nonatomic, copy) BOOL (^setDefault)(APBDeviceRole role, UInt32 deviceID);
@property (nonatomic, copy) NSNumber *_Nullable (^outputVolume)(void);
@property (nonatomic, copy) BOOL (^setOutputVolume)(float value);
@property (nonatomic, copy) BOOL (^isMuted)(APBDeviceRole role, UInt32 deviceID);
@property (nonatomic, copy) BOOL (^setMute)(APBDeviceRole role, UInt32 deviceID, BOOL muted);
@property (nonatomic, copy) BOOL (^canSetMute)(APBDeviceRole role, UInt32 deviceID);
@property (nonatomic, copy) NSNumber *_Nullable (^inputVolume)(UInt32 deviceID);
@property (nonatomic, copy) BOOL (^setInputVolume)(UInt32 deviceID, float value);
@property (nonatomic, copy) BOOL (^isRunning)(UInt32 deviceID);

@end

/// What the Jabra monitor knows about a device.
@interface APBLinkOperations : NSObject

@property (nonatomic, copy) BOOL (^isUsable)(APBAudioDevice *device);
/// `APBLinkStateNone` for a device that is not monitored.
@property (nonatomic, copy) APBLinkState (^state)(APBAudioDevice *device);
/// The headset's battery percentage, or nil. Defaults to nil.
@property (nonatomic, copy) NSNumber *_Nullable (^battery)(APBAudioDevice *device);

- (instancetype)initWithIsUsable:(BOOL (^)(APBAudioDevice *device))isUsable
                           state:(APBLinkState (^)(APBAudioDevice *device))state;

@end

typedef NS_ENUM(NSInteger, APBOutputSkipReason) {
    APBOutputSkipReasonOff,
    APBOutputSkipReasonNeverAutoSelect,
};

@interface APBSkippedOutput : NSObject

@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) APBOutputSkipReason reason;

- (instancetype)initWithDevice:(APBAudioDevice *)device reason:(APBOutputSkipReason)reason;

@end

@interface APBAutomaticOutputDecision : NSObject

@property (nonatomic, readonly, nullable) APBAudioDevice *target;
@property (nonatomic, readonly, nullable) APBSkippedOutput *skipped;
/// A candidate is still being checked, so no choice should be applied yet.
@property (nonatomic, readonly) BOOL isDeferred;

- (instancetype)initWithTarget:(nullable APBAudioDevice *)target
                       skipped:(nullable APBSkippedOutput *)skipped
                    isDeferred:(BOOL)isDeferred;

@end

@interface APBAppModel : NSObject

@property (nonatomic, copy) NSArray<APBAudioDevice *> *inputDevices;
@property (nonatomic, copy) NSArray<APBAudioDevice *> *speakerDevices;
@property (nonatomic, copy) NSArray<APBAudioDevice *> *headphoneDevices;
@property (nonatomic, copy) NSArray<APBAudioDevice *> *hiddenSpeakerDevices;
@property (nonatomic, copy) NSArray<APBAudioDevice *> *hiddenHeadphoneDevices;
/// The current devices' platform IDs, nil when there is none.
@property (nonatomic, nullable) NSNumber *currentInputID;
@property (nonatomic, nullable) NSNumber *currentOutputID;
@property (nonatomic) float volume;
@property (nonatomic) BOOL isVolumeControllable;
/// The current output has a settable mute property. Some, like TVs and audio
/// interfaces, have neither a volume nor a mute.
@property (nonatomic) BOOL isOutputMutable;
/// The current microphone's input level. While it is muted by zeroing, this
/// is the level unmuting will restore rather than zero.
@property (nonatomic) float microphoneLevel;
@property (nonatomic) BOOL isMicrophoneLevelControllable;
/// The current microphone can be muted, by its mute property or by zeroing
/// its level.
@property (nonatomic) BOOL isMicrophoneMutable;
@property (nonatomic) BOOL showAll;
@property (nonatomic) BOOL isManualMode;
@property (nonatomic) BOOL selectsPairedDevice;
@property (nonatomic) BOOL hideNewDisplayOutputs;
@property (nonatomic) BOOL isActiveOutputMuted;
@property (nonatomic) BOOL isActiveInputMuted;
@property (nonatomic) BOOL micFlashState;
/// The microphone mute the user asked for, carried to whichever microphone
/// is current.
@property (nonatomic) BOOL isMicrophoneMuted;
/// Some app is recording from the current microphone.
@property (nonatomic) BOOL isInputRecording;
@property (nonatomic) BOOL showsSwitchNotice;
@property (nonatomic) BOOL remindsWhenMuted;
@property (nonatomic) BOOL mutesSpeakersWhenHeadphonesDisconnect;
@property (nonatomic) BOOL outlinesMenuBarIcon;
@property (nonatomic) APBMenuBarDevices menuBarDevices;
@property (nonatomic) BOOL showsMenuBarVolume;
/// Called with the devices Automatic mode just switched to because the
/// hardware changed, output first. Never for the user's own choices.
@property (nonatomic, copy, nullable) void (^onAutomaticSwitch)(NSArray<APBAudioDevice *> *devices);

@property (nonatomic, readonly) APBPriorityStore *store;
@property (nonatomic, readonly) APBAudioOperations *audio;
@property (nonatomic, readonly) APBLinkOperations *link;
@property (nonatomic, readonly) APBBluetoothBatteryMonitor *battery;

/// Keeps "Output only" intact when CoreAudio echoes our own default change.
/// Held by UID because platform IDs are recycled across devices.
@property (nonatomic, copy, nullable) NSString *selectedOnlyOutputUID;
/// Devices picked in Control Center or Sound Settings, or that macOS keeps
/// switching to, by role and UID. Automatic mode keeps them until a device
/// connects or disconnects.
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *keptPicks;
/// When the app last switched each role back after macOS or another app
/// moved it, by role.
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *switchedBackAt;
/// The device macOS moved each role to again soon after a switch back, by
/// role and UID. The app leaves it there and names it in the panel.
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *takeoverUIDs;

- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(APBAudioOperations *)audio
                         link:(APBLinkOperations *)link
                      battery:(nullable APBBluetoothBatteryMonitor *)battery
                 reduceMotion:(BOOL (^_Nullable)(void))reduceMotion
                isUserPicking:(BOOL (^_Nullable)(void))isUserPicking NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(APBAudioOperations *)audio
                         link:(APBLinkOperations *)link;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

- (void)handleDevicesChanged;
/// The Jabra monitor reached a new verdict for some dongle.
- (void)handleLinkChanged;
- (void)handleDefaultChanged:(APBDeviceRole)role;
/// Coalesces a burst of mute and volume callbacks into one refresh on the
/// next turn of the main queue.
- (void)handleMuteOrVolumeChanged;
/// A Jabra headset reported a new battery level.
- (void)handleBatteryChanged;

- (void)refreshDevices;
- (void)refreshVolume;
- (void)refreshMute;

/// The device macOS keeps switching to, while it is still current, output
/// first.
@property (nonatomic, readonly, nullable) APBAudioDevice *takeoverDevice;
@property (nonatomic, readonly, nullable) APBAudioDevice *currentInputDevice;
@property (nonatomic, readonly, nullable) APBAudioDevice *currentOutputDevice;
@property (nonatomic, readonly) APBOutputCategory activeOutputCategory;
/// Audio is routed to a device we know cannot play it. Automatic switching
/// moves away on its own, so this only persists in manual mode or when there
/// is nothing better to fall back to.
@property (nonatomic, readonly) BOOL isActiveOutputLinkDown;
@property (nonatomic, readonly) APBAutomaticOutputDecision *automaticOutputDecision;

- (BOOL)isMuted:(APBAudioDevice *)device;
/// AirPods battery levels, read again when devices come or go and whenever
/// the panel opens, or a Jabra headset's, which it reports itself.
- (nullable APBBatteryLevels *)batteryLevelsForDevice:(APBAudioDevice *)device;
- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device;

- (void)applyHighestPriorityDevices;
- (void)applyHighestPriorityInput;
- (void)applyHighestPriorityOutput;

- (BOOL)select:(APBAudioDevice *)device;
- (BOOL)select:(APBAudioDevice *)device
  automatically:(BOOL)automatically
includesPairedDevice:(BOOL)includesPairedDevice;

/// Selects the paired counterpart of `device`, when `selectsPairedDevice`
/// covers both. Reaching from a microphone to its output only happens on a
/// direct pick (`automatically == NO`): automatic mode already anchors
/// microphone selection to the current output, so letting a priority-ranked
/// microphone reach back here would fight that output's own decision. The
/// already-current guard is what stops an output-to-mic-to-output cycle.
- (void)selectPairedDeviceOf:(APBAudioDevice *)device automatically:(BOOL)automatically;

/// The connected counterpart of `device` that shares its physical identity
/// (`pairingKey`), if any: the input half for an output, or the output half
/// for an input. Not gated by `selectsPairedDevice`, that setting only
/// governs the automatic selection in `selectPairedDeviceOf:`; the explicit
/// `selectWithPairedDevice:`/`selectOnly:` actions use this directly.
- (nullable APBAudioDevice *)pairedDeviceFor:(APBAudioDevice *)device;

/// Schedules one coalesced `APBAppModelDidChangeNotification`.
- (void)didChange;

@end

@interface APBAppModel (Actions)

- (void)setManualMode:(BOOL)enabled;
- (void)setSelectsPairedDeviceEnabled:(BOOL)enabled;
- (void)setHideNewDisplayOutputsEnabled:(BOOL)enabled;
- (void)setShowsSwitchNoticeEnabled:(BOOL)enabled;
- (void)setRemindsWhenMutedEnabled:(BOOL)enabled;
- (void)setMutesSpeakersWhenHeadphonesDisconnectEnabled:(BOOL)enabled;
- (void)setOutlinesMenuBarIconEnabled:(BOOL)enabled;
- (void)setMenuBarDevicesChoice:(APBMenuBarDevices)devices;
- (void)setShowsMenuBarVolumeEnabled:(BOOL)enabled;
- (void)setMicrophoneMuted:(BOOL)muted;
- (void)perform:(APBURLCommand)command;
/// Moving the level while muted unmutes, as the macOS volume keys do.
/// Named apart from the `microphoneLevel` property's setter.
- (void)changeMicrophoneLevel:(float)value;
- (void)setOutputMuted:(BOOL)muted;
- (void)selectManually:(APBAudioDevice *)device;
/// Selects a device with its paired counterpart, regardless of
/// `selectsPairedDevice`. Output goes first so a failed output selection,
/// like a plain manual selection, never moves the microphone.
- (void)selectWithPairedDevice:(APBAudioDevice *)device;
/// Selects one device only, regardless of `selectsPairedDevice`.
- (void)selectOnly:(APBAudioDevice *)device;
/// Sets the output volume, unmuting when it rises above zero. Named apart
/// from the `volume` property's setter.
- (void)changeVolume:(float)value;
- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device;
/// Hides a device everywhere: from Microphones, or from both Speakers and
/// Headphones, so one command has one meaning regardless of which output
/// list a device currently sits in.
- (void)hide:(APBAudioDevice *)device;
- (void)unhide:(APBAudioDevice *)device;
- (BOOL)isHidden:(APBAudioDevice *)device;
- (BOOL)isNeverUse:(APBAudioDevice *)device;
- (void)setNeverUse:(APBAudioDevice *)device enabled:(BOOL)enabled;
- (void)forget:(APBAudioDevice *)device;
- (void)moveInputFrom:(NSIndexSet *)source to:(NSInteger)destination;
- (void)moveOutputIn:(APBOutputCategory)category from:(NSIndexSet *)source to:(NSInteger)destination;
/// `category` of `APBOutputCategoryNone` drops into the microphones.
- (BOOL)dropDevice:(NSString *)identifier into:(APBOutputCategory)category at:(NSInteger)destination;

@end

NS_ASSUME_NONNULL_END
