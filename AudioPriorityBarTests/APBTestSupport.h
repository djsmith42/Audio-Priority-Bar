#import <XCTest/XCTest.h>
#import "APBAppModel.h"
#import "APBCoreAudio.h"
#import "APBModels.h"
#import "APBPriorityStore.h"

NS_ASSUME_NONNULL_BEGIN

/// A selection the fake recorded, in order.
@interface APBSelection : NSObject
@property (nonatomic, readonly) APBDeviceRole role;
@property (nonatomic, readonly) UInt32 deviceID;
@end

/// Stands in for CoreAudio. Mute keys are `input:<id>` or `output:<id>`.
@interface APBFakeAudio : NSObject <APBAudioOperations>
@property (nonatomic, copy) NSArray<APBAudioDevice *> *catalog;
/// Keyed by role.
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *defaults;
/// Nil when the output has no volume.
@property (nonatomic, nullable) NSNumber *volume;
@property (nonatomic) NSMutableSet<NSString *> *muted;
@property (nonatomic) NSMutableArray<APBSelection *> *selections;
@property (nonatomic) BOOL selectionSucceeds;
@property (nonatomic) NSMutableSet<NSNumber *> *failedSelectionRoles;
@property (nonatomic) NSInteger volumeReadCount;
@property (nonatomic) NSInteger muteReadCount;
/// Devices without a settable mute property, like ZoomAudioDevice or a
/// Scarlett Solo.
@property (nonatomic) NSMutableSet<NSNumber *> *noMuteProperty;
@property (nonatomic) NSMutableDictionary<NSNumber *, NSNumber *> *inputVolumes;
@property (nonatomic) NSMutableSet<NSNumber *> *running;

/// The device IDs selected, in order.
@property (nonatomic, readonly) NSArray<NSNumber *> *selectedIDs;
/// The roles selected, in order.
@property (nonatomic, readonly) NSArray<NSNumber *> *selectedRoles;
- (void)setDefault:(UInt32)deviceID role:(APBDeviceRole)role;
@end

FOUNDATION_EXPORT APBAudioDevice *APBOutput(UInt32 deviceID, NSString *uid, NSString *_Nullable name);
FOUNDATION_EXPORT APBAudioDevice *APBInput(UInt32 deviceID, NSString *uid, NSString *_Nullable name);
/// A fresh, empty defaults suite.
FOUNDATION_EXPORT NSUserDefaults *APBIsolatedDefaults(void);

/// A model over the fake, every device usable and unmonitored unless given.
FOUNDATION_EXPORT APBAppModel *APBTestModel(APBFakeAudio *audio,
                                            NSUserDefaults *defaults,
                                            APBLinkUsable _Nullable usable,
                                            APBLinkStateProvider _Nullable state,
                                            BOOL (^_Nullable isUserPicking)(void));

/// Spins the main run loop until `condition` holds or `timeout` passes.
FOUNDATION_EXPORT BOOL APBWaitUntil(NSTimeInterval timeout, BOOL (^condition)(void));

/// The UIDs of each list of devices, for comparing notices.
FOUNDATION_EXPORT NSArray<NSArray<NSString *> *> *APBUIDLists(NSArray<NSArray<APBAudioDevice *> *> *lists);

NS_ASSUME_NONNULL_END
