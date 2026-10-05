#import "APBDeviceRowView.h"
#import "APBDeviceIcon.h"

/// One status beside a device's name.
@interface APBRowStatus : NSObject
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *text;
/// Carried with the value so restyling never depends on matching copy.
@property (nonatomic) NSColor *tint;
/// Read aloud and shown on hover instead of `text` when the glyph carries
/// meaning the text alone does not.
@property (nonatomic, copy, nullable) NSString *spokenText;
@property (nonatomic, readonly) NSString *summary;
@end

@implementation APBRowStatus

+ (instancetype)icon:(NSString *)icon text:(NSString *)text tint:(NSColor *)tint {
    APBRowStatus *status = [[self alloc] init];
    status.icon = icon;
    status.text = text;
    status.tint = tint;
    return status;
}

- (NSString *)summary {
    return _spokenText ?: _text;
}

@end

/// A small capsule button, used for the row's selection override.
@interface APBPillButton : APBHoverView
@property (nonatomic, readonly) NSTextField *label;
@end

@implementation APBPillButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.isCapsule = YES;
        self.fillColor = APBPrimary(0.06);
        _label = APBLabel(@"", [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:18],
        ]];
        [_label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
    }
    return self;
}

- (BOOL)accessibilityPerformPress {
    if (self.onClick) self.onClick();
    return YES;
}

@end

@interface APBDeviceRowView ()
@property (nonatomic, readwrite) APBAudioDevice *device;
@end

@implementation APBDeviceRowView {
    APBAppModel *_model;
    __weak id<APBDeviceRowDelegate> _delegate;
    NSInteger _count;
    BOOL _isSelected;

    APBFillView *_background;
    NSTextField *_number;
    NSImageView *_handle;
    APBFillView *_iconCircle;
    NSImageView *_icon;
    NSTextField *_name;
    NSTextField *_statuses;
    NSStackView *_controls;
    APBPillButton *_pill;
    NSButton *_actions;
    NSImageView *_forbidden;

    BOOL _isHoveringSelectionOverride;
    NSString *_highlightedPartnerID;
    dispatch_block_t _pillAction;
    NSPoint _dragStart;
    BOOL _isDragging;
    BOOL _isMouseDown;
}

- (instancetype)initWithModel:(APBAppModel *)model delegate:(id<APBDeviceRowDelegate>)delegate {
    self = [super initWithFrame:NSMakeRect(0, 0, 372, APBRowHeight)];
    if (self) {
        _model = model;
        _delegate = delegate;
        [self build];
        __weak typeof(self) weakSelf = self;
        self.onHover = ^(BOOL hovering) {
            [weakSelf hoverChanged:hovering];
        };
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(voiceOverChanged:)
                                                   name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                 object:nil];
        [NSWorkspace.sharedWorkspace addObserver:self forKeyPath:@"voiceOverEnabled" options:0 context:NULL];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace removeObserver:self forKeyPath:@"voiceOverEnabled"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refresh];
    });
}

- (void)voiceOverChanged:(NSNotification *)notification {
    [self refresh];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)build {
    _background = [[APBFillView alloc] initWithFrame:self.bounds];
    _background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _background.cornerRadius = 8;
    [self addSubview:_background];

    // The priority number gives way to the drag handle while the row is
    // hovered or dragged.
    NSView *handleZone = [[NSView alloc] init];
    handleZone.translatesAutoresizingMaskIntoConstraints = NO;
    NSFont *caption = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightSemibold];
    _number = APBLabel(@"", caption, NSColor.secondaryLabelColor);
    _number.translatesAutoresizingMaskIntoConstraints = NO;
    _handle = [NSImageView imageViewWithImage:APBSymbol(@"line.3.horizontal", 11, NSFontWeightMedium)];
    _handle.translatesAutoresizingMaskIntoConstraints = NO;
    _handle.contentTintColor = NSColor.secondaryLabelColor;
    [handleZone addSubview:_number];
    [handleZone addSubview:_handle];
    [NSLayoutConstraint activateConstraints:@[
        [handleZone.widthAnchor constraintEqualToConstant:14],
        [_number.leadingAnchor constraintEqualToAnchor:handleZone.leadingAnchor],
        [_number.centerYAnchor constraintEqualToAnchor:handleZone.centerYAnchor],
        [_handle.leadingAnchor constraintEqualToAnchor:handleZone.leadingAnchor],
        [_handle.centerYAnchor constraintEqualToAnchor:handleZone.centerYAnchor],
    ]];

    _iconCircle = [[APBFillView alloc] init];
    _iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    _iconCircle.isCapsule = YES;
    _icon = [[NSImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    [_iconCircle addSubview:_icon];
    [NSLayoutConstraint activateConstraints:@[
        [_iconCircle.widthAnchor constraintEqualToConstant:26],
        [_iconCircle.heightAnchor constraintEqualToConstant:26],
        [_icon.centerXAnchor constraintEqualToAnchor:_iconCircle.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor],
    ]];

    _name = APBLabel(@"", [NSFont systemFontOfSize:13], NSColor.labelColor);
    [_name setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_name setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    _statuses = APBLabel(@"", [NSFont systemFontOfSize:10], NSColor.secondaryLabelColor);
    [_statuses setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_statuses setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *info = [NSStackView stackViewWithViews:@[ _iconCircle, _name, _statuses ]];
    info.spacing = 8;
    info.alignment = NSLayoutAttributeCenterY;
    info.detachesHiddenViews = YES;
    [info setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [info setClippingResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    _pill = [[APBPillButton alloc] init];
    __weak typeof(self) weakSelf = self;
    _pill.onClick = ^{
        typeof(self) self = weakSelf;
        if (self && self->_pillAction) self->_pillAction();
    };
    _pill.onHover = ^(BOOL hovering) {
        [weakSelf pillHoverChanged:hovering];
    };

    _actions = [NSButton buttonWithImage:APBSymbol(@"ellipsis.circle", 13, NSFontWeightRegular) target:self action:@selector(showActions:)];
    _actions.bordered = NO;
    _actions.translatesAutoresizingMaskIntoConstraints = NO;
    _actions.contentTintColor = NSColor.secondaryLabelColor;
    [NSLayoutConstraint activateConstraints:@[
        [_actions.widthAnchor constraintEqualToConstant:28],
        [_actions.heightAnchor constraintEqualToConstant:28],
    ]];

    _controls = [NSStackView stackViewWithViews:@[ _pill, _actions ]];
    _controls.spacing = 6;
    _controls.detachesHiddenViews = YES;
    _controls.wantsLayer = YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[ handleZone, info, _controls ]];
    row.spacing = 6;
    row.alignment = NSLayoutAttributeCenterY;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setCustomSpacing:6 afterView:handleZone];
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        // The handle sits 4 points in from the 8-point inset.
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [handleZone.heightAnchor constraintEqualToConstant:APBRowHeight],
    ]];

    _forbidden = [NSImageView imageViewWithImage:APBColoredSymbol(@"nosign", 16, NSFontWeightSemibold, NSColor.systemRedColor)];
    _forbidden.frame = NSMakeRect(0, 0, 22, 22);
    _forbidden.wantsLayer = YES;
    _forbidden.layer.cornerRadius = 11;
    _forbidden.layer.backgroundColor = [NSColor.windowBackgroundColor colorWithAlphaComponent:0.9].CGColor;
    _forbidden.hidden = YES;
    [self addSubview:_forbidden];

    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityGroupRole];
}

- (void)layout {
    [super layout];
    // Overhangs the top-trailing corner like a badge.
    _forbidden.frame = NSMakeRect(NSWidth(self.bounds) - 17, -5, 22, 22);
}

#pragma mark State

- (void)updateDevice:(APBAudioDevice *)device
               index:(NSInteger)index
               count:(NSInteger)count
          isSelected:(BOOL)isSelected
             section:(APBDeviceSection)section {
    _device = device;
    _index = index;
    _count = count;
    _isSelected = isSelected;
    _section = section;
    [self refresh];
}

- (APBOutputCategory)category {
    return APBDeviceSectionCategory(_section);
}

- (APBLinkState)linkState {
    return [_model linkStateForDevice:_device];
}

- (BOOL)isUnavailable {
    return self.linkState == APBLinkStateDown;
}

- (APBAudioDevice *)pairedDevice {
    return [_model pairedDeviceFor:_device];
}

/// Whether this device and its pair are both currently selected, so
/// selecting them together has nothing left to do.
- (BOOL)areBothDevicesSelected {
    APBAudioDevice *paired = self.pairedDevice;
    if (!paired) return NO;
    BOOL pairedIsCurrent = paired.role == APBDeviceRoleInput
        ? _model.currentInputID == paired.platformID
        : _model.currentOutputID == paired.platformID;
    return _isSelected && pairedIsCurrent;
}

/// Whether the paired device is connected and not link-down, so selecting it
/// could actually take effect.
- (BOOL)isPairedDeviceUsable {
    APBAudioDevice *paired = self.pairedDevice;
    if (!paired) return NO;
    return _device.isConnected && !self.isUnavailable && [_model linkStateForDevice:paired] != APBLinkStateDown;
}

- (NSString *)selectionOverrideHelp {
    if (_model.selectsPairedDevice) {
        return _device.role == APBDeviceRoleInput
            ? @"Select only this microphone, not its output"
            : @"Select only this output, not its microphone";
    }
    return [NSString stringWithFormat:@"Use %@ for input and output", _device.name];
}

- (NSArray<APBRowStatus *> *)statuses {
    NSMutableArray *result = [NSMutableArray array];
    APBLinkState linkState = self.linkState;
    if (_isSelected && self.isUnavailable) {
        [result addObject:[APBRowStatus icon:@"exclamationmark.circle" text:@"Current" tint:NSColor.systemOrangeColor]];
    }
    if (!_device.isConnected) {
        NSString *seen = [[_model.store storedDeviceWithUID:_device.uid role:_device.role] relativeLastSeen];
        NSString *text = seen ? [NSString stringWithFormat:@"Disconnected · Last seen %@", seen] : @"Disconnected";
        [result addObject:[APBRowStatus icon:@"wifi.slash" text:text tint:NSColor.secondaryLabelColor]];
    }
    // The antenna-slash glyph means a proven verdict, so it belongs to `Down`
    // alone: that state dims the row and blocks selection, while the states
    // below leave the device selectable. `Checking` shows nothing at all
    // because it settles in tens of milliseconds and would only flicker;
    // automatic selection still waits for it internally.
    if (linkState == APBLinkStateDown) {
        [result addObject:[APBRowStatus icon:@"antenna.radiowaves.left.and.right.slash" text:@"Headset off" tint:NSColor.systemOrangeColor]];
    } else if (linkState == APBLinkStateUnknown) {
        [result addObject:[APBRowStatus icon:@"questionmark.circle" text:@"Link unknown" tint:NSColor.secondaryLabelColor]];
    } else if (linkState == APBLinkStateMonitoringUnavailable) {
        [result addObject:[APBRowStatus icon:@"questionmark.circle" text:@"Link status unavailable" tint:NSColor.secondaryLabelColor]];
    }
    if ([_model isHidden:_device]) {
        [result addObject:[APBRowStatus icon:@"eye.slash" text:@"Hidden" tint:NSColor.secondaryLabelColor]];
    }
    if ([_model isMuted:_device]) {
        NSString *icon = _device.role == APBDeviceRoleInput ? @"mic.slash.fill" : @"speaker.slash.fill";
        [result addObject:[APBRowStatus icon:icon text:@"Muted" tint:NSColor.systemRedColor]];
    }
    for (APBBatteryBadge *badge in [_model batteryLevelsForDevice:_device].badges) {
        APBRowStatus *status = [APBRowStatus icon:badge.icon
                                             text:badge.text
                                             tint:badge.isLow ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor];
        status.spokenText = badge.spokenText;
        [result addObject:status];
    }
    return result;
}

- (BOOL)isHighlightedPairedDevice {
    return [_delegate.highlightedPairedDeviceID isEqualToString:_device.identifier];
}

/// The selection override and actions menu appear only on hover, like the
/// system's own lists, but stay visible to VoiceOver, which has no pointer to
/// hover with.
- (BOOL)showsRowControls {
    return self.isHovering || NSWorkspace.sharedWorkspace.isVoiceOverEnabled;
}

- (void)refresh {
    if (!_device) return;
    BOOL isNeverUse = [_model isNeverUse:_device];
    BOOL isUnavailable = self.isUnavailable;
    BOOL animates = !APBReduceMotion();

    _number.stringValue = [NSString stringWithFormat:@"%ld", (long)_index + 1];
    BOOL showsHandle = self.isHovering || _isLifted;
    [self fade:_number to:showsHandle ? 0 : 1 animated:animates];
    [self fade:_handle to:showsHandle ? 1 : 0 animated:animates];

    // Orange rather than the accent while the current device is unavailable,
    // matching its "Current" status.
    NSColor *selectionTint = isUnavailable ? NSColor.systemOrangeColor : NSColor.controlAccentColor;
    _iconCircle.fillColor = _isSelected ? selectionTint : APBPrimary(0.1);
    _icon.image = APBSymbol([_device hardwareIconForCategory:self.category], 12, NSFontWeightRegular);
    _icon.contentTintColor = _isSelected ? NSColor.whiteColor : NSColor.secondaryLabelColor;

    NSColor *nameColor = !_device.isConnected || isUnavailable || isNeverUse
        ? NSColor.secondaryLabelColor
        : NSColor.labelColor;
    NSMutableDictionary *attributes = [@{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: nameColor,
    } mutableCopy];
    if (isNeverUse) {
        attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        attributes[NSStrikethroughColorAttributeName] = NSColor.secondaryLabelColor;
    }
    NSMutableParagraphStyle *truncating = [[NSMutableParagraphStyle alloc] init];
    truncating.lineBreakMode = NSLineBreakByTruncatingTail;
    attributes[NSParagraphStyleAttributeName] = truncating;
    _name.attributedStringValue = [[NSAttributedString alloc] initWithString:_device.name attributes:attributes];
    _name.toolTip = isNeverUse ? [NSString stringWithFormat:@"%@ · Never auto-select", _device.name] : _device.name;

    NSArray<APBRowStatus *> *statuses = self.statuses;
    _statuses.hidden = statuses.count == 0;
    _statuses.attributedStringValue = [self attributedStatuses:statuses];
    _statuses.toolTip = [[statuses valueForKey:@"summary"] componentsJoinedByString:@" · "];

    [self refreshSelectionOverride];
    _actions.toolTip = nil;
    [_actions setAccessibilityLabel:[NSString stringWithFormat:@"Actions for %@", _device.name]];
    BOOL showsControls = self.showsRowControls;
    // Faded rather than removed, so the name keeps its width and does not
    // reflow as the pointer crosses rows.
    [self fade:_controls to:showsControls ? 1 : 0 animated:animates];
    _actions.enabled = showsControls;

    _background.fillColor = _isLifted
        ? NSColor.controlBackgroundColor
        : (self.isHovering || self.isHighlightedPairedDevice ? APBPrimary(0.06) : NSColor.clearColor);
    [self applyLift];
    _forbidden.hidden = !(_isLifted && _isForbidden);

    [self setAccessibilityLabel:_device.name];
    [self setAccessibilityValue:[self accessibilityValueWithStatuses:statuses neverUse:isNeverUse unavailable:isUnavailable]];
    [self setAccessibilityHelp:self.accessibilityHint];
    [self setAccessibilitySelected:_isSelected];
    [self setAccessibilityCustomActions:@[
        [[NSAccessibilityCustomAction alloc] initWithName:@"Move Up" target:self selector:@selector(accessibilityMoveUp)],
        [[NSAccessibilityCustomAction alloc] initWithName:@"Move Down" target:self selector:@selector(accessibilityMoveDown)],
    ]];
}

- (void)fade:(NSView *)view to:(CGFloat)alpha animated:(BOOL)animated {
    if (view.alphaValue == alpha) return;
    if (!animated || !self.window) {
        view.alphaValue = alpha;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.12;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        view.animator.alphaValue = alpha;
    }];
}

- (NSAttributedString *)attributedStatuses:(NSArray<APBRowStatus *> *)statuses {
    NSFont *font = [NSFont systemFontOfSize:10];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [statuses enumerateObjectsUsingBlock:^(APBRowStatus *status, NSUInteger index, BOOL *stop) {
        if (index > 0) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{
                NSFontAttributeName: font,
                // Widens the gap between statuses to 8 points.
                NSKernAttributeName: @6,
            }]];
        }
        NSImage *image = APBColoredSymbol(status.icon, 10, NSFontWeightRegular, status.tint);
        if (image) {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = image;
            CGFloat y = round((font.capHeight - image.size.height) / 2);
            attachment.bounds = NSMakeRect(0, y, image.size.width, image.size.height);
            [result appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            // Matches the gap SwiftUI's `Label` leaves after its icon. Kerning
            // is ignored after an attachment, so a sized gap stands in.
            NSTextAttachment *gap = [[NSTextAttachment alloc] init];
            gap.bounds = NSMakeRect(0, 0, 4, 1);
            [result appendAttributedString:[NSAttributedString attributedStringWithAttachment:gap]];
        }
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:status.text attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: status.tint,
        }]];
    }];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [result addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, result.length)];
    return result;
}

- (void)applyLift {
    BOOL lifted = _isLifted;
    self.layer.shadowColor = NSColor.blackColor.CGColor;
    self.layer.shadowOpacity = lifted ? 0.28 : 0;
    self.layer.shadowRadius = lifted ? 10 : 0;
    // The row is flipped, so a positive offset still drops the shadow down.
    self.layer.shadowOffset = CGSizeMake(0, lifted ? -5 : 0);
    self.layer.masksToBounds = NO;
}

#pragma mark Selection override

/// The override for the current default: offers to select only this device
/// while both are normally selected together, or to select both while only
/// one is. Shown only while it would change something, so a row whose pair is
/// already in the target state, unavailable, or absent keeps the layout it
/// had before.
- (void)refreshSelectionOverride {
    APBAudioDevice *paired = self.pairedDevice;
    NSString *label = nil;
    APBAppModel *model = _model;
    APBAudioDevice *device = _device;
    if (paired && self.isPairedDeviceUsable) {
        if (_model.selectsPairedDevice) {
            if (!_isSelected) {
                label = _device.role == APBDeviceRoleInput ? @"Mic only" : @"Output only";
                _pillAction = ^{ [model selectOnly:device]; };
            }
        } else if (!self.areBothDevicesSelected) {
            label = @"Use both";
            _pillAction = ^{ [model selectWithPairedDevice:device]; };
        }
    }
    if (!label) {
        _pillAction = nil;
        _pill.hidden = YES;
        if (_isHoveringSelectionOverride) {
            _isHoveringSelectionOverride = NO;
        }
        return;
    }
    _pill.hidden = NO;
    _pill.label.stringValue = label;
    _pill.fillColor = APBPrimary(_isHoveringSelectionOverride ? 0.12 : 0.06);
    _pill.toolTip = self.selectionOverrideHelp;
    [_pill setAccessibilityLabel:self.selectionOverrideHelp];
}

- (void)pillHoverChanged:(BOOL)hovering {
    _isHoveringSelectionOverride = hovering;
    _pill.fillColor = APBPrimary(hovering ? 0.12 : 0.06);
    APBAudioDevice *partner = self.pairedDevice;
    if (!partner) return;
    id<APBDeviceRowDelegate> delegate = _delegate;
    if (_model.selectsPairedDevice) {
        // This override selects only the hovered device, so suppress the
        // partner highlight while hovering it, and restore it when returning
        // to the row, which still selects both.
        if (hovering) {
            if ([delegate.highlightedPairedDeviceID isEqualToString:partner.identifier]) {
                delegate.highlightedPairedDeviceID = nil;
            }
        } else if (self.isHovering && !_isSelected) {
            _highlightedPartnerID = partner.identifier;
            delegate.highlightedPairedDeviceID = partner.identifier;
        }
    } else if (hovering) {
        // "Use both" is the only control that selects the partner while
        // selecting one device at a time is the default.
        delegate.highlightedPairedDeviceID = partner.identifier;
    } else if ([delegate.highlightedPairedDeviceID isEqualToString:partner.identifier]) {
        delegate.highlightedPairedDeviceID = nil;
    }
}

- (void)hoverChanged:(BOOL)hovering {
    id<APBDeviceRowDelegate> delegate = _delegate;
    if (!hovering) {
        if (_highlightedPartnerID == delegate.highlightedPairedDeviceID
            || [delegate.highlightedPairedDeviceID isEqualToString:_highlightedPartnerID]) {
            delegate.highlightedPairedDeviceID = nil;
        }
        _highlightedPartnerID = nil;
        // The override cannot still be hovered once the pointer has left the
        // row, and it reports nothing when selecting a device stops it being
        // rendered at all.
        _isHoveringSelectionOverride = NO;
        [self refresh];
        return;
    }
    APBAudioDevice *paired = self.pairedDevice;
    if (_model.selectsPairedDevice && self.isPairedDeviceUsable && !_isSelected
        && !_isHoveringSelectionOverride && paired) {
        _highlightedPartnerID = paired.identifier;
        delegate.highlightedPairedDeviceID = paired.identifier;
    }
    [self refresh];
}

#pragma mark Clicks and drags

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    // Faded-out controls do not take clicks; the row does instead.
    if (hit && !self.showsRowControls && [hit isDescendantOf:_controls]) return self;
    // Labels and the icon pass clicks through to the row.
    if (hit && hit != self && ![hit isDescendantOf:_controls]) return self;
    return hit;
}

- (BOOL)canSelect {
    return _device.isConnected && !self.isUnavailable && !_isSelected;
}

- (void)select {
    if (self.canSelect) [_model selectManually:_device];
}

- (void)mouseDown:(NSEvent *)event {
    _isMouseDown = YES;
    _isDragging = NO;
    _dragStart = [self.superview convertPoint:event.locationInWindow fromView:nil];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isMouseDown) return;
    NSPoint point = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGSize translation = CGSizeMake(point.x - _dragStart.x, point.y - _dragStart.y);
    if (!_isDragging && hypot(translation.width, translation.height) < 8) return;
    _isDragging = YES;
    [_delegate row:self dragChangedAt:point translation:translation];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_isMouseDown) return;
    _isMouseDown = NO;
    if (_isDragging) {
        _isDragging = NO;
        [_delegate rowDragEnded:self];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, self.bounds)) [self select];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

#pragma mark Actions menu

- (NSMenuItem *)item:(NSString *)title symbol:(NSString *)symbol action:(SEL)action enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:enabled ? action : nil keyEquivalent:@""];
    item.target = self;
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    item.enabled = enabled;
    return item;
}

- (void)showActions:(id)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    BOOL isHidden = [_model isHidden:_device];
    BOOL isNeverUse = [_model isNeverUse:_device];
    if (_device.isConnected) {
        [menu addItem:[self item:self.activationTitle symbol:@"checkmark.circle" action:@selector(select) enabled:!_isSelected && !self.isUnavailable]];
        [menu addItem:NSMenuItem.separatorItem];
    }
    [menu addItem:[self item:@"Move Up" symbol:@"arrow.up" action:@selector(moveUp) enabled:_index > 0]];
    [menu addItem:[self item:@"Move Down" symbol:@"arrow.down" action:@selector(moveDown) enabled:_index < _count - 1]];

    APBOutputCategory category = self.category;
    if (_device.role == APBDeviceRoleOutput && category != APBOutputCategoryNone) {
        [menu addItem:NSMenuItem.separatorItem];
        BOOL isSpeaker = category == APBOutputCategorySpeaker;
        [menu addItem:[self item:isSpeaker ? @"Move to Headphones" : @"Move to Speakers"
                          symbol:isSpeaker ? @"headphones" : @"speaker.wave.2.fill"
                          action:@selector(toggleCategory)
                         enabled:YES]];
    }

    [menu addItem:NSMenuItem.separatorItem];
    if (isHidden) {
        [menu addItem:[self item:@"Unhide Device" symbol:@"eye" action:@selector(unhideDevice) enabled:YES]];
    } else {
        [menu addItem:[self item:@"Hide Device" symbol:@"eye.slash" action:@selector(hideDevice) enabled:!_isSelected]];
    }

    if (_device.isConnected) {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItem:[self item:isNeverUse ? @"Allow Auto-Selection" : @"Never Auto-Select"
                          symbol:isNeverUse ? @"checkmark.circle" : @"nosign"
                          action:@selector(toggleNeverUse)
                         enabled:YES]];
    } else {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItem:[self item:@"Forget Device…" symbol:@"trash" action:@selector(confirmForget) enabled:YES]];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(_actions.bounds) + 2) inView:_actions];
}

- (NSString *)activationTitle {
    NSString *role = _device.role == APBDeviceRoleInput ? @"Microphone" : @"Output";
    if (_isSelected) {
        return self.isUnavailable
            ? [NSString stringWithFormat:@"Current %@, Unavailable", role]
            : [NSString stringWithFormat:@"Current %@", role];
    }
    return _device.role == APBDeviceRoleInput ? @"Use as Microphone" : @"Use for Sound Output";
}

- (void)moveUp {
    [_delegate row:self moveTo:_index - 1];
}

- (void)moveDown {
    [_delegate row:self moveTo:_index + 1];
}

- (void)toggleCategory {
    APBOutputCategory target = self.category == APBOutputCategorySpeaker ? APBOutputCategoryHeadphone : APBOutputCategorySpeaker;
    [_model setCategory:target forDevice:_device];
}

- (void)hideDevice {
    [_model hide:_device];
}

- (void)unhideDevice {
    [_model unhide:_device];
}

- (void)toggleNeverUse {
    [_model setNeverUse:_device enabled:![_model isNeverUse:_device]];
}

- (void)confirmForget {
    APBAudioDevice *device = _device;
    APBAppModel *model = _model;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Forget %@?", device.name];
    alert.informativeText = @"Its saved priority, category, and visibility will be removed.";
    NSButton *forget = [alert addButtonWithTitle:@"Forget Device"];
    forget.hasDestructiveAction = YES;
    [alert addButtonWithTitle:@"Cancel"];
    NSWindow *window = self.window;
    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [model forget:device];
    };
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

#pragma mark Accessibility

- (NSString *)accessibilityHint {
    if (!_device.isConnected) return @"Use the actions menu to manage this device";
    if (self.isUnavailable) return @"This device is unavailable";
    if (_isSelected) return @"Current device";
    return _model.isManualMode
        ? @"Activate to make this device active"
        : @"Activate to select this device and turn off automatic switching";
}

- (NSString *)accessibilityValueWithStatuses:(NSArray<APBRowStatus *> *)statuses neverUse:(BOOL)isNeverUse unavailable:(BOOL)isUnavailable {
    NSMutableArray *values = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"Priority %ld of %ld", (long)_index + 1, (long)_count]];
    if (_isSelected && !isUnavailable) [values addObject:@"Active"];
    [values addObjectsFromArray:[statuses valueForKey:@"summary"]];
    // Shown only as strikethrough, so it needs saying here.
    if (isNeverUse) [values addObject:@"Never auto-select"];
    return [values componentsJoinedByString:@", "];
}

- (BOOL)accessibilityPerformPress {
    [self select];
    return YES;
}

- (NSArray *)accessibilityChildren {
    NSMutableArray *children = [NSMutableArray array];
    if (!_pill.hidden) [children addObject:_pill];
    [children addObject:_actions];
    return children;
}

- (BOOL)accessibilityMoveUp {
    if (_index > 0) [self moveUp];
    return YES;
}

- (BOOL)accessibilityMoveDown {
    if (_index < _count - 1) [self moveDown];
    return YES;
}

@end
