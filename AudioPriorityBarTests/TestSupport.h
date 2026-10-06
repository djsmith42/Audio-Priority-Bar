#import <XCTest/XCTest.h>
#import "AppModel.h"
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Records what the model asks of CoreAudio and answers from plain state.
@interface APBFakeAudio : NSObject

@property (nonatomic, copy) NSArray<APBAudioDevice *> *catalog;
/// Default device ID by role (`@(APBDeviceRole)`).
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSNumber *> *defaults;
/// Nil when the output has no volume.
@property (nonatomic, nullable) NSNumber *volume;
/// "input:1" or "output:2", the role's raw value and the device ID.
@property (nonatomic, readonly) NSMutableSet<NSString *> *muted;
/// Each successful selection as `@[@(role), @(deviceID)]`, in order.
@property (nonatomic, readonly) NSMutableArray<NSArray<NSNumber *> *> *selections;
@property (nonatomic) BOOL selectionSucceeds;
@property (nonatomic, readonly) NSMutableSet<NSNumber *> *failedSelectionRoles;
@property (nonatomic) NSInteger volumeReadCount;
@property (nonatomic) NSInteger muteReadCount;
/// Devices without a settable mute property, like ZoomAudioDevice or a
/// Scarlett Solo.
@property (nonatomic, readonly) NSMutableSet<NSNumber *> *noMuteProperty;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSNumber *> *inputVolumes;
@property (nonatomic, readonly) NSMutableSet<NSNumber *> *running;

@property (nonatomic, readonly) APBAudioOperations *operations;

/// The roles of `selections`, in order.
@property (nonatomic, readonly) NSArray<NSNumber *> *selectedRoles;
/// The device IDs of `selections`, in order.
@property (nonatomic, readonly) NSArray<NSNumber *> *selectedIDs;

/// "output:2" for muting device 2's output.
+ (NSString *)muteKeyForRole:(APBDeviceRole)role deviceID:(UInt32)deviceID;

@end

/// A model over `audio` with every device usable and unmonitored unless the
/// blocks say otherwise.
FOUNDATION_EXPORT APBAppModel *APBTestModel(APBFakeAudio *audio,
                                            NSUserDefaults *defaults,
                                            BOOL (^_Nullable usable)(APBAudioDevice *device),
                                            APBLinkState (^_Nullable state)(APBAudioDevice *device),
                                            BOOL (^_Nullable isUserPicking)(void));

/// A connected output, named "Speaker" when `name` is nil.
FOUNDATION_EXPORT APBAudioDevice *APBOutput(UInt32 deviceID, NSString *uid, NSString *_Nullable name);
/// A connected input, named "Microphone" when `name` is nil.
FOUNDATION_EXPORT APBAudioDevice *APBInput(UInt32 deviceID, NSString *uid, NSString *_Nullable name);
/// Empty defaults no other test shares.
FOUNDATION_EXPORT NSUserDefaults *APBIsolatedDefaults(void);

/// Runs the main run loop until queued main-queue work has run.
FOUNDATION_EXPORT void APBDrainMainQueue(void);

NS_ASSUME_NONNULL_END
