#import <AppKit/AppKit.h>
#import "AppModel.h"

NS_ASSUME_NONNULL_BEGIN

@class APBDeviceRowView;

/// The list a row sits in, which owns state shared between rows.
@protocol APBDeviceRowHost <NSObject>
/// The id of the device whose row should show a highlight because the
/// selection override on its paired device's row is hovered, held by the
/// list since the two rows can be in different sections.
@property (nonatomic, copy, nullable) NSString *highlightedPairedDeviceID;
/// The pointer went down on a row; the host tracks a click or a drag.
- (void)row:(APBDeviceRowView *)row mouseDown:(NSEvent *)event;
/// Moves the row's device to `target` within its list.
- (void)row:(APBDeviceRowView *)row moveTo:(NSInteger)target;
@end

/// One device in a list: its priority, icon, name and state, with a
/// selection override and an actions menu that appear on hover.
@interface APBDeviceRowView : NSView

@property (nonatomic, weak, nullable) id<APBDeviceRowHost> host;
@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic) BOOL isLifted;
/// Shows the no-entry badge on a lifted row over the wrong list.
@property (nonatomic) BOOL isForbidden;

- (instancetype)initWithModel:(APBAppModel *)model;

- (void)configureWithDevice:(APBAudioDevice *)device
                      index:(NSInteger)index
                      count:(NSInteger)count
                 isSelected:(BOOL)isSelected
                   category:(APBOutputCategory)category;

/// Whether a click selects the device: connected, available, not current.
@property (nonatomic, readonly) BOOL isSelectable;
- (void)selectDevice;
/// Redraws the highlight after the host's shared state changed.
- (void)refreshHighlight;

@end

NS_ASSUME_NONNULL_END
