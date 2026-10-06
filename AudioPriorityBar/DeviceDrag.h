#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Row geometry shared by the lists and the layout math.
FOUNDATION_EXPORT const CGFloat APBDeviceRowHeight;
FOUNDATION_EXPORT const CGFloat APBDeviceRowSpacing;
FOUNDATION_EXPORT const CGFloat APBDeviceRowPitch;
FOUNDATION_EXPORT const CGFloat APBDeviceSectionHeaderHeight;

/// One of the panel's three device lists.
typedef NS_ENUM(NSInteger, APBDeviceSection) {
    APBDeviceSectionSpeaker,
    APBDeviceSectionHeadphone,
    APBDeviceSectionInput,
};

/// `APBOutputCategoryNone` for the microphones.
FOUNDATION_EXPORT APBOutputCategory APBDeviceSectionCategory(APBDeviceSection section);
FOUNDATION_EXPORT APBDeviceRole APBDeviceSectionRole(APBDeviceSection section);

@interface APBDropTarget : NSObject <NSCopying>

@property (nonatomic, readonly) APBDeviceSection section;
@property (nonatomic, readonly) NSInteger index;

+ (instancetype)targetWithSection:(APBDeviceSection)section index:(NSInteger)index;

@end

/// A row being dragged. Held by the panel rather than a section so the row
/// can be carried into another list.
@interface APBDeviceDrag : NSObject <NSCopying>

@property (nonatomic, readonly) APBAudioDevice *device;
@property (nonatomic, readonly) APBDeviceSection section;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, nullable) APBDropTarget *target;
@property (nonatomic) CGSize translation;
@property (nonatomic) BOOL isForbidden;

- (instancetype)initWithDevice:(APBAudioDevice *)device section:(APBDeviceSection)section index:(NSInteger)index;

- (void)updateHovered:(nullable APBDropTarget *)hovered translation:(CGSize)translation;

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

/// Pairs of `@[@(APBDeviceSection), @(rowCount)]`, top to bottom.
@property (nonatomic, readonly) NSArray<NSArray<NSNumber *> *> *sections;

- (instancetype)initWithSections:(NSArray<NSArray<NSNumber *> *> *)sections;

/// Nearest gap to `y`, measured from the top of a section.
+ (NSInteger)insertionIndexForY:(CGFloat)y rowCount:(NSInteger)rowCount;

@property (nonatomic, readonly) CGFloat contentHeight;
/// NAN for a section the layout does not hold.
- (CGFloat)sectionTopOf:(APBDeviceSection)section;
- (CGFloat)contentTopOf:(APBDeviceSection)section;
- (CGFloat)sectionOffsetFor:(APBDeviceSection)section drag:(APBDeviceDrag *)drag;
/// How much taller the lists become while `drag` previews its drop.
- (CGFloat)heightDeltaFor:(APBDeviceDrag *)drag;
- (CGFloat)rowOffsetAt:(NSInteger)index in:(APBDeviceSection)section drag:(APBDeviceDrag *)drag;
- (CGSize)liftedOffsetFor:(APBDeviceDrag *)drag;
/// The list and row gap under `point`, before applying device-role rules.
- (nullable APBDropTarget *)targetAt:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
