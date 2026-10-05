#import <AppKit/AppKit.h>
#import "APBAppModel.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat APBPanelWidth = 380;

/// The panel under the status item: the automatic switching toggle, the
/// output and microphone levels, the three device lists and the footer.
@interface APBPanelView : NSView

@property (nonatomic, copy, nullable) dispatch_block_t onShowSettings;
/// Called after the content changes height, so the window can follow it.
@property (nonatomic, copy, nullable) dispatch_block_t onSizeChange;

- (instancetype)initWithModel:(APBAppModel *)model;
/// Re-reads the model. Called while the panel is visible.
- (void)refresh;
/// Drops a drag in progress, as when the panel loses key.
- (void)cancelDrag;

@end

NS_ASSUME_NONNULL_END
