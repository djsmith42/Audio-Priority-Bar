#import "DeviceRowView.h"
#import "DeviceDrag.h"
#import "DeviceIcon.h"
#import "UIHelpers.h"

/// One status shown after the name.
@interface APBRowStatus : NSObject
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *text;
/// Carried with the value so restyling never depends on matching copy.
@property (nonatomic) NSColor *tint;
/// Read aloud and shown on hover instead of `text` when the glyph carries
/// meaning the text alone does not.
@property (nonatomic, copy, nullable) NSString *spokenText;
@property (nonatomic, readonly) NSString *statusDescription;
@end

@implementation APBRowStatus

+ (instancetype)statusWithIcon:(NSString *)icon text:(NSString *)text tint:(NSColor *)tint {
    APBRowStatus *status = [[self alloc] init];
    status.icon = icon;
    status.text = text;
    status.tint = tint ?: NSColor.secondaryLabelColor;
    return status;
}

- (NSString *)statusDescription {
    return _spokenText ?: _text;
}

@end

/// A small capsule button that reports hover.
@interface APBPillButton : NSButton
@property (nonatomic, copy, nullable) void (^onHover)(BOOL hovering);
@property (nonatomic, readonly) BOOL isHovering;
@end

@implementation APBPillButton {
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.font = [NSFont systemFontOfSize:APBCaptionSize weight:NSFontWeightSemibold];
        self.contentTintColor = NSColor.secondaryLabelColor;
        [self.heightAnchor constraintEqualToConstant:18].active = YES;
    }
    return self;
}

- (NSSize)intrinsicContentSize {
    NSSize text = [self.title sizeWithAttributes:@{NSFontAttributeName: self.font}];
    return NSMakeSize(ceil(text.width) + 12, 18);
}

- (void)setTitle:(NSString *)title {
    super.title = title;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
    }];
    [self invalidateIntrinsicContentSize];
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat radius = NSHeight(self.bounds) / 2;
    [APBPrimary(_isHovering ? 0.12 : 0.06) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
    [super drawRect:dirtyRect];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setHovering:(BOOL)hovering {
    if (_isHovering == hovering) return;
    _isHovering = hovering;
    self.needsDisplay = YES;
    if (_onHover) _onHover(hovering);
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self setHovering:NO];
}

@end

/// The ellipsis that opens the row's actions as a menu.
@interface APBMenuButton : NSButton
@property (nonatomic, copy, nullable) NSMenu *_Nullable (^makeMenu)(void);
@end

@implementation APBMenuButton

- (void)mouseDown:(NSEvent *)event {
    [self showMenu];
}

- (BOOL)accessibilityPerformPress {
    [self showMenu];
    return YES;
}

- (void)showMenu {
    NSMenu *menu = _makeMenu ? _makeMenu() : nil;
    if (!menu) return;
    NSPoint below = NSMakePoint(0, self.isFlipped ? NSHeight(self.bounds) + 2 : -2);
    [menu popUpMenuPositioningItem:nil atLocation:below inView:self];
}

@end

/// Holds the hover-only controls, ignoring clicks while they are faded out.
@interface APBFadingStack : NSStackView
@end

@implementation APBFadingStack

- (NSView *)hitTest:(NSPoint)point {
    return self.alphaValue < 0.01 ? nil : [super hitTest:point];
}

@end

@implementation APBDeviceRowView {
    APBAppModel *_model;
    NSInteger _count;
    BOOL _isSelected;
    APBOutputCategory _category;
    BOOL _isHovering;
    BOOL _isHoveringSelectionOverride;
    NSString *_highlightedPartnerID;
    NSArray<APBRowStatus *> *_statuses;

    NSTextField *_number;
    NSImageView *_handle;
    APBFillView *_iconCircle;
    NSImageView *_icon;
    NSTextField *_name;
    NSTextField *_statusLabel;
    APBFadingStack *_controls;
    APBPillButton *_pill;
    APBMenuButton *_actions;
    NSImageView *_forbidden;
    NSTrackingArea *_trackingArea;
    void (^_pillAction)(void);
    APBAudioDevice *_pillPartner;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 300, APBDeviceRowHeight)])) {
        _model = model;
        self.wantsLayer = YES;

        _number = APBLabel(@"", [NSFont monospacedDigitSystemFontOfSize:APBCaptionSize weight:NSFontWeightSemibold],
                           NSColor.secondaryLabelColor);
        _handle = [NSImageView imageViewWithImage:APBSymbol(@"line.3.horizontal", 11, NSFontWeightMedium)];
        _handle.contentTintColor = NSColor.secondaryLabelColor;
        _handle.alphaValue = 0;
        NSView *handleZone = [[NSView alloc] init];
        for (NSView *view in @[_number, _handle]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [handleZone addSubview:view];
            [view.leadingAnchor constraintEqualToAnchor:handleZone.leadingAnchor].active = YES;
            [view.centerYAnchor constraintEqualToAnchor:handleZone.centerYAnchor].active = YES;
        }

        _iconCircle = [[APBFillView alloc] init];
        _iconCircle.isCapsule = YES;
        _icon = [[NSImageView alloc] init];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconCircle addSubview:_icon];
        [_icon.centerXAnchor constraintEqualToAnchor:_iconCircle.centerXAnchor].active = YES;
        [_icon.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor].active = YES;

        _name = APBLabel(@"", [NSFont systemFontOfSize:APBBodySize], NSColor.labelColor);
        [_name setContentCompressionResistancePriority:740 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_name setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        _statusLabel = APBLabel(@"", [NSFont systemFontOfSize:APBCaptionSize], NSColor.secondaryLabelColor);
        [_statusLabel setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
        _statusLabel.accessibilityElement = NO;

        _pill = [[APBPillButton alloc] init];
        _pill.target = self;
        _pill.action = @selector(pillClicked:);
        __weak typeof(self) weakSelf = self;
        _pill.onHover = ^(BOOL hovering) { [weakSelf pillHovered:hovering]; };
        _actions = [[APBMenuButton alloc] init];
        _actions.bordered = NO;
        _actions.image = APBSymbol(@"ellipsis.circle", APBBodySize, NSFontWeightRegular);
        _actions.imagePosition = NSImageOnly;
        _actions.contentTintColor = NSColor.labelColor;
        _actions.makeMenu = ^NSMenu *{ return [weakSelf actionsMenu]; };
        [_actions.widthAnchor constraintEqualToConstant:28].active = YES;
        [_actions.heightAnchor constraintEqualToConstant:28].active = YES;
        _controls = [[APBFadingStack alloc] init];
        _controls.spacing = 6;
        [_controls addArrangedSubview:_pill];
        [_controls addArrangedSubview:_actions];
        _controls.alphaValue = 0;

        _forbidden = [NSImageView imageViewWithImage:APBSymbol(@"nosign", 16, NSFontWeightSemibold)];
        _forbidden.contentTintColor = NSColor.systemRedColor;
        _forbidden.hidden = YES;
        _forbidden.wantsLayer = YES;

        for (NSView *view in @[handleZone, _iconCircle, _name, _statusLabel, _controls, _forbidden]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:view];
        }
        NSLayoutConstraint *statusTrailing = [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_controls.leadingAnchor constant:-6];
        [NSLayoutConstraint activateConstraints:@[
            // The row overhangs the section by 8 points on each side, so its
            // text lines up with the heading while its highlight overhangs.
            [handleZone.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [handleZone.widthAnchor constraintEqualToConstant:14],
            [handleZone.topAnchor constraintEqualToAnchor:self.topAnchor],
            [handleZone.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_iconCircle.leadingAnchor constraintEqualToAnchor:handleZone.trailingAnchor constant:6],
            [_iconCircle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconCircle.widthAnchor constraintEqualToConstant:26],
            [_iconCircle.heightAnchor constraintEqualToConstant:26],
            [_name.leadingAnchor constraintEqualToAnchor:_iconCircle.trailingAnchor constant:8],
            [_name.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_statusLabel.leadingAnchor constraintEqualToAnchor:_name.trailingAnchor constant:8],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            statusTrailing,
            [_name.trailingAnchor constraintLessThanOrEqualToAnchor:_controls.leadingAnchor constant:-6],
            [_controls.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_controls.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_forbidden.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:5],
            [_forbidden.topAnchor constraintEqualToAnchor:self.topAnchor constant:-5],
        ]];

        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityGroupRole;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - State

- (APBLinkState)linkState {
    return [_model linkStateForDevice:_device];
}

- (BOOL)isUnavailable {
    return self.linkState == APBLinkStateDown;
}

- (BOOL)isHiddenDevice {
    return [_model isHidden:_device];
}

- (BOOL)isNeverUse {
    return [_model isNeverUse:_device];
}

- (APBAudioDevice *)pairedDevice {
    return [_model pairedDeviceFor:_device];
}

/// Whether this device and its pair are both currently selected, so
/// selecting them together has nothing left to do.
- (BOOL)areBothDevicesSelected {
    APBAudioDevice *paired = self.pairedDevice;
    if (!paired) return NO;
    NSNumber *current = paired.role == APBDeviceRoleInput ? _model.currentInputID : _model.currentOutputID;
    return _isSelected && current && current.unsignedIntValue == paired.platformID;
}

/// Whether the paired device is connected and not link-down, so selecting it
/// could actually take effect.
- (BOOL)isPairedDeviceUsable {
    APBAudioDevice *paired = self.pairedDevice;
    if (!paired) return NO;
    return _device.isConnected && !self.isUnavailable && [_model linkStateForDevice:paired] != APBLinkStateDown;
}

- (BOOL)canSelectBothDevices {
    return self.isPairedDeviceUsable && !self.areBothDevicesSelected;
}

- (NSString *)selectionOverrideHelp {
    if (_model.selectsPairedDevice) {
        return _device.role == APBDeviceRoleInput
            ? @"Select only this microphone, not its output"
            : @"Select only this output, not its microphone";
    }
    return [NSString stringWithFormat:@"Use %@ for input and output", _device.name];
}

- (NSArray<APBRowStatus *> *)computeStatuses {
    NSMutableArray<APBRowStatus *> *result = [NSMutableArray array];
    APBLinkState linkState = self.linkState;
    if (_isSelected && self.isUnavailable) {
        [result addObject:[APBRowStatus statusWithIcon:@"exclamationmark.circle" text:@"Current" tint:NSColor.systemOrangeColor]];
    }
    if (!_device.isConnected) {
        NSString *seen = [[_model.store storedDeviceWithUID:_device.uid role:@(_device.role)] relativeLastSeen];
        NSString *text = seen ? [NSString stringWithFormat:@"Disconnected · Last seen %@", seen] : @"Disconnected";
        [result addObject:[APBRowStatus statusWithIcon:@"wifi.slash" text:text tint:nil]];
    }
    // The antenna-slash glyph means a proven verdict, so it belongs to `down`
    // alone: that state dims the row and blocks selection, while the states
    // below leave the device selectable. `checking` shows nothing at all
    // because it settles in tens of milliseconds and would only flicker;
    // automatic selection still waits for it internally.
    if (linkState == APBLinkStateDown) {
        [result addObject:[APBRowStatus statusWithIcon:@"antenna.radiowaves.left.and.right.slash"
                                                  text:@"Headset off"
                                                  tint:NSColor.systemOrangeColor]];
    } else if (linkState == APBLinkStateUnknown) {
        [result addObject:[APBRowStatus statusWithIcon:@"questionmark.circle" text:@"Link unknown" tint:nil]];
    } else if (linkState == APBLinkStateMonitoringUnavailable) {
        [result addObject:[APBRowStatus statusWithIcon:@"questionmark.circle" text:@"Link status unavailable" tint:nil]];
    }
    if (self.isHiddenDevice) {
        [result addObject:[APBRowStatus statusWithIcon:@"eye.slash" text:@"Hidden" tint:nil]];
    }
    if ([_model isMuted:_device]) {
        [result addObject:[APBRowStatus statusWithIcon:_device.role == APBDeviceRoleInput ? @"mic.slash.fill" : @"speaker.slash.fill"
                                                  text:@"Muted"
                                                  tint:NSColor.systemRedColor]];
    }
    for (APBBatteryBadge *badge in [_model batteryLevelsForDevice:_device].badges) {
        APBRowStatus *status = [APBRowStatus statusWithIcon:badge.icon
                                                       text:badge.text
                                                       tint:badge.isLow ? NSColor.systemOrangeColor : nil];
        status.spokenText = badge.spokenText;
        [result addObject:status];
    }
    return result;
}

- (BOOL)isSelectable {
    return _device.isConnected && !self.isUnavailable && !_isSelected;
}

#pragma mark - Configuration

- (void)configureWithDevice:(APBAudioDevice *)device
                      index:(NSInteger)index
                      count:(NSInteger)count
                 isSelected:(BOOL)isSelected
                   category:(APBOutputCategory)category {
    _device = device;
    _index = index;
    _count = count;
    _isSelected = isSelected;
    _category = category;
    _statuses = [self computeStatuses];

    _number.stringValue = [NSString stringWithFormat:@"%ld", (long)index + 1];

    BOOL unavailable = self.isUnavailable;
    // Orange rather than the accent while the current device is unavailable,
    // matching its "Current" status.
    _iconCircle.fillColor = isSelected
        ? (unavailable ? NSColor.systemOrangeColor : NSColor.controlAccentColor)
        : APBPrimary(0.1);
    _icon.image = APBSymbol([device hardwareIconForCategory:category], 12, NSFontWeightRegular);
    _icon.contentTintColor = isSelected ? NSColor.whiteColor : NSColor.secondaryLabelColor;

    BOOL neverUse = self.isNeverUse;
    NSColor *nameColor = !device.isConnected || unavailable || neverUse ? NSColor.secondaryLabelColor : NSColor.labelColor;
    NSMutableDictionary *attributes = [@{
        NSFontAttributeName: [NSFont systemFontOfSize:APBBodySize],
        NSForegroundColorAttributeName: nameColor,
    } mutableCopy];
    if (neverUse) {
        attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        attributes[NSStrikethroughColorAttributeName] = NSColor.secondaryLabelColor;
    }
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    attributes[NSParagraphStyleAttributeName] = paragraph;
    _name.attributedStringValue = [[NSAttributedString alloc] initWithString:device.name attributes:attributes];
    _name.toolTip = neverUse ? [NSString stringWithFormat:@"%@ · Never auto-select", device.name] : device.name;

    _statusLabel.attributedStringValue = [self statusString];
    NSMutableArray *descriptions = [NSMutableArray array];
    for (APBRowStatus *status in _statuses) [descriptions addObject:status.statusDescription];
    _statusLabel.toolTip = descriptions.count ? [descriptions componentsJoinedByString:@" · "] : nil;

    [self configureSelectionOverride];
    _actions.accessibilityLabel = [NSString stringWithFormat:@"Actions for %@", device.name];
    [self configureAccessibility];
    [self updateChrome:NO];
}

/// The statuses as one line of glyphs and text, so the line truncates as a
/// whole.
- (NSAttributedString *)statusString {
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] init];
    NSFont *font = [NSFont systemFontOfSize:APBCaptionSize];
    for (APBRowStatus *status in _statuses) {
        if (string.length) [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:@{NSFontAttributeName: font}]];
        NSImage *glyph = [APBSymbol(status.icon, APBCaptionSize, NSFontWeightRegular)
                          imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[status.tint]]];
        if (glyph) {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = glyph;
            CGFloat y = round((font.capHeight - glyph.size.height) / 2);
            attachment.bounds = NSMakeRect(0, y, glyph.size.width, glyph.size.height);
            [string appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
            [string appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{NSFontAttributeName: font}]];
        }
        [string appendAttributedString:[[NSAttributedString alloc] initWithString:status.text attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: status.tint,
        }]];
    }
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    [string addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, string.length)];
    return string;
}

/// The override for the current default: offers to select only this device
/// while both are normally selected together, or to select both while only
/// one is. Shown only while it would change something, so a row whose pair
/// is already in the target state, unavailable, or absent keeps the layout it
/// had before.
- (void)configureSelectionOverride {
    APBAudioDevice *paired = self.pairedDevice;
    _pillAction = nil;
    _pillPartner = nil;
    if (paired && self.isPairedDeviceUsable) {
        __weak typeof(self) weakSelf = self;
        if (_model.selectsPairedDevice) {
            if (!_isSelected) {
                _pill.title = _device.role == APBDeviceRoleInput ? @"Mic only" : @"Output only";
                _pillAction = ^{
                    APBDeviceRowView *row = weakSelf;
                    if (row) [row->_model selectOnly:row->_device];
                };
            }
        } else if (self.canSelectBothDevices) {
            _pill.title = @"Use both";
            _pillAction = ^{
                APBDeviceRowView *row = weakSelf;
                if (row) [row->_model selectWithPairedDevice:row->_device];
            };
        }
    }
    if (_pillAction) _pillPartner = paired;
    _pill.hidden = _pillAction == nil;
    _pill.toolTip = self.selectionOverrideHelp;
    _pill.accessibilityLabel = self.selectionOverrideHelp;
}

- (void)pillClicked:(id)sender {
    if (_pillAction) _pillAction();
}

- (void)pillHovered:(BOOL)hovering {
    APBAudioDevice *partner = _pillPartner;
    _isHoveringSelectionOverride = hovering;
    if (!partner) return;
    id<APBDeviceRowHost> host = _host;
    if (_model.selectsPairedDevice) {
        // This override selects only the hovered device, so suppress the
        // partner highlight while hovering it, and restore it when returning
        // to the row, which still selects both.
        if (hovering) {
            if ([host.highlightedPairedDeviceID isEqualToString:partner.identifier]) host.highlightedPairedDeviceID = nil;
        } else if (_isHovering && !_isSelected) {
            _highlightedPartnerID = partner.identifier;
            host.highlightedPairedDeviceID = partner.identifier;
        }
    } else if (hovering) {
        // "Use both" is the only control that selects the partner while
        // selecting one device at a time is the default.
        host.highlightedPairedDeviceID = partner.identifier;
    } else if ([host.highlightedPairedDeviceID isEqualToString:partner.identifier]) {
        host.highlightedPairedDeviceID = nil;
    }
}

#pragma mark - Appearance

- (void)setIsLifted:(BOOL)isLifted {
    if (_isLifted == isLifted) return;
    _isLifted = isLifted;
    [self updateChrome:YES];
}

- (void)setIsForbidden:(BOOL)isForbidden {
    _isForbidden = isForbidden;
    _forbidden.hidden = !isForbidden;
}

- (void)refreshHighlight {
    self.needsDisplay = YES;
}

- (BOOL)showsDragHandle {
    return _isHovering || _isLifted;
}

/// The selection override and actions menu appear only on hover, like the
/// system's own lists, but stay visible to VoiceOver, which has no pointer
/// to hover with, and while one has keyboard focus.
- (BOOL)showsRowControls {
    NSResponder *responder = self.window.firstResponder;
    BOOL focused = responder == _pill || responder == _actions;
    return _isHovering || NSWorkspace.sharedWorkspace.isVoiceOverEnabled || focused;
}

- (void)updateChrome:(BOOL)animated {
    BOOL handle = self.showsDragHandle;
    BOOL controls = self.showsRowControls;
    void (^changes)(void) = ^{
        self->_number.animator.alphaValue = handle ? 0 : 1;
        self->_handle.animator.alphaValue = handle ? 1 : 0;
        self->_controls.animator.alphaValue = controls ? 1 : 0;
    };
    if (animated) {
        APBAnimate(0.12, changes);
    } else {
        _number.alphaValue = handle ? 0 : 1;
        _handle.alphaValue = handle ? 1 : 0;
        _controls.alphaValue = controls ? 1 : 0;
    }
    self.shadow = nil;
    if (_isLifted) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.28];
        shadow.shadowBlurRadius = 10;
        shadow.shadowOffset = NSMakeSize(0, -5);
        self.shadow = shadow;
    }
    self.layer.masksToBounds = NO;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *fill = nil;
    if (_isLifted) {
        fill = NSColor.controlBackgroundColor;
    } else if (_isHovering || [_host.highlightedPairedDeviceID isEqualToString:_device.identifier]) {
        fill = APBPrimary(0.06);
    }
    if (!fill) return;
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
}

#pragma mark - Pointer

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self setHovering:NO];
}

- (void)setHovering:(BOOL)hovering {
    if (_isHovering == hovering) return;
    _isHovering = hovering;
    [self updateChrome:YES];
    id<APBDeviceRowHost> host = _host;
    if (!hovering) {
        NSString *highlighted = host.highlightedPairedDeviceID;
        if (highlighted == _highlightedPartnerID || [highlighted isEqualToString:_highlightedPartnerID]) {
            host.highlightedPairedDeviceID = nil;
        }
        _highlightedPartnerID = nil;
        // The override cannot still be hovered once the pointer has left the
        // row, and it reports nothing when selecting a device stops it being
        // shown at all.
        _isHoveringSelectionOverride = NO;
        return;
    }
    APBAudioDevice *paired = self.pairedDevice;
    if (!_model.selectsPairedDevice || !self.isPairedDeviceUsable || _isSelected
        || _isHoveringSelectionOverride || !paired) {
        return;
    }
    _highlightedPartnerID = paired.identifier;
    host.highlightedPairedDeviceID = paired.identifier;
}

- (void)mouseDown:(NSEvent *)event {
    [_host row:self mouseDown:event];
}

- (void)selectDevice {
    [_model selectManually:_device];
}

#pragma mark - Actions

- (NSMenu *)menuForEvent:(NSEvent *)event {
    return [self actionsMenu];
}

- (NSMenuItem *)item:(NSString *)title symbol:(NSString *)symbol action:(SEL)action enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = enabled;
    if (@available(macOS 26, *)) {
        item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    }
    return item;
}

- (NSMenu *)actionsMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    BOOL unavailable = self.isUnavailable;
    if (_device.isConnected) {
        [menu addItem:[self item:self.activationTitle symbol:@"checkmark.circle" action:@selector(activate:)
                         enabled:!_isSelected && !unavailable]];
        [menu addItem:NSMenuItem.separatorItem];
    }
    [menu addItem:[self item:@"Move Up" symbol:@"arrow.up" action:@selector(moveUp:) enabled:_index > 0]];
    [menu addItem:[self item:@"Move Down" symbol:@"arrow.down" action:@selector(moveDown:) enabled:_index < _count - 1]];
    if (_device.role == APBDeviceRoleOutput && _category != APBOutputCategoryNone) {
        [menu addItem:NSMenuItem.separatorItem];
        BOOL isSpeaker = _category == APBOutputCategorySpeaker;
        [menu addItem:[self item:isSpeaker ? @"Move to Headphones" : @"Move to Speakers"
                          symbol:isSpeaker ? @"headphones" : @"speaker.wave.2.fill"
                          action:@selector(switchCategory:)
                         enabled:YES]];
    }
    [menu addItem:NSMenuItem.separatorItem];
    if (self.isHiddenDevice) {
        [menu addItem:[self item:@"Unhide Device" symbol:@"eye" action:@selector(unhideDevice:) enabled:YES]];
    } else {
        [menu addItem:[self item:@"Hide Device" symbol:@"eye.slash" action:@selector(hideDevice:) enabled:!_isSelected]];
    }
    if (_device.isConnected) {
        [menu addItem:NSMenuItem.separatorItem];
        BOOL neverUse = self.isNeverUse;
        [menu addItem:[self item:neverUse ? @"Allow Auto-Selection" : @"Never Auto-Select"
                          symbol:neverUse ? @"checkmark.circle" : @"nosign"
                          action:@selector(toggleNeverUse:)
                         enabled:YES]];
    } else {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItem:[self item:@"Forget Device" symbol:@"trash" action:@selector(confirmForget:) enabled:YES]];
    }
    return menu;
}

- (NSString *)activationTitle {
    NSString *role = _device.role == APBDeviceRoleInput ? @"Microphone" : @"Output";
    if (_isSelected) {
        return self.isUnavailable ? [NSString stringWithFormat:@"Current %@, Unavailable", role]
                                  : [NSString stringWithFormat:@"Current %@", role];
    }
    return _device.role == APBDeviceRoleInput ? @"Use as Microphone" : @"Use for Sound Output";
}

- (void)activate:(id)sender {
    [self selectDevice];
}

- (void)moveUp:(id)sender {
    [_host row:self moveTo:_index - 1];
}

- (void)moveDown:(id)sender {
    [_host row:self moveTo:_index + 1];
}

- (void)switchCategory:(id)sender {
    APBOutputCategory target = _category == APBOutputCategorySpeaker ? APBOutputCategoryHeadphone : APBOutputCategorySpeaker;
    [_model setCategory:target forDevice:_device];
}

- (void)unhideDevice:(id)sender {
    [_model unhide:_device];
}

- (void)hideDevice:(id)sender {
    [_model hide:_device];
}

- (void)toggleNeverUse:(id)sender {
    [_model setNeverUse:_device enabled:!self.isNeverUse];
}

- (void)confirmForget:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Forget %@?", _device.name];
    alert.informativeText = @"Its saved priority, category, and visibility will be removed.";
    NSButton *forget = [alert addButtonWithTitle:@"Forget Device"];
    forget.hasDestructiveAction = YES;
    [alert addButtonWithTitle:@"Cancel"];
    APBAudioDevice *device = _device;
    APBAppModel *model = _model;
    void (^completion)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [model forget:device];
    };
    if (self.window) {
        [alert beginSheetModalForWindow:self.window completionHandler:completion];
    } else {
        completion([alert runModal]);
    }
}

#pragma mark - Accessibility

- (void)configureAccessibility {
    self.accessibilityLabel = _device.name;
    NSMutableArray *values = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"Priority %ld of %ld", (long)_index + 1, (long)_count]];
    if (_isSelected && !self.isUnavailable) [values addObject:@"Active"];
    for (APBRowStatus *status in _statuses) [values addObject:status.statusDescription];
    // Shown only as strikethrough, so it needs saying here.
    if (self.isNeverUse) [values addObject:@"Never auto-select"];
    self.accessibilityValue = [values componentsJoinedByString:@", "];
    NSString *hint;
    if (!_device.isConnected) {
        hint = @"Use the actions menu to manage this device";
    } else if (self.isUnavailable) {
        hint = @"This device is unavailable";
    } else if (_isSelected) {
        hint = @"Current device";
    } else if (_model.isManualMode) {
        hint = @"Activate to make this device active";
    } else {
        hint = @"Activate to select this device and turn off automatic switching";
    }
    self.accessibilityHelp = hint;
    self.accessibilitySelected = _isSelected;
    __weak typeof(self) weakSelf = self;
    self.accessibilityCustomActions = @[
        [[NSAccessibilityCustomAction alloc] initWithName:@"Move Up" handler:^BOOL {
            APBDeviceRowView *row = weakSelf;
            if (row && row.index > 0) [row.host row:row moveTo:row.index - 1];
            return YES;
        }],
        [[NSAccessibilityCustomAction alloc] initWithName:@"Move Down" handler:^BOOL {
            APBDeviceRowView *row = weakSelf;
            if (row && row.index < row->_count - 1) [row.host row:row moveTo:row.index + 1];
            return YES;
        }],
    ];
}

- (BOOL)accessibilityPerformPress {
    if (self.isSelectable) [self selectDevice];
    return YES;
}

@end
