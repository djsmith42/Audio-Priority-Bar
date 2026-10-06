#import <AppKit/AppKit.h>
#import "AppModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The panel under the menu bar icon: automatic switching, the output and
/// microphone levels, the device lists and the footer.
@interface APBPanelViewController : NSViewController

/// Called after the panel's size changes.
@property (nonatomic, copy, nullable) void (^onSizeChange)(void);

- (instancetype)initWithModel:(APBAppModel *)model showSettings:(void (^)(void))showSettings;

/// Reads the model again.
- (void)reload;
/// Abandons a drag in progress.
- (void)cancelDrag;

@end

NS_ASSUME_NONNULL_END
