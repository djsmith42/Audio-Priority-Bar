#import <AppKit/AppKit.h>
#import "AppModel.h"

NS_ASSUME_NONNULL_BEGIN

/// Draws the menu bar icon as one template image: the microphone, the output
/// and its volume, beside a warning while the headset is off.
@interface APBStatusLabel : NSObject

/// Drawn as a template, so the system dims it on an inactive display and
/// tints it when highlighted.
+ (NSImage *)imageForModel:(APBAppModel *)model;

@end

NS_ASSUME_NONNULL_END
