#import <AppKit/AppKit.h>
#import "APBAppModel.h"
#import "APBDeviceDrag.h"
#import "APBUI.h"

NS_ASSUME_NONNULL_BEGIN

@class APBDeviceRowView;

/// What a row reports back to the lists that hold it.
@protocol APBDeviceRowDelegate <NSObject>
/// The id of the device whose row should show a highlight because the
/// selection override on its paired device's row is hovered, held by the
/// lists since the two rows can be in different sections.
@property (nonatomic, copy, nullable) NSString *highlightedPairedDeviceID;
- (void)row:(APBDeviceRowView *)row moveTo:(NSInteger)target;
- (void)row:(APBDeviceRowView *)row dragChangedAt:(NSPoint)point translation:(CGSize)translation;
- (void)rowDragEnded:(APBDeviceRowView *)row;
@end

@interface APBDeviceRowView : APBHoverView

@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) APBDeviceSection section;
@property (nonatomic) BOOL isLifted;
@property (nonatomic) BOOL isForbidden;

- (instancetype)initWithModel:(APBAppModel *)model delegate:(id<APBDeviceRowDelegate>)delegate;

/// Shows `device` at `index` of `count` in `section`, read fresh from the
/// model.
- (void)updateDevice:(APBAudioDevice *)device
               index:(NSInteger)index
               count:(NSInteger)count
          isSelected:(BOOL)isSelected
             section:(APBDeviceSection)section;
/// Re-reads everything from the model, as after any change.
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
