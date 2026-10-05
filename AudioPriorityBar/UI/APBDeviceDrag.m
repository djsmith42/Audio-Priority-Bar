#import "APBDeviceDrag.h"

APBOutputCategory APBDeviceSectionCategory(APBDeviceSection section) {
    switch (section) {
        case APBDeviceSectionSpeaker: return APBOutputCategorySpeaker;
        case APBDeviceSectionHeadphone: return APBOutputCategoryHeadphone;
        case APBDeviceSectionInput: return APBOutputCategoryNone;
    }
    return APBOutputCategoryNone;
}

APBDeviceRole APBDeviceSectionRole(APBDeviceSection section) {
    return section == APBDeviceSectionInput ? APBDeviceRoleInput : APBDeviceRoleOutput;
}

BOOL APBDropTargetEqual(APBDropTarget left, APBDropTarget right) {
    if (!left.exists || !right.exists) return left.exists == right.exists;
    return left.section == right.section && left.index == right.index;
}

@implementation APBDeviceDrag

- (instancetype)initWithDevice:(APBAudioDevice *)device section:(APBDeviceSection)section index:(NSInteger)index {
    self = [super init];
    if (self) {
        _device = device;
        _section = section;
        _index = index;
    }
    return self;
}

- (void)updateHovered:(APBDropTarget)hovered translation:(CGSize)translation {
    _translation = translation;
    _isForbidden = hovered.exists && APBDeviceSectionRole(hovered.section) != _device.role;
    _target = _isForbidden ? (APBDropTarget){ .exists = NO } : hovered;
}

@end

@implementation APBPanelLayout {
    NSArray<NSArray<NSNumber *> *> *_sections;
}

+ (CGFloat)sectionGap { return 16; }
+ (CGFloat)separatorInset { return 8; }
+ (CGFloat)horizontalPadding { return 12; }
+ (CGFloat)topPadding { return self.sectionGap - self.separatorInset; }
+ (CGFloat)bottomPadding { return 8; }

- (instancetype)initWithSections:(NSArray<NSArray<NSNumber *> *> *)sections {
    self = [super init];
    if (self) _sections = [sections copy];
    return self;
}

+ (NSInteger)insertionIndexForY:(CGFloat)y rowCount:(NSInteger)rowCount {
    CGFloat top = APBSectionHeaderHeight + APBRowSpacing;
    CGFloat gap = round((y - top) / APBRowPitch);
    return MAX(0, MIN(rowCount, (NSInteger)gap));
}

static CGFloat Height(NSInteger count) {
    return APBSectionHeaderHeight + (CGFloat)MAX(count, 1) * APBRowPitch;
}

/// An empty list still reserves a placeholder row, so giving up a last device,
/// or taking a first one, changes no height.
static CGFloat Shrink(NSInteger count) {
    return Height(MAX(count - 1, 0)) - Height(count);
}

static CGFloat Grow(NSInteger count) {
    return Height(count + 1) - Height(count);
}

- (APBDeviceSection)sectionAt:(NSUInteger)index {
    return _sections[index][0].integerValue;
}

- (NSInteger)countAt:(NSUInteger)index {
    return _sections[index][1].integerValue;
}

- (NSUInteger)indexOf:(APBDeviceSection)section {
    for (NSUInteger index = 0; index < _sections.count; index++) {
        if ([self sectionAt:index] == section) return index;
    }
    return NSNotFound;
}

- (CGFloat)contentHeight {
    CGFloat height = APBPanelLayout.topPadding + APBPanelLayout.bottomPadding
        + (CGFloat)MAX((NSInteger)_sections.count - 1, 0) * APBPanelLayout.sectionGap;
    for (NSUInteger index = 0; index < _sections.count; index++) height += Height([self countAt:index]);
    return height;
}

- (CGFloat)sectionTopOf:(APBDeviceSection)section {
    CGFloat top = APBPanelLayout.topPadding;
    for (NSUInteger index = 0; index < _sections.count; index++) {
        if ([self sectionAt:index] == section) return top;
        top += Height([self countAt:index]) + APBPanelLayout.sectionGap;
    }
    return NAN;
}

- (CGFloat)contentTopOf:(APBDeviceSection)section {
    return [self sectionTopOf:section] + APBSectionHeaderHeight + APBRowSpacing;
}

- (CGFloat)sectionOffsetFor:(APBDeviceSection)section drag:(APBDeviceDrag *)drag {
    APBDropTarget target = drag.target;
    if (!target.exists || target.section == drag.section) return 0;
    NSUInteger sourceIndex = [self indexOf:drag.section];
    NSUInteger targetIndex = [self indexOf:target.section];
    NSUInteger sectionIndex = [self indexOf:section];
    if (sourceIndex == NSNotFound || targetIndex == NSNotFound || sectionIndex == NSNotFound) return 0;
    CGFloat offset = 0;
    if (sourceIndex < sectionIndex) offset += Shrink([self countAt:sourceIndex]);
    if (targetIndex < sectionIndex) offset += Grow([self countAt:targetIndex]);
    return offset;
}

- (CGFloat)heightDeltaFor:(APBDeviceDrag *)drag {
    APBDropTarget target = drag.target;
    if (!target.exists || target.section == drag.section) return 0;
    NSUInteger source = [self indexOf:drag.section];
    NSUInteger destination = [self indexOf:target.section];
    if (source == NSNotFound || destination == NSNotFound) return 0;
    return Shrink([self countAt:source]) + Grow([self countAt:destination]);
}

- (CGFloat)rowOffsetAt:(NSInteger)index in:(APBDeviceSection)section drag:(APBDeviceDrag *)drag {
    APBDropTarget target = drag.target;
    if (!target.exists) return 0;
    CGFloat offset = 0;
    if (drag.section == section && index > drag.index) offset -= APBRowPitch;
    if (target.section == section && index >= target.index) offset += APBRowPitch;
    return offset;
}

- (CGFloat)liftedOffsetFor:(APBDeviceDrag *)drag {
    APBDropTarget target = drag.target;
    CGFloat sourceTop = [self contentTopOf:drag.section];
    CGFloat targetTop = target.exists ? [self contentTopOf:target.section] : NAN;
    if (!target.exists || isnan(sourceTop) || isnan(targetTop)) return drag.translation.height;
    CGFloat sourceY = sourceTop + (CGFloat)drag.index * APBRowPitch + [self sectionOffsetFor:drag.section drag:drag];
    NSInteger targetIndex = target.index;
    if (target.section == drag.section && targetIndex > drag.index) targetIndex -= 1;
    CGFloat targetY = targetTop + [self sectionOffsetFor:target.section drag:drag] + (CGFloat)targetIndex * APBRowPitch;
    return targetY - sourceY;
}

- (APBDropTarget)targetAtY:(CGFloat)y {
    CGFloat top = APBPanelLayout.topPadding;
    for (NSUInteger index = 0; index < _sections.count; index++) {
        NSInteger count = [self countAt:index];
        CGFloat bottom = top + Height(count) + APBPanelLayout.sectionGap;
        if (y < bottom) {
            return (APBDropTarget){
                .exists = YES,
                .section = [self sectionAt:index],
                .index = [APBPanelLayout insertionIndexForY:y - top rowCount:count],
            };
        }
        top = bottom;
    }
    return (APBDropTarget){ .exists = NO };
}

@end
