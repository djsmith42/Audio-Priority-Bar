#import "PanelViewController.h"
#import "DeviceIcon.h"
#import "DeviceListView.h"
#import "UIHelpers.h"

static const CGFloat PanelWidth = 380;

static NSView *Padded(NSView *content, NSEdgeInsets insets) {
    NSView *container = [[NSView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [content.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
    ]];
    return container;
}

/// The round mute button. Hovering previews what a click will do.
@interface APBMuteButton : NSButton
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *toggledIcon;
@property (nonatomic) BOOL isMuted;
@property (nonatomic) BOOL canToggle;
@end

@implementation APBMuteButton {
    NSTrackingArea *_trackingArea;
    BOOL _isHovering;
    /// Set by a click so the result shows until the pointer leaves, instead
    /// of the preview flipping straight back to the previous state.
    BOOL _isPreviewSuppressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.imagePosition = NSImageOnly;
        self.buttonType = NSButtonTypeMomentaryChange;
        [self.widthAnchor constraintEqualToConstant:26].active = YES;
        [self.heightAnchor constraintEqualToConstant:26].active = YES;
    }
    return self;
}

- (void)refresh {
    BOOL preview = _isHovering && _canToggle && !_isPreviewSuppressed;
    self.image = APBSymbol(preview ? _toggledIcon : _icon, APBBodySize, NSFontWeightRegular);
    self.contentTintColor = _isMuted ? NSColor.systemRedColor : NSColor.labelColor;
    self.enabled = _canToggle;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Always filled so the icon reads as a button, and tinted while muted.
    NSColor *fill = _isMuted
        ? [NSColor.systemRedColor colorWithAlphaComponent:_isHovering ? 0.3 : 0.2]
        : APBPrimary(_isHovering ? 0.24 : 0.16);
    [fill setFill];
    [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
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

- (void)mouseEntered:(NSEvent *)event {
    _isHovering = YES;
    [self refresh];
}

- (void)mouseExited:(NSEvent *)event {
    _isHovering = NO;
    _isPreviewSuppressed = NO;
    [self refresh];
}

- (BOOL)sendAction:(SEL)action to:(id)target {
    _isPreviewSuppressed = YES;
    return [super sendAction:action to:target];
}

@end

/// One row for the current output or microphone: the icon mutes, the slider
/// sets the level. Both rows share it so they look and behave alike.
@interface APBLevelControl : NSView
@property (nonatomic, copy) NSString *name;
/// The device the row controls, named in the tooltip and for VoiceOver
/// rather than taking a line of its own.
@property (nonatomic, copy, nullable) NSString *deviceName;
@property (nonatomic) float level;
@property (nonatomic) BOOL isMuted;
@property (nonatomic) BOOL isControllable;
/// Shown in place of the slider when the level cannot be set, so a disabled
/// slider is not mistaken for a broken one.
@property (nonatomic, copy) NSString *uncontrollableNote;
@property (nonatomic, readonly) APBMuteButton *muteButton;
@property (nonatomic, copy) void (^toggleMute)(void);
@property (nonatomic, copy) void (^setLevel)(float level);
- (void)refresh;
@end

@implementation APBLevelControl {
    NSSlider *_slider;
    NSTextField *_percent;
    NSStackView *_sliderRow;
    NSTextField *_note;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _muteButton = [[APBMuteButton alloc] init];
        _muteButton.target = self;
        _muteButton.action = @selector(muteClicked:);

        _slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(sliderMoved:)];
        _slider.controlSize = NSControlSizeSmall;
        _slider.continuous = YES;
        NSFont *digits = [NSFont monospacedDigitSystemFontOfSize:APBCalloutSize weight:NSFontWeightRegular];
        _percent = APBLabel(@"", digits, NSColor.secondaryLabelColor);
        _percent.accessibilityElement = NO;
        // Sized to the widest value, so it sits close to the slider without
        // the slider resizing as the digits change.
        CGFloat widest = ceil([@"100%" sizeWithAttributes:@{NSFontAttributeName: digits}].width) + 4;
        [_percent.widthAnchor constraintEqualToConstant:widest].active = YES;
        _sliderRow = [NSStackView stackViewWithViews:@[_slider, _percent]];
        _sliderRow.spacing = 6;
        [_slider setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

        _note = APBLabel(@"", [NSFont systemFontOfSize:APBCalloutSize], NSColor.tertiaryLabelColor);
        [_note setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView *row = [NSStackView stackViewWithViews:@[_muteButton, _sliderRow, _note]];
        row.spacing = 10;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (NSString *)muteTitle {
    return [NSString stringWithFormat:@"%@ %@", _isMuted ? @"Unmute" : @"Mute", _deviceName ?: _name];
}

- (void)refresh {
    [_muteButton refresh];
    _muteButton.toolTip = self.muteTitle;
    _muteButton.accessibilityLabel = self.muteTitle;
    BOOL showsNote = !_isControllable && _uncontrollableNote.length;
    _note.hidden = !showsNote;
    _sliderRow.hidden = showsNote;
    _note.stringValue = _uncontrollableNote ?: @"";
    _note.toolTip = _deviceName ?: _name;
    if (fabs(_slider.doubleValue - _level) > 0.0001) _slider.doubleValue = _level;
    _slider.enabled = _isControllable;
    _slider.alphaValue = _isMuted ? 0.5 : 1;
    _slider.toolTip = _deviceName ?: _name;
    _slider.accessibilityLabel = [NSString stringWithFormat:@"%@ volume", _name];
    NSMutableArray *values = [NSMutableArray arrayWithObject:_isControllable
        ? [NSString stringWithFormat:@"%d percent", (int)(_level * 100)] : @"Unavailable"];
    if (_isMuted) [values insertObject:@"Muted" atIndex:0];
    if (_deviceName) [values addObject:_deviceName];
    _slider.accessibilityValueDescription = [values componentsJoinedByString:@", "];
    _percent.stringValue = _isControllable ? [NSString stringWithFormat:@"%d%%", (int)(_level * 100)] : @"—";
}

- (void)muteClicked:(id)sender {
    if (_toggleMute) _toggleMute();
}

- (void)sliderMoved:(NSSlider *)slider {
    if (_setLevel) _setLevel((float)slider.doubleValue);
}

- (void)scrollWheel:(NSEvent *)event {
    if (!_isControllable || !_setLevel) return;
    _setLevel(MAX(0, MIN(1, _level + (float)(event.deltaY * 0.02))));
}

@end

@implementation APBPanelViewController {
    APBAppModel *_model;
    void (^_showSettings)(void);
    NSSwitch *_automatic;
    NSStackView *_takeover;
    NSTextField *_takeoverText;
    NSButton *_fixButton;
    NSTextField *_automationNote;
    APBLevelControl *_output;
    APBLevelControl *_microphone;
    NSScrollView *_scrollView;
    NSLayoutConstraint *_listHeight;
    APBDeviceListView *_list;
    NSButton *_showAll;
    NSSize _lastSize;
}

- (instancetype)initWithModel:(APBAppModel *)model showSettings:(void (^)(void))showSettings {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _model = model;
        _showSettings = [showSettings copy];
    }
    return self;
}

- (void)loadView {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 0;

    APBAddArranged(stack, Padded(self.header, NSEdgeInsetsMake(10, 12, 0, 12)), PanelWidth);
    APBAddArranged(stack, Padded(self.levels, NSEdgeInsetsMake(8, 12, 10, 12)), PanelWidth);
    APBAddArranged(stack, Padded([[APBSeparatorView alloc] init], NSEdgeInsetsMake(0, 12, 0, 12)), PanelWidth);

    _list = [[APBDeviceListView alloc] initWithModel:_model];
    __weak typeof(self) weakSelf = self;
    _list.onHeightChange = ^{ [weakSelf updateListHeight]; };
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.drawsBackground = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.documentView = _list;
    _scrollView.contentView.drawsBackground = NO;
    _listHeight = [_scrollView.heightAnchor constraintEqualToConstant:200];
    _listHeight.active = YES;
    APBAddArranged(stack, _scrollView, PanelWidth);

    APBAddArranged(stack, Padded([[APBSeparatorView alloc] init], NSEdgeInsetsMake(0, 12, 0, 12)), PanelWidth);
    APBAddArranged(stack, self.footer, PanelWidth);

    self.view = [[APBPanelBackgroundView alloc] initWithContent:stack];
    [self reload];
}

- (NSView *)header {
    NSTextField *title = APBLabel(@"Automatic switching", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                  NSColor.labelColor);
    title.accessibilityElement = NO;
    _automatic = [[NSSwitch alloc] init];
    _automatic.target = self;
    _automatic.action = @selector(automaticToggled:);
    _automatic.accessibilityLabel = @"Automatic switching";
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *titleRow = [NSStackView stackViewWithViews:@[title, spacer, _automatic]];
    titleRow.toolTip = @"Use device priorities as availability changes";

    NSFont *caption = [NSFont systemFontOfSize:APBCaptionSize];
    _takeoverText = [NSTextField wrappingLabelWithString:@""];
    _takeoverText.font = caption;
    _takeoverText.textColor = NSColor.secondaryLabelColor;
    _takeoverText.maximumNumberOfLines = 2;
    _fixButton = [NSButton buttonWithTitle:@"Fix in Settings…" target:self action:@selector(openHeadphoneSettings:)];
    _fixButton.bordered = NO;
    _fixButton.attributedTitle = [[NSAttributedString alloc] initWithString:@"Fix in Settings…" attributes:@{
        NSFontAttributeName: caption,
        NSForegroundColorAttributeName: NSColor.linkColor,
    }];
    _fixButton.toolTip = @"Under Connect to This Mac, choose When Last Connected to This Mac";
    [_fixButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    _takeover = [NSStackView stackViewWithViews:@[_takeoverText, _fixButton]];
    _takeover.spacing = 6;
    _automationNote = [NSTextField wrappingLabelWithString:@""];
    _automationNote.font = caption;
    _automationNote.textColor = NSColor.secondaryLabelColor;
    _automationNote.maximumNumberOfLines = 2;

    NSStackView *header = [NSStackView stackViewWithViews:@[titleRow, _takeover, _automationNote]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 2;
    [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor].active = YES;
    [_automationNote.widthAnchor constraintLessThanOrEqualToAnchor:header.widthAnchor].active = YES;
    [_takeover.widthAnchor constraintLessThanOrEqualToAnchor:header.widthAnchor].active = YES;
    _automationNote.preferredMaxLayoutWidth = PanelWidth - 24;
    return header;
}

- (NSView *)levels {
    // The model outlives the panel, so the blocks hold it directly.
    APBAppModel *model = _model;
    _output = [[APBLevelControl alloc] init];
    _output.name = @"Output";
    _output.uncontrollableNote = @"This device does not allow volume control";
    _output.toggleMute = ^{ [model setOutputMuted:!model.isActiveOutputMuted]; };
    _output.setLevel = ^(float level) { [model changeVolume:level]; };
    _microphone = [[APBLevelControl alloc] init];
    _microphone.name = @"Microphone";
    _microphone.uncontrollableNote = @"This mic does not allow volume control";
    _microphone.toggleMute = ^{ [model setMicrophoneMuted:!model.isMicrophoneMuted]; };
    _microphone.setLevel = ^(float level) { [model changeMicrophoneLevel:level]; };
    NSStackView *levels = [[NSStackView alloc] init];
    levels.orientation = NSUserInterfaceLayoutOrientationVertical;
    levels.spacing = 8;
    APBAddArranged(levels, _output, PanelWidth - 24);
    APBAddArranged(levels, _microphone, PanelWidth - 24);
    return levels;
}

- (NSView *)footer {
    __weak typeof(self) weakSelf = self;
    _showAll = [NSButton checkboxWithTitle:@"Show hidden and disconnected devices"
                                    target:self
                                    action:@selector(showAllToggled:)];
    _showAll.font = [NSFont systemFontOfSize:13];
    APBHoverRowView *showAllRow = [[APBHoverRowView alloc] init];
    // The highlight covers the whole row, so the whole row toggles.
    showAllRow.action = ^{ [weakSelf toggleShowAll]; };
    [showAllRow addSubview:Padded(_showAll, NSEdgeInsetsMake(1, 8, 1, 8))];
    [self pin:showAllRow.subviews.firstObject to:showAllRow];
    [showAllRow.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;

    NSImageView *gear = [NSImageView imageViewWithImage:APBSymbol(@"gearshape", 13, NSFontWeightRegular)];
    gear.contentTintColor = NSColor.labelColor;
    // Fills the gap that lines the text up with the checkbox title above,
    // which starts 22 points past the box's leading edge.
    [gear.widthAnchor constraintEqualToConstant:30].active = YES;
    gear.imageAlignment = NSImageAlignCenter;
    NSTextField *settingsTitle = APBLabel(@"Audio Priority Bar Settings…", [NSFont systemFontOfSize:13], NSColor.labelColor);
    NSStackView *settingsContent = [NSStackView stackViewWithViews:@[gear, settingsTitle]];
    settingsContent.spacing = 0;
    APBHoverRowView *settingsRow = [[APBHoverRowView alloc] init];
    settingsRow.action = ^{
        APBPanelViewController *controller = weakSelf;
        if (controller) controller->_showSettings();
    };
    settingsRow.accessibilityElement = YES;
    settingsRow.accessibilityRole = NSAccessibilityButtonRole;
    settingsRow.accessibilityLabel = @"Audio Priority Bar Settings…";
    [settingsRow addSubview:Padded(settingsContent, NSEdgeInsetsMake(2, 0, 2, 8))];
    [self pin:settingsRow.subviews.firstObject to:settingsRow];
    [settingsRow.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;

    // Matches the system Wi-Fi menu, which keeps equal space around its
    // show-hidden toggle. Both values sit outside the highlight box.
    NSStackView *footer = [[NSStackView alloc] init];
    footer.orientation = NSUserInterfaceLayoutOrientationVertical;
    footer.spacing = 0;
    APBAddArranged(footer, Padded(showAllRow, NSEdgeInsetsMake(6, 4, 6, 4)), PanelWidth);
    APBAddArranged(footer, Padded([[APBSeparatorView alloc] init], NSEdgeInsetsMake(0, 12, 0, 12)), PanelWidth);
    APBAddArranged(footer, Padded(settingsRow, NSEdgeInsetsMake(6, 4, 6, 4)), PanelWidth);
    return footer;
}

- (void)pin:(NSView *)view to:(NSView *)container {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
}

#pragma mark - Updates

- (void)reload {
    if (!self.isViewLoaded) return;
    _automatic.state = _model.isManualMode ? NSControlStateValueOff : NSControlStateValueOn;
    APBAudioDevice *takeover = _model.takeoverDevice;
    NSString *note = self.automationNote;
    _takeover.hidden = takeover == nil;
    _takeoverText.stringValue = takeover ? [NSString stringWithFormat:@"macOS keeps switching to %@", takeover.name] : @"";
    _fixButton.hidden = !takeover.isBluetooth;
    _automationNote.hidden = takeover != nil || note == nil;
    _automationNote.stringValue = note ?: @"";

    NSString *outputIcon = self.outputIcon;
    APBMuteButton *outputButton = _output.muteButton;
    BOOL outputMuted = _model.isActiveOutputMuted;
    outputButton.icon = outputMuted ? @"speaker.slash.fill" : outputIcon;
    outputButton.toggledIcon = outputMuted ? outputIcon : @"speaker.slash.fill";
    outputButton.isMuted = outputMuted;
    outputButton.canToggle = _model.isOutputMutable;
    _output.deviceName = _model.currentOutputDevice.name;
    _output.isMuted = outputMuted;
    _output.level = _model.volume;
    _output.isControllable = _model.isVolumeControllable;
    [_output refresh];

    _microphone.hidden = _model.currentInputID == nil;
    BOOL micMuted = _model.isMicrophoneMuted;
    APBMuteButton *micButton = _microphone.muteButton;
    micButton.icon = micMuted ? @"mic.slash.fill" : @"mic.fill";
    micButton.toggledIcon = micMuted ? @"mic.fill" : @"mic.slash.fill";
    micButton.isMuted = micMuted;
    micButton.canToggle = _model.isMicrophoneMutable;
    _microphone.deviceName = _model.currentInputDevice.name;
    _microphone.isMuted = micMuted;
    _microphone.level = _model.microphoneLevel;
    _microphone.isControllable = _model.isMicrophoneLevelControllable;
    [_microphone refresh];

    _showAll.state = _model.showAll ? NSControlStateValueOn : NSControlStateValueOff;
    [_list reload];
    [self updateListHeight];
}

- (CGFloat)maximumListHeight {
    NSPoint mouse = NSEvent.mouseLocation;
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(mouse, candidate.frame)) {
            screen = candidate;
            break;
        }
    }
    CGFloat visible = screen ? NSHeight(screen.visibleFrame) : 900;
    return MIN(500, MAX(240, visible / 2));
}

- (void)updateListHeight {
    CGFloat content = _list.contentHeight;
    CGFloat maximum = self.maximumListHeight;
    CGFloat height = MIN(content, maximum);
    [_list setFrameSize:NSMakeSize(PanelWidth, content)];
    _scrollView.hasVerticalScroller = height >= maximum;
    if (_listHeight.constant != height) _listHeight.constant = height;
    [self.view layoutSubtreeIfNeeded];
    NSSize size = self.view.fittingSize;
    if (!NSEqualSizes(size, _lastSize)) {
        _lastSize = size;
        if (_onSizeChange) _onSizeChange();
    }
}

- (void)cancelDrag {
    [_list cancelDrag];
}

/// The current output's hardware icon, so it is clear which device the
/// slider controls. A generic speaker shows the volume level instead, or full
/// waves when the device has no volume to show.
- (NSString *)outputIcon {
    APBAudioDevice *output = _model.currentOutputDevice;
    NSString *hardware = output
        ? [output hardwareIconForCategory:_model.activeOutputCategory]
        : (_model.activeOutputCategory == APBOutputCategoryHeadphone ? @"headphones" : APBAudioDevice.genericSpeakerIcon);
    if (![hardware isEqualToString:APBAudioDevice.genericSpeakerIcon]) return hardware;
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

#pragma mark - Actions

- (void)automaticToggled:(NSSwitch *)sender {
    [_model setManualMode:sender.state != NSControlStateValueOn];
}

- (void)openHeadphoneSettings:(id)sender {
    // The AirPods page, which holds their Connect to This Mac setting.
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.HeadphoneSettings"]];
}

- (void)showAllToggled:(NSButton *)sender {
    _model.showAll = sender.state == NSControlStateValueOn;
    [_model refreshDevices];
}

- (void)toggleShowAll {
    _model.showAll = !_model.showAll;
    [_model refreshDevices];
}

@end
