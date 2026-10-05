#import <Foundation/Foundation.h>
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat APBRowHeight = 30;
static const CGFloat APBRowSpacing = 3;
static const CGFloat APBRowPitch = APBRowHeight + APBRowSpacing;
static const CGFloat APBSectionHeaderHeight = 18;

/// One of the panel's three device lists.
typedef NS_ENUM(NSInteger, APBDeviceSection) {
    APBDeviceSectionSpeaker,
    APBDeviceSectionHeadphone,
    APBDeviceSectionInput,
};

FOUNDATION_EXPORT APBOutputCategory APBDeviceSectionCategory(APBDeviceSection section);
FOUNDATION_EXPORT APBDeviceRole APBDeviceSectionRole(APBDeviceSection section);

typedef struct {
    BOOL exists;
    APBDeviceSection section;
    NSInteger index;
} APBDropTarget;

FOUNDATION_EXPORT BOOL APBDropTargetEqual(APBDropTarget left, APBDropTarget right);

/// A row being dragged. Held by the panel rather than a section so the row
/// can be carried into another list.
@interface APBDeviceDrag : NSObject
@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) APBDeviceSection section;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) APBDropTarget target;
@property (nonatomic, readonly) CGSize translation;
@property (nonatomic, readonly) BOOL isForbidden;

- (instancetype)initWithDevice:(APBAudioDevice *)device section:(APBDeviceSection)section index:(NSInteger)index NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)updateHovered:(APBDropTarget)hovered translation:(CGSize)translation;
@end

/// The stacked lists' geometry, derived from the same row metrics the panel
/// lays out with. Computing it instead of measuring keeps the drop target and
/// the panel height in agreement, and avoids a layout-feedback loop where
/// opening a gap would move the rows the target is calculated from.
@interface APBPanelLayout : NSObject

/// Room above a section for its separator, which sits `separatorInset` below
/// the previous section, leaving the rest as padding under it.
@property (class, nonatomic, readonly) CGFloat sectionGap;
@property (class, nonatomic, readonly) CGFloat separatorInset;
@property (class, nonatomic, readonly) CGFloat horizontalPadding;
/// Matches the room between a section separator and the next heading.
@property (class, nonatomic, readonly) CGFloat topPadding;
@property (class, nonatomic, readonly) CGFloat bottomPadding;

/// Sections in order, each `@[@(section), @(count)]`.
- (instancetype)initWithSections:(NSArray<NSArray<NSNumber *> *> *)sections NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Nearest gap to `y`, measured from the top of a section.
+ (NSInteger)insertionIndexForY:(CGFloat)y rowCount:(NSInteger)rowCount;

@property (nonatomic, readonly) CGFloat contentHeight;
/// Measured from the top of the lists; NAN for a section not laid out.
- (CGFloat)sectionTopOf:(APBDeviceSection)section;
- (CGFloat)contentTopOf:(APBDeviceSection)section;
- (CGFloat)sectionOffsetFor:(APBDeviceSection)section drag:(APBDeviceDrag *)drag;
/// How much taller the lists become while `drag` previews its drop.
- (CGFloat)heightDeltaFor:(APBDeviceDrag *)drag;
- (CGFloat)rowOffsetAt:(NSInteger)index in:(APBDeviceSection)section drag:(APBDeviceDrag *)drag;
- (CGFloat)liftedOffsetFor:(APBDeviceDrag *)drag;
/// The list and row gap under `point`, before applying device-role rules.
/// `y` grows downward from the top of the lists.
- (APBDropTarget)targetAtY:(CGFloat)y;

@end

NS_ASSUME_NONNULL_END
