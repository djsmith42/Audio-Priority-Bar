#import "DeviceListView.h"
#import "AppModel+Private.h"
#import "DeviceDrag.h"
#import "UIHelpers.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat DragThreshold = 8;

/// One list's fixed parts: its heading, empty placeholder and separator.
@interface APBListSection : NSObject
@property (nonatomic) APBDeviceSection section;
@property (nonatomic, copy) NSArray<APBAudioDevice *> *devices;
@property (nonatomic, nullable) NSNumber *currentID;
@property (nonatomic) NSTextField *title;
@property (nonatomic) APBFillView *empty;
@property (nonatomic) NSTextField *emptyLabel;
@property (nonatomic, nullable) APBSeparatorView *separator;
@end

@implementation APBListSection
@end

@implementation APBDeviceListView {
    APBAppModel *_model;
    NSArray<APBListSection *> *_sections;
    NSMutableDictionary<NSString *, APBDeviceRowView *> *_rows;
    APBPanelLayout *_layout;
    APBDeviceDrag *_drag;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 380, 200)])) {
        _model = model;
        _rows = [NSMutableDictionary dictionary];
        NSArray *titles = @[@"Speakers", @"Headphones", @"Microphones"];
        NSArray *empties = @[@"No speakers shown", @"No headphones shown", @"No microphones shown"];
        NSMutableArray *sections = [NSMutableArray array];
        for (NSInteger index = 0; index < 3; index++) {
            APBListSection *section = [[APBListSection alloc] init];
            section.section = (APBDeviceSection)index;
            section.title = APBLabel(titles[index], [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                     NSColor.secondaryLabelColor);
            section.title.accessibilityRole = NSAccessibilityStaticTextRole;
            section.empty = [[APBFillView alloc] init];
            section.empty.cornerRadius = 8;
            NSFont *italic = [NSFontManager.sharedFontManager convertFont:[NSFont systemFontOfSize:APBCalloutSize]
                                                              toHaveTrait:NSItalicFontMask];
            section.emptyLabel = APBLabel(empties[index], italic, NSColor.tertiaryLabelColor);
            [section.empty addSubview:section.emptyLabel];
            [self addSubview:section.title];
            [self addSubview:section.empty];
            // Draws a separator in the gap above every list but the first.
            if (index > 0) {
                section.separator = [[APBSeparatorView alloc] init];
                [self addSubview:section.separator];
            }
            [sections addObject:section];
        }
        _sections = sections;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setHighlightedPairedDeviceID:(NSString *)highlightedPairedDeviceID {
    _highlightedPairedDeviceID = [highlightedPairedDeviceID copy];
    for (APBDeviceRowView *row in _rows.allValues) [row refreshHighlight];
}

- (CGFloat)contentHeight {
    CGFloat growth = _drag ? MAX(0, [_layout heightDeltaFor:_drag]) : 0;
    return _layout.contentHeight + growth;
}

- (APBListSection *)sectionFor:(APBDeviceSection)section {
    return _sections[(NSUInteger)section];
}

#pragma mark - Loading

- (void)reload {
    [self sectionFor:APBDeviceSectionSpeaker].devices = _model.speakerDevices;
    [self sectionFor:APBDeviceSectionHeadphone].devices = _model.headphoneDevices;
    [self sectionFor:APBDeviceSectionInput].devices = _model.inputDevices;
    [self sectionFor:APBDeviceSectionSpeaker].currentID = _model.currentOutputID;
    [self sectionFor:APBDeviceSectionHeadphone].currentID = _model.currentOutputID;
    [self sectionFor:APBDeviceSectionInput].currentID = _model.currentInputID;

    NSMutableArray *counts = [NSMutableArray array];
    NSMutableSet<NSString *> *rendered = [NSMutableSet set];
    for (APBListSection *section in _sections) {
        [counts addObject:@[@(section.section), @(section.devices.count)]];
        NSInteger count = (NSInteger)section.devices.count;
        [section.devices enumerateObjectsUsingBlock:^(APBAudioDevice *device, NSUInteger index, BOOL *stop) {
            APBDeviceRowView *row = self->_rows[device.identifier];
            if (!row) {
                row = [[APBDeviceRowView alloc] initWithModel:self->_model];
                row.host = self;
                self->_rows[device.identifier] = row;
                [self addSubview:row];
            }
            [row configureWithDevice:device
                               index:(NSInteger)index
                               count:count
                          isSelected:device.isConnected && APBIDIs(section.currentID, device.platformID)
                            category:APBDeviceSectionCategory(section.section)];
            [rendered addObject:device.identifier];
        }];
    }
    for (NSString *identifier in _rows.allKeys) {
        if ([rendered containsObject:identifier]) continue;
        [_rows[identifier] removeFromSuperview];
        [_rows removeObjectForKey:identifier];
    }
    _layout = [[APBPanelLayout alloc] initWithSections:counts];
    if (_drag && ![rendered containsObject:_drag.device.identifier]) _drag = nil;
    // A row removed while hovered never reports the pointer leaving, so its
    // partner's highlight would outlive both rows.
    if (_highlightedPairedDeviceID && ![rendered containsObject:_highlightedPairedDeviceID]) {
        self.highlightedPairedDeviceID = nil;
    }
    [self layoutContentAnimated:NO];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutContentAnimated:NO];
}

#pragma mark - Layout

- (void)layoutContentAnimated:(BOOL)animated {
    if (!_layout) return;
    CGFloat width = NSWidth(self.bounds);
    CGFloat inset = APBPanelLayout.horizontalPadding;
    CGFloat contentWidth = width - inset * 2;
    NSMutableDictionary<NSValue *, NSValue *> *frames = [NSMutableDictionary dictionary];
    void (^place)(NSView *, NSRect) = ^(NSView *view, NSRect frame) {
        frames[[NSValue valueWithNonretainedObject:view]] = [NSValue valueWithRect:frame];
    };
    __block APBDeviceRowView *liftedRow = nil;
    for (APBListSection *section in _sections) {
        CGFloat offset = _drag ? [_layout sectionOffsetFor:section.section drag:_drag] : 0;
        CGFloat top = [_layout sectionTopOf:section.section] + offset;
        CGFloat contentTop = [_layout contentTopOf:section.section] + offset;
        place(section.title, NSMakeRect(inset, top, contentWidth, APBDeviceSectionHeaderHeight));
        if (section.separator) {
            place(section.separator, NSMakeRect(inset, top + APBPanelLayout.separatorInset - APBPanelLayout.sectionGap,
                                                contentWidth, 1));
        }
        BOOL isEmpty = section.devices.count == 0;
        section.empty.hidden = !isEmpty;
        BOOL isTargeted = _drag.target.section == section.section && _drag.target != nil;
        section.empty.fillColor = isTargeted ? [NSColor.controlAccentColor colorWithAlphaComponent:0.12] : nil;
        // Overhangs the text like a row's highlight does.
        place(section.empty, NSMakeRect(inset - 8, contentTop, contentWidth + 16, APBDeviceRowHeight));
        NSSize labelSize = section.emptyLabel.intrinsicContentSize;
        section.emptyLabel.frame = NSMakeRect(8, (APBDeviceRowHeight - labelSize.height) / 2,
                                              MIN(labelSize.width, contentWidth), labelSize.height);
        [section.devices enumerateObjectsUsingBlock:^(APBAudioDevice *device, NSUInteger index, BOOL *stop) {
            APBDeviceRowView *row = self->_rows[device.identifier];
            BOOL lifted = self->_drag && [self->_drag.device.identifier isEqualToString:device.identifier];
            row.isLifted = lifted;
            row.isForbidden = lifted && self->_drag.isForbidden;
            CGFloat y = contentTop + (CGFloat)index * APBDeviceRowPitch;
            if (lifted) {
                // The lifted row snaps into the target gap, or follows the
                // pointer while there is none.
                y += [self->_layout liftedOffsetFor:self->_drag].height;
            } else if (self->_drag) {
                // The rest close the source gap and open the destination gap.
                y += [self->_layout rowOffsetAt:(NSInteger)index in:section.section drag:self->_drag];
            }
            NSRect frame = NSMakeRect(inset - 8, y, contentWidth + 16, APBDeviceRowHeight);
            if (lifted) {
                liftedRow = row;
                row.frame = frame;
            } else {
                place(row, frame);
            }
        }];
    }
    if (liftedRow) [self addSubview:liftedRow positioned:NSWindowAbove relativeTo:nil];
    void (^apply)(void) = ^{
        for (NSValue *key in frames) {
            NSView *view = key.nonretainedObjectValue;
            NSRect frame = frames[key].rectValue;
            if (!NSEqualRects(view.frame, frame)) (animated ? view.animator : view).frame = frame;
        }
    };
    if (animated && !APBReduceMotion()) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1];
            apply();
        }];
    } else {
        apply();
    }
}

#pragma mark - APBDeviceRowHost

- (APBDeviceSection)sectionOfRow:(APBDeviceRowView *)row {
    for (APBListSection *section in _sections) {
        for (APBAudioDevice *device in section.devices) {
            if ([device.identifier isEqualToString:row.device.identifier]) return section.section;
        }
    }
    return APBDeviceSectionInput;
}

- (void)row:(APBDeviceRowView *)row moveTo:(NSInteger)target {
    NSInteger source = row.index;
    if (source == target) return;
    NSInteger destination = target > source ? target + 1 : target;
    NSIndexSet *offsets = [NSIndexSet indexSetWithIndex:(NSUInteger)source];
    APBOutputCategory category = APBDeviceSectionCategory([self sectionOfRow:row]);
    if (category != APBOutputCategoryNone) {
        [_model moveOutputIn:category from:offsets to:destination];
    } else {
        [_model moveInputFrom:offsets to:destination];
    }
}

/// Follows the pointer until it is released: a short press selects the
/// device, and a drag of a few points lifts the row.
- (void)row:(APBDeviceRowView *)row mouseDown:(NSEvent *)event {
    NSPoint start = [self convertPoint:event.locationInWindow fromView:nil];
    APBDeviceSection section = [self sectionOfRow:row];
    BOOL dragging = NO;
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (!next) break;
        NSPoint point = [self convertPoint:next.locationInWindow fromView:nil];
        if (next.type == NSEventTypeLeftMouseUp) break;
        CGSize translation = CGSizeMake(point.x - start.x, point.y - start.y);
        if (!dragging && hypot(translation.width, translation.height) >= DragThreshold) {
            dragging = YES;
            _drag = [[APBDeviceDrag alloc] initWithDevice:row.device section:section index:row.index];
        }
        if (!dragging) continue;
        APBDropTarget *previousTarget = _drag.target;
        CGFloat previousHeight = self.contentHeight;
        [_drag updateHovered:[_layout targetAt:point] translation:translation];
        BOOL targetChanged = !(previousTarget == _drag.target || [previousTarget isEqual:_drag.target]);
        [self layoutContentAnimated:targetChanged];
        if (self.contentHeight != previousHeight && _onHeightChange) _onHeightChange();
    }
    if (!dragging) {
        if (row.isSelectable) [row selectDevice];
        return;
    }
    APBDeviceDrag *finished = _drag;
    _drag = nil;
    if (finished.target) {
        [_model dropDevice:finished.device.identifier
                      into:APBDeviceSectionCategory(finished.target.section)
                        at:finished.target.index];
    }
    [self reload];
    if (_onHeightChange) _onHeightChange();
}

- (void)cancelDrag {
    if (!_drag) return;
    _drag = nil;
    [self layoutContentAnimated:NO];
    if (_onHeightChange) _onHeightChange();
}

@end
