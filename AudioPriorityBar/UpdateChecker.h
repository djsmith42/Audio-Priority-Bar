#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Keeps the app current through Sparkle: with automatic updates on, a new
/// release is downloaded, verified against `SUPublicEDKey`, installed and
/// relaunched without asking. Turning them off leaves only manual checks.
@interface APBUpdateChecker : NSObject

/// Only release packaging sets a feed, so local builds never replace
/// themselves with the published release.
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, readonly) BOOL automaticUpdatesEnabled;
/// Called after `automaticUpdatesEnabled` changes.
@property (nonatomic, copy, nullable) void (^onChange)(void);

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          bundle:(NSBundle *)bundle
                          isIdle:(BOOL (^_Nullable)(void))isIdle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIsIdle:(BOOL (^_Nullable)(void))isIdle;
- (instancetype)init;

- (void)start;
- (void)setAutomaticUpdatesEnabled:(BOOL)enabled;
- (void)checkForUpdates;

/// Quitting releases any microphone mute the app applied, so a restart waits
/// until the microphone is neither muted nor recording.
- (void)installWhenIdle:(void (^)(void))install;
- (void)installPendingUpdateIfIdle;

@end

NS_ASSUME_NONNULL_END
