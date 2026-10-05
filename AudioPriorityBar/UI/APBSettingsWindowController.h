#import <AppKit/AppKit.h>
#import "APBAppModel.h"
#import "APBHotKey.h"
#import "APBServices.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBSettingsPlacement : NSObject
/// Where to move a window so it lands centered on a screen, or nil when it is
/// already on that screen and whatever the user did with it should be left
/// alone.
+ (nullable NSValue *)originForWindow:(NSRect)frame screenFrame:(NSRect)screenFrame visibleFrame:(NSRect)visibleFrame;
@end

@interface APBSettingsWindowController : NSWindowController

- (instancetype)initWithModel:(APBAppModel *)model
                launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                      updates:(APBUpdateChecker *)updates
                  muteHotKey:(APBHotKey *)muteHotKey;

/// Opens on the screen whose menu bar was used, rather than reappearing
/// wherever it was last left, which on a multi-screen desk is usually the
/// wrong one.
- (void)showSettingsOnScreen:(nullable NSScreen *)screen;

@end

NS_ASSUME_NONNULL_END
