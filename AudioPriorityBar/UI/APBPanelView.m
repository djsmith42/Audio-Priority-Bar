#import "APBPanelView.h"
#import "APBDeviceDrag.h"
#import "APBDeviceIcon.h"
#import "APBDeviceRowView.h"
#import "APBUI.h"

/// The AirPods page, which holds their Connect to This Mac setting.
static NSString *const HeadphoneSettingsURL = @"x-apple.systempreferences:com.apple.HeadphoneSettings";

static NSLayoutConstraint *Pin(NSLayoutConstraint *constraint, NSLayoutPriority priority) {
    constraint.priority = priority;
    return constraint;
}

#pragma mark - Level control

/// One row for the current output or microphone: the icon mutes, the slider
/// sets the level. Both rows share it so they look and behave alike.
@interface APBLevelControl : NSView
@property (nonatomic, copy) NSString *name;
/// The device the row controls, named in the tooltip and for VoiceOver rather
/// than taking a line of its own.
@property (nonatomic, copy, nullable) NSString *deviceName;
@property (nonatomic, copy) NSString *icon;
/// Shown while hovering, so the button previews what a click will do.
@property (nonatomic, copy) NSString *toggledIcon;
@property (nonatomic) BOOL isMuted;
@property (nonatomic) float level;
@property (nonatomic) BOOL isControllable;
/// Shown in place of the slider when the level cannot be set, so a disabled
/// slider is not mistaken for a broken one.
@property (nonatomic, copy) NSString *uncontrollableNote;
/// NO when muting cannot work, so the button shows as disabled rather than
/// pressing and doing nothing.
@property (nonatomic) BOOL canToggleMute;
@property (nonatomic, copy) dispatch_block_t toggleMute;
@property (nonatomic, copy) void (^setLevel)(float level);
- (void)update;
@end

@implementation APBLevelControl {
    APBHoverView *_muteButton;
    NSImageView *_muteIcon;
    NSSlider *_slider;
    NSTextField *_percent;
    NSTextField *_note;
    /// Set by a click so the result shows until the pointer leaves, instead of
    /// the preview flipping straight back to the previous state.
    BOOL _isPreviewSuppressed;
}

- (instancetype)init {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _canToggleMute = YES;

        _muteButton = [[APBHoverView alloc] init];
        _muteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _muteButton.isCapsule = YES;
        _muteIcon = [[NSImageView alloc] init];
        _muteIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_muteButton addSubview:_muteIcon];
        __weak typeof(self) weakSelf = self;
        _muteButton.onClick = ^{
            typeof(self) self = weakSelf;
            if (!self || !self.canToggleMute) return;
            self->_isPreviewSuppressed = YES;
            self.toggleMute();
        };
        _muteButton.onHover = ^(BOOL hovering) {
            typeof(self) self = weakSelf;
            if (!self) return;
            if (!hovering) self->_isPreviewSuppressed = NO;
            [self update];
        };
        [_muteButton setAccessibilityElement:YES];
        [_muteButton setAccessibilityRole:NSAccessibilityButtonRole];

        _slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(sliderMoved:)];
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        _slider.controlSize = NSControlSizeSmall;
        _slider.continuous = YES;

        // Sized to the widest value, so it sits close to the slider without the
        // slider resizing as the digits change.
        _percent = APBLabel(@"", [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
        _percent.translatesAutoresizingMaskIntoConstraints = NO;
        CGFloat widest = [@"100%" sizeWithAttributes:@{ NSFontAttributeName: _percent.font }].width;
        [_percent setAccessibilityElement:NO];

        _note = APBLabel(@"", [NSFont systemFontOfSize:12], NSColor.tertiaryLabelColor);
        _note.translatesAutoresizingMaskIntoConstraints = NO;

        for (NSView *view in @[ _muteButton, _slider, _percent, _note ]) [self addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [_muteButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_muteButton.widthAnchor constraintEqualToConstant:26],
            [_muteButton.heightAnchor constraintEqualToConstant:26],
            [_muteButton.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_muteButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_muteIcon.centerXAnchor constraintEqualToAnchor:_muteButton.centerXAnchor],
            [_muteIcon.centerYAnchor constraintEqualToAnchor:_muteButton.centerYAnchor],
            [_slider.leadingAnchor constraintEqualToAnchor:_muteButton.trailingAnchor constant:10],
            [_slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_percent.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor constant:6],
            [_percent.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_percent.widthAnchor constraintEqualToConstant:ceil(widest) + 2],
            [_percent.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_note.leadingAnchor constraintEqualToAnchor:_muteButton.trailingAnchor constant:10],
            [_note.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
            [_note.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)sliderMoved:(NSSlider *)slider {
    if (_setLevel) _setLevel((float)slider.doubleValue);
}

- (void)scrollWheel:(NSEvent *)event {
    if (!_isControllable || !_setLevel) return;
    _setLevel(MAX(0, MIN(1, _level + (float)(event.deltaY * 0.02))));
}

- (NSString *)muteTitle {
    return [NSString stringWithFormat:@"%@ %@", _isMuted ? @"Unmute" : @"Mute", _deviceName ?: _name];
}

- (void)update {
    BOOL hovering = _muteButton.isHovering;
    NSString *iconName = hovering && _canToggleMute && !_isPreviewSuppressed ? _toggledIcon : _icon;
    _muteIcon.image = APBSymbol(iconName, 13, NSFontWeightRegular);
    _muteIcon.contentTintColor = _isMuted ? NSColor.systemRedColor : NSColor.labelColor;
    // Always filled so the icon reads as a button, and tinted while muted.
    _muteButton.fillColor = _isMuted
        ? [NSColor.systemRedColor colorWithAlphaComponent:hovering ? 0.3 : 0.2]
        : APBPrimary(hovering ? 0.24 : 0.16);
    _muteButton.alphaValue = _canToggleMute ? 1 : 0.5;
    _muteButton.toolTip = self.muteTitle;
    [_muteButton setAccessibilityLabel:self.muteTitle];
    [_muteButton setAccessibilityEnabled:_canToggleMute];

    BOOL showsNote = !_isControllable && _uncontrollableNote.length > 0;
    _note.hidden = !showsNote;
    _note.stringValue = _uncontrollableNote ?: @"";
    _note.toolTip = _deviceName ?: _name;
    _slider.hidden = showsNote;
    _percent.hidden = showsNote;
    _slider.enabled = _isControllable;
    _slider.doubleValue = _level;
    _slider.alphaValue = _isMuted ? 0.5 : 1;
    _slider.toolTip = _deviceName ?: _name;
    [_slider setAccessibilityLabel:[NSString stringWithFormat:@"%@ volume", _name]];
    NSMutableArray *values = [NSMutableArray array];
    if (_isMuted) [values addObject:@"Muted"];
    [values addObject:_isControllable ? [NSString stringWithFormat:@"%d percent", (int)(_level * 100)] : @"Unavailable"];
    if (_deviceName) [values addObject:_deviceName];
    [_slider setAccessibilityValueDescription:[values componentsJoinedByString:@", "]];
    _percent.stringValue = _isControllable ? [NSString stringWithFormat:@"%d%%", (int)(_level * 100)] : @"—";
}

@end

#pragma mark - Device lists

@interface APBDeviceListsView : NSView <APBDeviceRowDelegate>
@property (nonatomic, copy, nullable) NSString *highlightedPairedDeviceID;
@property (nonatomic, readonly, nullable) APBDeviceDrag *drag;
@property (nonatomic, copy, nullable) dispatch_block_t onDragChange;
@property (nonatomic, readonly) CGFloat contentHeight;
- (instancetype)initWithModel:(APBAppModel *)model;
- (APBPanelLayout *)layoutModel;
- (void)refresh;
- (void)cancelDrag;
@end

/// The views for one section: its heading, placeholder and separator.
@interface APBSectionViews : NSObject
@property (nonatomic) NSTextField *title;
@property (nonatomic) APBFillView *empty;
@property (nonatomic) NSTextField *emptyLabel;
@property (nonatomic, nullable) APBSeparator *separator;
@end

@implementation APBSectionViews
@end

@implementation APBDeviceListsView {
    APBAppModel *_model;
    NSMutableDictionary<NSString *, APBDeviceRowView *> *_rows;
    NSDictionary<NSNumber *, APBSectionViews *> *_sections;
    APBDropTarget _lastTarget;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    self = [super initWithFrame:NSMakeRect(0, 0, APBPanelWidth, 100)];
    if (self) {
        _model = model;
        _rows = [NSMutableDictionary dictionary];
        NSMutableDictionary *sections = [NSMutableDictionary dictionary];
        NSDictionary *titles = @{
            @(APBDeviceSectionSpeaker): @[ @"Speakers", @"No speakers shown" ],
            @(APBDeviceSectionHeadphone): @[ @"Headphones", @"No headphones shown" ],
            @(APBDeviceSectionInput): @[ @"Microphones", @"No microphones shown" ],
        };
        for (NSNumber *section in titles) {
            APBSectionViews *views = [[APBSectionViews alloc] init];
            views.title = APBLabel(titles[section][0], [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
            [views.title setAccessibilityRole:NSAccessibilityStaticTextRole];
            [views.title setAccessibilityRoleDescription:@"heading"];
            views.empty = [[APBFillView alloc] init];
            views.empty.cornerRadius = 8;
            NSFont *italic = [NSFontManager.sharedFontManager convertFont:[NSFont systemFontOfSize:12] toHaveTrait:NSItalicFontMask];
            views.emptyLabel = APBLabel(titles[section][1], italic, NSColor.tertiaryLabelColor);
            views.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [views.empty addSubview:views.emptyLabel];
            [NSLayoutConstraint activateConstraints:@[
                [views.emptyLabel.leadingAnchor constraintEqualToAnchor:views.empty.leadingAnchor constant:8],
                [views.emptyLabel.centerYAnchor constraintEqualToAnchor:views.empty.centerYAnchor],
            ]];
            // Draws a separator in the gap above every section but the first.
            if (section.integerValue != APBDeviceSectionSpeaker) {
                views.separator = [APBSeparator separator];
                views.separator.translatesAutoresizingMaskIntoConstraints = YES;
                [views.separator setAccessibilityElement:NO];
                [self addSubview:views.separator];
            }
            [self addSubview:views.title];
            [self addSubview:views.empty];
            sections[section] = views;
        }
        _sections = sections;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSArray<APBAudioDevice *> *)devicesIn:(APBDeviceSection)section {
    switch (section) {
        case APBDeviceSectionSpeaker: return _model.speakerDevices;
        case APBDeviceSectionHeadphone: return _model.headphoneDevices;
        case APBDeviceSectionInput: return _model.inputDevices;
    }
}

- (UInt32)currentIDIn:(APBDeviceSection)section {
    return section == APBDeviceSectionInput ? _model.currentInputID : _model.currentOutputID;
}

- (NSArray<NSNumber *> *)sectionOrder {
    return @[ @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone), @(APBDeviceSectionInput) ];
}

- (APBPanelLayout *)layoutModel {
    NSMutableArray *sections = [NSMutableArray array];
    for (NSNumber *section in self.sectionOrder) {
        [sections addObject:@[ section, @([self devicesIn:section.integerValue].count) ]];
    }
    return [[APBPanelLayout alloc] initWithSections:sections];
}

- (void)setHighlightedPairedDeviceID:(NSString *)identifier {
    if (identifier == _highlightedPairedDeviceID || [identifier isEqualToString:_highlightedPairedDeviceID]) return;
    _highlightedPairedDeviceID = [identifier copy];
    for (APBDeviceRowView *row in _rows.allValues) [row refresh];
}

- (void)refresh {
    NSMutableSet *rendered = [NSMutableSet set];
    for (NSNumber *section in self.sectionOrder) {
        NSArray<APBAudioDevice *> *devices = [self devicesIn:section.integerValue];
        UInt32 currentID = [self currentIDIn:section.integerValue];
        [devices enumerateObjectsUsingBlock:^(APBAudioDevice *device, NSUInteger index, BOOL *stop) {
            APBDeviceRowView *row = self->_rows[device.identifier];
            if (!row) {
                row = [[APBDeviceRowView alloc] initWithModel:self->_model delegate:self];
                self->_rows[device.identifier] = row;
                [self addSubview:row];
            }
            [rendered addObject:device.identifier];
            [row updateDevice:device
                        index:(NSInteger)index
                        count:(NSInteger)devices.count
                   isSelected:device.isConnected && currentID == device.platformID
                      section:section.integerValue];
        }];
    }
    for (NSString *identifier in _rows.allKeys) {
        if ([rendered containsObject:identifier]) continue;
        [_rows[identifier] removeFromSuperview];
        [_rows removeObjectForKey:identifier];
    }
    if (_drag && ![rendered containsObject:_drag.device.identifier]) [self endDragNotifying:YES];
    // A row removed while hovered never reports the pointer leaving, so its
    // partner's highlight would outlive both rows.
    if (_highlightedPairedDeviceID && ![rendered containsObject:_highlightedPairedDeviceID]) {
        self.highlightedPairedDeviceID = nil;
    }
    [self layoutRowsAnimated:NO];
}

- (CGFloat)contentHeight {
    APBPanelLayout *layout = self.layoutModel;
    return layout.contentHeight + MAX(0, _drag ? [layout heightDeltaFor:_drag] : 0);
}

- (void)layoutRowsAnimated:(BOOL)animated {
    APBPanelLayout *layout = self.layoutModel;
    CGFloat padding = APBPanelLayout.horizontalPadding;
    CGFloat width = APBPanelWidth - padding * 2;
    NSMutableArray<dispatch_block_t> *changes = [NSMutableArray array];
    __block APBDeviceRowView *liftedRow = nil;

    for (NSNumber *number in self.sectionOrder) {
        APBDeviceSection section = number.integerValue;
        APBSectionViews *views = _sections[number];
        NSArray<APBAudioDevice *> *devices = [self devicesIn:section];
        CGFloat offset = _drag ? [layout sectionOffsetFor:section drag:_drag] : 0;
        CGFloat top = [layout sectionTopOf:section] + offset;
        CGFloat contentTop = [layout contentTopOf:section] + offset;

        NSRect titleFrame = NSMakeRect(padding, top, width, APBSectionHeaderHeight);
        NSRect separatorFrame = NSMakeRect(padding, top - APBPanelLayout.sectionGap + APBPanelLayout.separatorInset, width, 1);
        BOOL isTargeted = _drag && _drag.target.exists && _drag.target.section == section;
        views.empty.hidden = devices.count > 0;
        views.empty.fillColor = [NSColor.controlAccentColor colorWithAlphaComponent:isTargeted ? 0.12 : 0];
        // Overhangs the text like a row's highlight does.
        NSRect emptyFrame = NSMakeRect(padding - 8, contentTop, width + 16, APBRowHeight);
        [changes addObject:^{
            views.title.animator.frame = titleFrame;
            views.separator.animator.frame = separatorFrame;
            views.empty.animator.frame = emptyFrame;
        }];

        [devices enumerateObjectsUsingBlock:^(APBAudioDevice *device, NSUInteger index, BOOL *stop) {
            APBDeviceRowView *row = self->_rows[device.identifier];
            BOOL lifted = self->_drag && [self->_drag.device.identifier isEqualToString:device.identifier];
            CGFloat y = contentTop + (CGFloat)index * APBRowPitch;
            if (lifted) {
                y += [layout liftedOffsetFor:self->_drag];
            } else if (self->_drag) {
                y += [layout rowOffsetAt:(NSInteger)index in:section drag:self->_drag];
            }
            NSRect frame = NSMakeRect(padding - 8, y, width + 16, APBRowHeight);
            // The lifted row grows 2% about its center. Done with the frame,
            // since AppKit owns a view layer's anchor point and position, and
            // a layer transform drew the row half a width to the left.
            if (lifted && !APBReduceMotion()) {
                frame = NSInsetRect(frame, -NSWidth(frame) * 0.01, -NSHeight(frame) * 0.01);
            }
            if (lifted && !self->_drag.target.exists) {
                // Follows the pointer directly while over no gap.
                row.frame = frame;
            } else {
                [changes addObject:^{ row.animator.frame = frame; }];
            }
            if (row.isLifted != lifted || row.isForbidden != (lifted && self->_drag.isForbidden)) {
                row.isLifted = lifted;
                row.isForbidden = lifted && self->_drag.isForbidden;
                [row refresh];
            }
            if (lifted) liftedRow = row;
        }];
    }
    // The lifted row draws above its neighbours.
    if (liftedRow) [self addSubview:liftedRow positioned:NSWindowAbove relativeTo:nil];

    if (animated && !APBReduceMotion()) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1.0];
            for (dispatch_block_t change in changes) change();
        }];
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0;
            for (dispatch_block_t change in changes) change();
        }];
    }
}

#pragma mark APBDeviceRowDelegate

- (void)row:(APBDeviceRowView *)row moveTo:(NSInteger)target {
    NSInteger source = row.index;
    if (source == target) return;
    NSInteger destination = target > source ? target + 1 : target;
    APBOutputCategory category = APBDeviceSectionCategory(row.section);
    if (category != APBOutputCategoryNone) {
        [_model moveOutputInCategory:category from:source to:destination];
    } else {
        [_model moveInputFrom:source to:destination];
    }
}

- (void)row:(APBDeviceRowView *)row dragChangedAt:(NSPoint)point translation:(CGSize)translation {
    BOOL started = _drag == nil;
    if (!_drag) _drag = [[APBDeviceDrag alloc] initWithDevice:row.device section:row.section index:row.index];
    APBDropTarget previous = _drag.target;
    [_drag updateHovered:[self.layoutModel targetAtY:point.y] translation:translation];
    BOOL targetChanged = started || !APBDropTargetEqual(previous, _drag.target);
    [self layoutRowsAnimated:targetChanged];
    if (targetChanged && _onDragChange) _onDragChange();
}

- (void)rowDragEnded:(APBDeviceRowView *)row {
    APBDeviceDrag *drag = _drag;
    [self endDragNotifying:NO];
    if (drag.target.exists) {
        [_model dropDevice:drag.device.identifier intoCategory:APBDeviceSectionCategory(drag.target.section) at:drag.target.index];
    }
    [self refresh];
    if (_onDragChange) _onDragChange();
}

- (void)endDragNotifying:(BOOL)notify {
    if (!_drag) return;
    APBDeviceRowView *row = _rows[_drag.device.identifier];
    _drag = nil;
    row.isLifted = NO;
    row.isForbidden = NO;
    [row refresh];
    if (notify) {
        [self layoutRowsAnimated:YES];
        if (_onDragChange) _onDragChange();
    }
}

- (void)cancelDrag {
    [self endDragNotifying:YES];
}

@end

#pragma mark - Panel

@implementation APBPanelView {
    APBAppModel *_model;
    NSSwitch *_automaticSwitch;
    NSTextField *_takeoverLabel;
    NSButton *_fixButton;
    NSStackView *_takeoverRow;
    NSTextField *_automationNote;
    APBLevelControl *_output;
    APBLevelControl *_microphone;
    NSScrollView *_scrollView;
    APBDeviceListsView *_lists;
    NSLayoutConstraint *_listHeight;
    NSButton *_showAll;
    APBHoverView *_settingsRow;
    CGFloat _lastHeight;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    self = [super initWithFrame:NSMakeRect(0, 0, APBPanelWidth, 400)];
    if (self) {
        _model = model;
        [self build];
        [self refresh];
    }
    return self;
}

- (void)build {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    // Header
    NSTextField *title = APBLabel(@"Automatic switching", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    [title setAccessibilityElement:NO];
    _automaticSwitch = [[NSSwitch alloc] init];
    _automaticSwitch.target = self;
    _automaticSwitch.action = @selector(toggleAutomatic:);
    _automaticSwitch.controlSize = NSControlSizeSmall;
    [_automaticSwitch setAccessibilityLabel:@"Automatic switching"];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *titleRow = [NSStackView stackViewWithViews:@[ title, spacer, _automaticSwitch ]];
    titleRow.alignment = NSLayoutAttributeCenterY;
    titleRow.toolTip = @"Use device priorities as availability changes";

    _takeoverLabel = APBWrappingLabel(@"", [NSFont systemFontOfSize:10], NSColor.secondaryLabelColor, 2);
    _fixButton = [NSButton buttonWithTitle:@"Fix in Settings…" target:self action:@selector(openHeadphoneSettings:)];
    _fixButton.bordered = NO;
    _fixButton.font = [NSFont systemFontOfSize:10];
    _fixButton.contentTintColor = NSColor.linkColor;
    _fixButton.attributedTitle = [[NSAttributedString alloc] initWithString:@"Fix in Settings…" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: NSColor.linkColor,
    }];
    _fixButton.toolTip = @"Under Connect to This Mac, choose When Last Connected to This Mac";
    _takeoverRow = [NSStackView stackViewWithViews:@[ _takeoverLabel, _fixButton ]];
    _takeoverRow.spacing = 6;
    _takeoverRow.alignment = NSLayoutAttributeFirstBaseline;
    _takeoverRow.detachesHiddenViews = YES;
    _automationNote = APBWrappingLabel(@"", [NSFont systemFontOfSize:10], NSColor.secondaryLabelColor, 2);

    NSStackView *header = [NSStackView stackViewWithViews:@[ titleRow, _takeoverRow, _automationNote ]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 2;
    header.detachesHiddenViews = YES;
    header.edgeInsets = NSEdgeInsetsMake(10, 12, 0, 12);
    [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor constant:-24].active = YES;
    [_automationNote.widthAnchor constraintLessThanOrEqualToAnchor:header.widthAnchor constant:-24].active = YES;
    [_takeoverRow.widthAnchor constraintLessThanOrEqualToAnchor:header.widthAnchor constant:-24].active = YES;

    // Levels
    __weak typeof(self) weakSelf = self;
    APBAppModel *model = _model;
    _output = [[APBLevelControl alloc] init];
    _output.name = @"Output";
    _output.uncontrollableNote = @"This device does not allow volume control";
    _output.toggleMute = ^{ [model setOutputMuted:!model.isActiveOutputMuted]; };
    _output.setLevel = ^(float level) { [model setVolume:level]; };
    _microphone = [[APBLevelControl alloc] init];
    _microphone.name = @"Microphone";
    _microphone.uncontrollableNote = @"This mic does not allow volume control";
    _microphone.toggleMute = ^{ [model setMicrophoneMuted:!model.isMicrophoneMuted]; };
    _microphone.setLevel = ^(float level) { [model setMicrophoneLevel:level]; };
    NSStackView *levels = [NSStackView stackViewWithViews:@[ _output, _microphone ]];
    levels.orientation = NSUserInterfaceLayoutOrientationVertical;
    levels.spacing = 8;
    levels.detachesHiddenViews = YES;
    levels.edgeInsets = NSEdgeInsetsMake(8, 12, 10, 12);
    [_output.widthAnchor constraintEqualToAnchor:levels.widthAnchor constant:-24].active = YES;
    [_microphone.widthAnchor constraintEqualToAnchor:levels.widthAnchor constant:-24].active = YES;

    // Lists
    _lists = [[APBDeviceListsView alloc] initWithModel:_model];
    _lists.onDragChange = ^{ [weakSelf updateListHeight]; };
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.documentView = _lists;
    _scrollView.contentView.drawsBackground = NO;
    _listHeight = [_scrollView.heightAnchor constraintEqualToConstant:200];
    _listHeight.active = YES;

    // Footer
    _showAll = [NSButton checkboxWithTitle:@"Show hidden and disconnected devices" target:self action:@selector(toggleShowAll:)];
    _showAll.font = [NSFont systemFontOfSize:13];
    NSView *showAllRow = [[NSView alloc] init];
    _showAll.translatesAutoresizingMaskIntoConstraints = NO;
    [showAllRow addSubview:_showAll];
    [NSLayoutConstraint activateConstraints:@[
        [_showAll.leadingAnchor constraintEqualToAnchor:showAllRow.leadingAnchor constant:12],
        [_showAll.trailingAnchor constraintLessThanOrEqualToAnchor:showAllRow.trailingAnchor constant:-12],
        [_showAll.centerYAnchor constraintEqualToAnchor:showAllRow.centerYAnchor],
        [showAllRow.heightAnchor constraintGreaterThanOrEqualToConstant:30],
    ]];

    // A plain button only hits its visible pixels, so the label gets the
    // whole row to click.
    _settingsRow = [[APBHoverView alloc] init];
    _settingsRow.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsRow.cornerRadius = 6;
    NSTextField *settingsLabel = APBLabel(@"Audio Priority Bar Settings…", [NSFont systemFontOfSize:13], NSColor.labelColor);
    settingsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsRow addSubview:settingsLabel];
    [NSLayoutConstraint activateConstraints:@[
        // Lines the text up with the checkbox title above, which starts 22
        // points past the box's leading edge.
        [settingsLabel.leadingAnchor constraintEqualToAnchor:_settingsRow.leadingAnchor constant:30],
        [settingsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_settingsRow.trailingAnchor constant:-8],
        [settingsLabel.centerYAnchor constraintEqualToAnchor:_settingsRow.centerYAnchor],
        [_settingsRow.heightAnchor constraintGreaterThanOrEqualToConstant:26],
    ]];
    APBHoverView *settingsRow = _settingsRow;
    _settingsRow.onHover = ^(BOOL hovering) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.12;
            settingsRow.fillColor = APBPrimary(hovering ? 0.1 : 0);
        }];
    };
    _settingsRow.onClick = ^{
        typeof(self) self = weakSelf;
        if (self.onShowSettings) self.onShowSettings();
    };
    [_settingsRow setAccessibilityElement:YES];
    [_settingsRow setAccessibilityRole:NSAccessibilityButtonRole];
    [_settingsRow setAccessibilityLabel:@"Audio Priority Bar Settings…"];
    NSView *settingsContainer = [[NSView alloc] init];
    [settingsContainer addSubview:_settingsRow];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsRow.leadingAnchor constraintEqualToAnchor:settingsContainer.leadingAnchor constant:4],
        [_settingsRow.trailingAnchor constraintEqualToAnchor:settingsContainer.trailingAnchor constant:-4],
        [_settingsRow.topAnchor constraintEqualToAnchor:settingsContainer.topAnchor constant:4],
        [_settingsRow.bottomAnchor constraintEqualToAnchor:settingsContainer.bottomAnchor constant:-4],
    ]];

    NSView *topDivider = [self paddedSeparator];
    NSView *bottomDivider = [self paddedSeparator];
    NSStackView *stack = [NSStackView stackViewWithViews:@[
        header, levels, topDivider, _scrollView, bottomDivider, showAllRow, settingsContainer,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 0;
    stack.alignment = NSLayoutAttributeLeading;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in stack.arrangedSubviews) {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    APBPanelBackgroundView *background = [[APBPanelBackgroundView alloc] initWithContent:stack];
    [self addSubview:background];
    [NSLayoutConstraint activateConstraints:@[
        [background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [background.topAnchor constraintEqualToAnchor:self.topAnchor],
        [background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.widthAnchor constraintEqualToConstant:APBPanelWidth],
    ]];
    [self setAccessibilityElement:NO];
}

- (NSView *)paddedSeparator {
    NSView *container = [[NSView alloc] init];
    APBSeparator *separator = [APBSeparator separator];
    [container addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [separator.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [separator.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        Pin([container.heightAnchor constraintEqualToConstant:1], NSLayoutPriorityRequired),
    ]];
    return container;
}

#pragma mark Refresh

- (void)refresh {
    APBAppModel *model = _model;
    _automaticSwitch.state = model.isManualMode ? NSControlStateValueOff : NSControlStateValueOn;

    APBAudioDevice *takeover = model.takeoverDevice;
    NSString *note = self.automationNote;
    _takeoverRow.hidden = takeover == nil;
    _automationNote.hidden = takeover != nil || note == nil;
    if (takeover) {
        _takeoverLabel.stringValue = [NSString stringWithFormat:@"macOS keeps switching to %@", takeover.name];
        _fixButton.hidden = !takeover.isBluetooth;
    }
    _automationNote.stringValue = note ?: @"";

    NSString *outputIcon = self.outputIcon;
    _output.deviceName = model.currentOutputDevice.name;
    _output.icon = model.isActiveOutputMuted ? @"speaker.slash.fill" : outputIcon;
    _output.toggledIcon = model.isActiveOutputMuted ? outputIcon : @"speaker.slash.fill";
    _output.isMuted = model.isActiveOutputMuted;
    _output.level = model.volume;
    _output.isControllable = model.isVolumeControllable;
    _output.canToggleMute = model.isOutputMutable;
    [_output update];

    _microphone.hidden = model.currentInputID == 0;
    _microphone.deviceName = model.currentInputDevice.name;
    _microphone.icon = model.isMicrophoneMuted ? @"mic.slash.fill" : @"mic.fill";
    _microphone.toggledIcon = model.isMicrophoneMuted ? @"mic.fill" : @"mic.slash.fill";
    _microphone.isMuted = model.isMicrophoneMuted;
    _microphone.level = model.microphoneLevel;
    _microphone.isControllable = model.isMicrophoneLevelControllable;
    _microphone.canToggleMute = model.isMicrophoneMutable;
    [_microphone update];

    _showAll.state = model.showAll ? NSControlStateValueOn : NSControlStateValueOff;
    [_lists refresh];
    [self updateListHeight];
}

- (CGFloat)maximumListHeight {
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(NSEvent.mouseLocation, candidate.frame)) screen = candidate;
    }
    screen = screen ?: NSScreen.mainScreen;
    CGFloat visible = screen ? NSHeight(screen.visibleFrame) : 900;
    return MIN(500, MAX(240, visible / 2));
}

/// Only ever grows for a drag, so a preview that adds a row cannot clip the
/// bottom of the list, and one that removes a row cannot resize the panel out
/// from under the cursor.
- (void)updateListHeight {
    CGFloat content = _lists.contentHeight;
    CGFloat maximum = self.maximumListHeight;
    CGFloat height = MIN(content, maximum);
    _lists.frame = NSMakeRect(0, 0, APBPanelWidth, MAX(content, height));
    _scrollView.hasVerticalScroller = height >= maximum;
    if (_listHeight.constant != height) {
        _listHeight.constant = height;
        [self layoutSubtreeIfNeeded];
    }
    CGFloat fitting = self.fittingSize.height;
    if (fitting != _lastHeight) {
        _lastHeight = fitting;
        if (_onSizeChange) _onSizeChange();
    }
}

- (void)cancelDrag {
    [_lists cancelDrag];
}

/// The current output's hardware icon, so it is clear which device the slider
/// controls. A generic speaker shows the volume level instead, or full waves
/// when the device has no volume to show.
- (NSString *)outputIcon {
    APBAudioDevice *output = _model.currentOutputDevice;
    NSString *hardware = output
        ? [output hardwareIconForCategory:_model.activeOutputCategory]
        : (_model.activeOutputCategory == APBOutputCategoryHeadphone ? @"headphones" : APBGenericSpeakerIcon);
    if (![hardware isEqualToString:APBGenericSpeakerIcon]) return hardware;
    if (!_model.isVolumeControllable) return @"speaker.wave.3.fill";
    float volume = _model.volume;
    if (volume <= 0) return @"speaker.fill";
    if (volume < 0.33) return @"speaker.wave.1.fill";
    if (volume < 0.66) return @"speaker.wave.2.fill";
    return @"speaker.wave.3.fill";
}

/// Why automatic switching chose what it did, shown only when there is
/// something the lists and the toggle do not already say.
- (NSString *)automationNote {
    APBAudioDevice *current = _model.currentOutputDevice;
    if (!current) return @"No output selected";
    if (_model.isManualMode) return @"Your choice stays until you turn this on";
    APBSkippedOutput *skipped = _model.automaticOutputDecision.skipped;
    if (!skipped || [skipped.device.identifier isEqualToString:current.identifier]) return nil;
    NSString *reason = skipped.reason == APBOutputSkipReasonOff ? @"headset off" : @"never auto-selected";
    return [NSString stringWithFormat:@"Skipping %@: %@", skipped.device.name, reason];
}

#pragma mark Actions

- (void)toggleAutomatic:(NSSwitch *)sender {
    [_model setManualMode:sender.state != NSControlStateValueOn];
}

- (void)toggleShowAll:(NSButton *)sender {
    _model.showAll = sender.state == NSControlStateValueOn;
    [_model refreshDevices];
}

- (void)openHeadphoneSettings:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:HeadphoneSettingsURL]];
}

@end
