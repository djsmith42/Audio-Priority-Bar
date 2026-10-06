#import <AppKit/AppKit.h>
#import "AppModel.h"
#import "DeviceRowView.h"

NS_ASSUME_NONNULL_BEGIN

/// The panel's three stacked device lists: Speakers, Headphones and
/// Microphones. Rows are laid out from `APBPanelLayout`, and dragging a row
/// reorders it or carries it into another list.
@interface APBDeviceListView : NSView <APBDeviceRowHost>

@property (nonatomic, copy, nullable) NSString *highlightedPairedDeviceID;
/// Called when `contentHeight` changes, as when a drag previews a drop.
@property (nonatomic, copy, nullable) void (^onHeightChange)(void);

- (instancetype)initWithModel:(APBAppModel *)model;

/// The lists' height. Only ever grows for a drag, so a preview that adds a
/// row cannot clip the bottom of the list, and one that removes a row cannot
/// resize the panel out from under the cursor.
@property (nonatomic, readonly) CGFloat contentHeight;

/// Reads the model again.
- (void)reload;
/// Abandons a drag, as when the panel closes.
- (void)cancelDrag;

@end

NS_ASSUME_NONNULL_END
