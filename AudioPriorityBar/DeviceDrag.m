#import "DeviceDrag.h"

const CGFloat APBDeviceRowHeight = 30;
const CGFloat APBDeviceRowSpacing = 3;
const CGFloat APBDeviceRowPitch = 33;
const CGFloat APBDeviceSectionHeaderHeight = 18;

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

@implementation APBDropTarget

+ (instancetype)targetWithSection:(APBDeviceSection)section index:(NSInteger)index {
    APBDropTarget *target = [[self alloc] init];
    target->_section = section;
    target->_index = index;
    return target;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBDropTarget.class]) return NO;
    APBDropTarget *other = object;
    return _section == other.section && _index == other.index;
}

- (NSUInteger)hash {
    return (NSUInteger)(_section << 16 ^ _index);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<target section %ld index %ld>", (long)_section, (long)_index];
}

@end

@implementation APBDeviceDrag

- (instancetype)initWithDevice:(APBAudioDevice *)device section:(APBDeviceSection)section index:(NSInteger)index {
    if ((self = [super init])) {
        _device = device;
        _section = section;
        _index = index;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    APBDeviceDrag *copy = [[APBDeviceDrag alloc] initWithDevice:_device section:_section index:_index];
    copy.target = _target;
    copy.translation = _translation;
    copy.isForbidden = _isForbidden;
    return copy;
}

- (void)updateHovered:(APBDropTarget *)hovered translation:(CGSize)translation {
    _translation = translation;
    _isForbidden = hovered ? APBDeviceSectionRole(hovered.section) != _device.role : NO;
    _target = _isForbidden ? nil : hovered;
}

@end

@implementation APBPanelLayout

+ (CGFloat)sectionGap { return 16; }
+ (CGFloat)separatorInset { return 8; }
+ (CGFloat)horizontalPadding { return 12; }
+ (CGFloat)topPadding { return self.sectionGap - self.separatorInset; }
+ (CGFloat)bottomPadding { return 8; }

- (instancetype)initWithSections:(NSArray<NSArray<NSNumber *> *> *)sections {
    if ((self = [super init])) _sections = [sections copy];
    return self;
}

static APBDeviceSection SectionAt(NSArray<NSArray<NSNumber *> *> *sections, NSUInteger index) {
    return sections[index][0].integerValue;
}

static NSInteger CountAt(NSArray<NSArray<NSNumber *> *> *sections, NSUInteger index) {
    return sections[index][1].integerValue;
}

- (NSUInteger)indexOf:(APBDeviceSection)section {
    for (NSUInteger index = 0; index < _sections.count; index++) {
        if (SectionAt(_sections, index) == section) return index;
    }
    return NSNotFound;
}

+ (NSInteger)insertionIndexForY:(CGFloat)y rowCount:(NSInteger)rowCount {
    CGFloat top = APBDeviceSectionHeaderHeight + APBDeviceRowSpacing;
    CGFloat gap = round((y - top) / APBDeviceRowPitch);
    return MAX(0, MIN(rowCount, (NSInteger)gap));
}

- (CGFloat)height:(NSInteger)count {
    return APBDeviceSectionHeaderHeight + (CGFloat)MAX(count, 1) * APBDeviceRowPitch;
}

/// An empty list still reserves a placeholder row, so giving up a last
/// device, or taking a first one, changes no height.
- (CGFloat)shrink:(NSInteger)count {
    return [self height:MAX(count - 1, 0)] - [self height:count];
}

- (CGFloat)grow:(NSInteger)count {
    return [self height:count + 1] - [self height:count];
}

- (CGFloat)contentHeight {
    CGFloat height = APBPanelLayout.topPadding + APBPanelLayout.bottomPadding
        + (CGFloat)MAX((NSInteger)_sections.count - 1, 0) * APBPanelLayout.sectionGap;
    for (NSUInteger index = 0; index < _sections.count; index++) {
        height += [self height:CountAt(_sections, index)];
    }
    return height;
}

- (CGFloat)sectionTopOf:(APBDeviceSection)section {
    CGFloat top = APBPanelLayout.topPadding;
    for (NSUInteger index = 0; index < _sections.count; index++) {
        if (SectionAt(_sections, index) == section) return top;
        top += [self height:CountAt(_sections, index)] + APBPanelLayout.sectionGap;
    }
    return NAN;
}

- (CGFloat)contentTopOf:(APBDeviceSection)section {
    return [self sectionTopOf:section] + APBDeviceSectionHeaderHeight + APBDeviceRowSpacing;
}

- (CGFloat)sectionOffsetFor:(APBDeviceSection)section drag:(APBDeviceDrag *)drag {
    APBDropTarget *target = drag.target;
    if (!target || target.section == drag.section) return 0;
    NSUInteger sourceIndex = [self indexOf:drag.section];
    NSUInteger targetIndex = [self indexOf:target.section];
    NSUInteger sectionIndex = [self indexOf:section];
    if (sourceIndex == NSNotFound || targetIndex == NSNotFound || sectionIndex == NSNotFound) return 0;
    CGFloat offset = 0;
    if (sourceIndex < sectionIndex) offset += [self shrink:CountAt(_sections, sourceIndex)];
    if (targetIndex < sectionIndex) offset += [self grow:CountAt(_sections, targetIndex)];
    return offset;
}

- (CGFloat)heightDeltaFor:(APBDeviceDrag *)drag {
    APBDropTarget *target = drag.target;
    if (!target || target.section == drag.section) return 0;
    NSUInteger source = [self indexOf:drag.section];
    NSUInteger destination = [self indexOf:target.section];
    if (source == NSNotFound || destination == NSNotFound) return 0;
    return [self shrink:CountAt(_sections, source)] + [self grow:CountAt(_sections, destination)];
}

- (CGFloat)rowOffsetAt:(NSInteger)index in:(APBDeviceSection)section drag:(APBDeviceDrag *)drag {
    APBDropTarget *target = drag.target;
    if (!target) return 0;
    CGFloat offset = 0;
    if (drag.section == section && index > drag.index) offset -= APBDeviceRowPitch;
    if (target.section == section && index >= target.index) offset += APBDeviceRowPitch;
    return offset;
}

- (CGSize)liftedOffsetFor:(APBDeviceDrag *)drag {
    APBDropTarget *target = drag.target;
    CGFloat sourceTop = [self contentTopOf:drag.section];
    CGFloat targetTop = target ? [self contentTopOf:target.section] : NAN;
    if (!target || isnan(sourceTop) || isnan(targetTop)) {
        return CGSizeMake(0, drag.translation.height);
    }
    CGFloat sourceY = sourceTop + (CGFloat)drag.index * APBDeviceRowPitch
        + [self sectionOffsetFor:drag.section drag:drag];
    NSInteger targetIndex = target.index;
    if (target.section == drag.section && targetIndex > drag.index) targetIndex -= 1;
    CGFloat targetY = targetTop + [self sectionOffsetFor:target.section drag:drag]
        + (CGFloat)targetIndex * APBDeviceRowPitch;
    return CGSizeMake(0, targetY - sourceY);
}

- (APBDropTarget *)targetAt:(CGPoint)point {
    CGFloat top = APBPanelLayout.topPadding;
    for (NSUInteger index = 0; index < _sections.count; index++) {
        NSInteger count = CountAt(_sections, index);
        CGFloat bottom = top + [self height:count] + APBPanelLayout.sectionGap;
        if (point.y < bottom) {
            return [APBDropTarget targetWithSection:SectionAt(_sections, index)
                                              index:[APBPanelLayout insertionIndexForY:point.y - top rowCount:count]];
        }
        top = bottom;
    }
    return nil;
}

@end
