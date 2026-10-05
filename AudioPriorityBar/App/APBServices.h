#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const APBAppDisplayName;

#pragma mark - Launch at login

typedef BOOL (^APBLoginItemAction)(NSError **error);

@interface APBLaunchAtLoginController : NSObject

@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) BOOL requiresApproval;
@property (nonatomic, readonly, copy, nullable) NSString *errorMessage;

/// Uses `SMAppService.mainApp`.
- (instancetype)init;
- (instancetype)initWithStatus:(SMAppServiceStatus (^)(void))status
                      register:(APBLoginItemAction)registerAction
                    unregister:(APBLoginItemAction)unregisterAction NS_DESIGNATED_INITIALIZER;

- (void)refresh;
- (void)setEnabled:(BOOL)enabled;

@end

#pragma mark - Updates

/// Keeps the app current through Sparkle: with automatic updates on, a new
/// release is downloaded, verified against `SUPublicEDKey`, installed and
/// relaunched without asking. Turning them off leaves only manual checks.
@interface APBUpdateChecker : NSObject

/// Only release packaging sets a feed, so local builds never replace
/// themselves with the published release.
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, readonly) BOOL automaticUpdatesEnabled;

- (instancetype)initWithIsIdle:(BOOL (^)(void))isIdle;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          bundle:(NSBundle *)bundle
                          isIdle:(BOOL (^)(void))isIdle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)setAutomaticUpdatesEnabled:(BOOL)enabled;
- (void)checkForUpdates;
/// Quitting releases any microphone mute the app applied, so a restart waits
/// until the microphone is neither muted nor recording.
- (void)installWhenIdle:(dispatch_block_t)install;
- (void)installPendingUpdateIfIdle;

@end

#pragma mark - System sound picker

/// Whether someone is picking a device in Control Center or System Settings
/// right now. CoreAudio never says who changed a default, but Control Center
/// shows a window outside the menu bar's layer only while one of its menus is
/// open. Window owners and layers need no permission to read.
@interface APBSystemSoundPicker : NSObject
+ (BOOL)isInUse;
+ (BOOL)isInUseWithWindows:(NSArray<NSDictionary<NSString *, id> *> *)windows
         controlCenterPIDs:(NSSet<NSNumber *> *)controlCenterPIDs
          frontmostBundleID:(nullable NSString *)frontmostBundleID;
@end

NS_ASSUME_NONNULL_END
