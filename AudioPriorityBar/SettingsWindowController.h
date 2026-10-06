#import <AppKit/AppKit.h>
#import "AppModel.h"
#import "LaunchAtLoginController.h"
#import "UpdateChecker.h"

NS_ASSUME_NONNULL_BEGIN

/// The Settings window: Menu Bar, Devices, Shortcuts and App tabs.
@interface APBSettingsWindowController : NSWindowController

- (instancetype)initWithModel:(APBAppModel *)model
                launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                      updates:(APBUpdateChecker *)updates;

/// Opens on the screen whose menu bar was used, rather than reappearing
/// wherever it was last left, which on a multi-screen desk is usually the
/// wrong one.
- (void)showSettingsOnScreen:(nullable NSScreen *)screen;

@end

NS_ASSUME_NONNULL_END
