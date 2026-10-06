#import <AppKit/AppKit.h>
#import "AppModel.h"
#import "SettingsWindowController.h"
#import "UpdateChecker.h"

NS_ASSUME_NONNULL_BEGIN

/// The menu bar icon: a click opens the panel, a right or Control click the
/// menu, and an Option click toggles the microphone mute.
@interface APBStatusItemController : NSObject <NSWindowDelegate>

- (instancetype)initWithModel:(APBAppModel *)model
                     settings:(APBSettingsWindowController *)settings
                      updates:(APBUpdateChecker *)updates;

@end

NS_ASSUME_NONNULL_END
