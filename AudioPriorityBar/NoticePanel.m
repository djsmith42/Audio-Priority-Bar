#import "NoticePanel.h"
#import "DeviceIcon.h"
#import "UIHelpers.h"

static const NSTimeInterval SwitchDuration = 1.5;

static NSPanel *FloatingPanel(void) {
    NSPanel *window = [[NSPanel alloc] initWithContentRect:NSZeroRect
                                                 styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    window.level = NSStatusWindowLevel;
    window.ignoresMouseEvents = YES;
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    window.hasShadow = YES;
    window.releasedWhenClosed = NO;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorFullScreenAuxiliary
        | NSWindowCollectionBehaviorIgnoresCycle;
    return window;
}

static void Pin(NSView *view, NSView *container, NSEdgeInsets insets) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
    ]];
}

/// The notice's rounded bubble: one line per device, its icon and name, on
/// the regular material.
@interface APBNoticeBubble : NSView
@property (nonatomic, copy, nullable) void (^onDismiss)(void);
- (instancetype)initWithContent:(APBNoticeContent *)content onDismiss:(nullable void (^)(void))onDismiss;
@end

@implementation APBNoticeBubble {
    NSVisualEffectView *_material;
    BOOL _isCapsule;
}

- (instancetype)initWithContent:(APBNoticeContent *)content onDismiss:(void (^)(void))onDismiss {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _onDismiss = [onDismiss copy];
        // A capsule for one line; two lines would make its ends look swollen.
        _isCapsule = content.lines.count <= 1;
        _material = [[NSVisualEffectView alloc] init];
        _material.material = NSVisualEffectMaterialPopover;
        _material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _material.state = NSVisualEffectStateActive;
        [self addSubview:_material];
        Pin(_material, self, NSEdgeInsetsZero);

        NSStackView *lines = [[NSStackView alloc] init];
        lines.orientation = NSUserInterfaceLayoutOrientationVertical;
        lines.alignment = NSLayoutAttributeLeading;
        lines.spacing = 6;
        for (APBNoticeLine *line in content.lines) {
            NSImageView *icon = [NSImageView imageViewWithImage:APBSymbol(line.icon, APBBodySize, NSFontWeightRegular) ?: [[NSImage alloc] init]];
            icon.contentTintColor = NSColor.labelColor;
            // A shared width keeps the text of every line aligned.
            [icon.widthAnchor constraintEqualToConstant:18].active = YES;
            NSTextField *text = APBLabel(line.text, [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.labelColor);
            NSStackView *row = [NSStackView stackViewWithViews:@[icon, text]];
            row.spacing = 8;
            [lines addArrangedSubview:row];
        }
        [_material addSubview:lines];
        Pin(lines, _material, NSEdgeInsetsMake(8, 14, 8, 14));

        if (onDismiss) {
            self.accessibilityElement = YES;
            self.accessibilityRole = NSAccessibilityButtonRole;
            self.accessibilityLabel = content.announcement;
            self.accessibilityHelp = @"Hides the reminder until you next record while muted";
        }
    }
    return self;
}

- (void)layout {
    [super layout];
    CGFloat radius = _isCapsule ? NSHeight(self.bounds) / 2 : 14;
    CGFloat edge = radius * 2 + 1;
    NSImage *mask = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    _material.maskImage = mask;
}

- (void)mouseUp:(NSEvent *)event {
    if (_onDismiss) _onDismiss();
}

- (BOOL)accessibilityPerformPress {
    if (!_onDismiss) return NO;
    _onDismiss();
    return YES;
}

@end

@implementation APBNoticePanel {
    NSPanel *_window;
    APBPlacement _placement;
    APBNoticeContent *_switchNotice;
    NSUInteger _clearGeneration;
    APBNoticeContent *_shown;
}

- (instancetype)initWithPlacement:(APBPlacement)placement {
    if ((self = [super init])) {
        _placement = [placement copy];
        _window = FloatingPanel();
    }
    return self;
}

- (void)setShowsMutedReminder:(BOOL)showsMutedReminder {
    if (_showsMutedReminder == showsMutedReminder) return;
    _showsMutedReminder = showsMutedReminder;
    [self update];
}

- (void)setIsSuppressed:(BOOL)isSuppressed {
    if (_isSuppressed == isSuppressed) return;
    _isSuppressed = isSuppressed;
    [self update];
}

- (void)showSwitch:(APBNoticeContent *)content {
    if (_isSuppressed) return;
    _switchNotice = content;
    NSUInteger generation = ++_clearGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SwitchDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        APBNoticePanel *panel = weakSelf;
        if (!panel || panel->_clearGeneration != generation) return;
        panel->_switchNotice = nil;
        [panel update];
    });
    [self update];
}

- (void)update {
    APBNoticeContent *content = [APBNoticeContent currentWithSwitchNotice:_switchNotice
                                                       showsMutedReminder:_showsMutedReminder
                                                             isSuppressed:_isSuppressed];
    if (content == _shown || [content isEqual:_shown]) return;
    _shown = content;
    BOOL isReminder = [content isEqual:APBNoticeContent.mutedWhileRecording];
    _window.ignoresMouseEvents = !isReminder;
    BOOL animates = !APBReduceMotion();
    if (!content) {
        if (!animates) {
            [_window orderOut:nil];
            return;
        }
        __weak typeof(self) weakSelf = self;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            self->_window.animator.alphaValue = 0;
        } completionHandler:^{
            APBNoticePanel *panel = weakSelf;
            if (panel && !panel->_shown) [panel->_window orderOut:nil];
        }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    APBNoticeBubble *bubble = [[APBNoticeBubble alloc] initWithContent:content onDismiss:isReminder ? ^{
        APBNoticePanel *panel = weakSelf;
        if (panel.onDismissMutedReminder) panel.onDismissMutedReminder();
    } : nil];
    _window.contentView = bubble;
    [bubble layoutSubtreeIfNeeded];
    NSSize size = bubble.fittingSize;
    [_window setContentSize:size];
    NSValue *origin = _placement(size);
    if (origin) [_window setFrameOrigin:origin.pointValue];
    if (!_window.isVisible) _window.alphaValue = animates ? 0 : 1;
    [_window orderFrontRegardless];
    if (animates) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            self->_window.animator.alphaValue = 1;
        }];
    } else {
        _window.alphaValue = 1;
    }
    NSAccessibilityPostNotificationWithUserInfo(NSApp, NSAccessibilityAnnouncementRequestedNotification, @{
        NSAccessibilityAnnouncementKey: content.announcement,
        NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh),
    });
}

@end

/// A read-only volume meter, dimmed while muted like the panel's slider.
/// Drawn in the text color with no thumb or value, so it does not read as a
/// slider to drag.
@interface APBLevelBar : NSView
@property (nonatomic) float level;
@property (nonatomic) BOOL isMuted;
@end

@implementation APBLevelBar

- (NSSize)intrinsicContentSize {
    return NSMakeSize(120, 4);
}

- (void)setLevel:(float)level {
    _level = level;
    self.needsDisplay = YES;
}

- (void)setIsMuted:(BOOL)isMuted {
    _isMuted = isMuted;
    self.alphaValue = isMuted ? 0.5 : 1;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat radius = NSHeight(bounds) / 2;
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    [APBPrimary(0.1) setFill];
    [track fill];
    [NSGraphicsContext saveGraphicsState];
    [track addClip];
    [NSColor.labelColor setFill];
    CGFloat width = NSWidth(bounds) * MAX(0, MIN(1, (CGFloat)_level));
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, width, NSHeight(bounds)) xRadius:radius yRadius:radius] fill];
    [NSGraphicsContext restoreGraphicsState];
}

@end

/// Icon, name, and mute status styled as in the device list, with the level
/// underneath when the device reports one.
@interface APBPreviewRow : NSStackView
@property (nonatomic, readonly) NSImageView *icon;
@property (nonatomic, readonly) NSTextField *name;
@property (nonatomic, readonly) APBLevelBar *levelBar;
@end

@implementation APBPreviewRow

- (instancetype)init {
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.spacing = 8;
        self.alignment = NSLayoutAttributeCenterY;
        _icon = [[NSImageView alloc] init];
        [_icon.widthAnchor constraintEqualToConstant:20].active = YES;
        _name = APBLabel(@"", [NSFont systemFontOfSize:13], NSColor.labelColor);
        _levelBar = [[APBLevelBar alloc] init];
        NSStackView *text = [NSStackView stackViewWithViews:@[_name, _levelBar]];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 4;
        [self addArrangedSubview:_icon];
        [self addArrangedSubview:text];
    }
    return self;
}

@end

@interface APBHoverPreviewView : NSView
- (instancetype)initWithModel:(APBAppModel *)model;
- (void)update;
@end

@implementation APBHoverPreviewView {
    APBAppModel *_model;
    NSTextField *_state;
    NSStackView *_headsetOff;
    APBPreviewRow *_output;
    APBPreviewRow *_input;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    if ((self = [super initWithFrame:NSZeroRect])) {
        _model = model;
        NSTextField *title = APBLabel(@"Automatic switching", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
        _state = APBLabel(@"", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
        NSView *spacer = [[NSView alloc] init];
        [spacer.widthAnchor constraintGreaterThanOrEqualToConstant:16].active = YES;
        [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *titleRow = [NSStackView stackViewWithViews:@[title, spacer, _state]];
        titleRow.spacing = 0;
        // What the tooltip used to explain behind the warning glyph.
        NSImageView *warning = [NSImageView imageViewWithImage:APBSymbol(@"exclamationmark.triangle.fill", APBCaptionSize, NSFontWeightRegular)];
        warning.contentTintColor = NSColor.secondaryLabelColor;
        _headsetOff = [NSStackView stackViewWithViews:@[warning, APBLabel(@"Headset off", [NSFont systemFontOfSize:APBCaptionSize], NSColor.secondaryLabelColor)]];
        _headsetOff.spacing = 3;
        NSStackView *header = [NSStackView stackViewWithViews:@[titleRow, _headsetOff]];
        header.orientation = NSUserInterfaceLayoutOrientationVertical;
        header.alignment = NSLayoutAttributeLeading;
        header.spacing = 2;
        [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor].active = YES;

        _output = [[APBPreviewRow alloc] init];
        _input = [[APBPreviewRow alloc] init];
        NSStackView *rows = [NSStackView stackViewWithViews:@[_output, _input]];
        rows.orientation = NSUserInterfaceLayoutOrientationVertical;
        rows.alignment = NSLayoutAttributeLeading;
        rows.spacing = 14;

        APBSeparatorView *divider = [[APBSeparatorView alloc] init];
        // In the panel's order: its header, then output, then microphone.
        NSStackView *stack = [NSStackView stackViewWithViews:@[header, divider, rows]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 10;
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [divider.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

        APBPanelBackgroundView *background = [[APBPanelBackgroundView alloc] initWithContent:[self padded:stack]];
        [self addSubview:background];
        Pin(background, self, NSEdgeInsetsZero);
        [self update];
    }
    return self;
}

- (NSView *)padded:(NSView *)content {
    NSView *container = [[NSView alloc] init];
    [container addSubview:content];
    Pin(content, container, NSEdgeInsetsMake(10, 12, 12, 12));
    return container;
}

- (void)update {
    _state.stringValue = _model.isManualMode ? @"Off" : @"On";
    _headsetOff.hidden = !_model.isActiveOutputLinkDown;
    [self configure:_output
             device:_model.currentOutputDevice
        placeholder:@"No output"
          showsLevel:_model.isVolumeControllable
              level:_model.volume];
    [self configure:_input
             device:_model.currentInputDevice
        placeholder:@"No microphone"
          showsLevel:_model.isMicrophoneLevelControllable
              level:_model.microphoneLevel];
}

- (void)configure:(APBPreviewRow *)row
           device:(APBAudioDevice *)device
      placeholder:(NSString *)placeholder
       showsLevel:(BOOL)showsLevel
            level:(float)level {
    BOOL isMuted = device ? [_model isMuted:device] : NO;
    NSString *iconName = @"questionmark";
    if (isMuted) {
        iconName = device.role == APBDeviceRoleInput ? @"mic.slash.fill" : @"speaker.slash.fill";
    } else if (device) {
        iconName = [device hardwareIconForCategory:device.role == APBDeviceRoleOutput
                    ? [_model.store categoryForDevice:device] : APBOutputCategoryNone];
    }
    // No circle, unlike the panel's buttons, since nothing here can be
    // clicked. Muted shows as the panel's mute button does.
    row.icon.image = APBSymbol(iconName, 14, NSFontWeightRegular);
    row.icon.contentTintColor = isMuted ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    row.name.stringValue = device.name ?: placeholder;
    row.name.textColor = device ? NSColor.labelColor : NSColor.secondaryLabelColor;
    row.levelBar.hidden = !(device && showsLevel);
    row.levelBar.level = level;
    row.levelBar.isMuted = isMuted;
}

@end

@implementation APBHoverPreviewPanel {
    NSPanel *_window;
    APBHoverPreviewView *_view;
    APBPlacement _placement;
}

- (instancetype)initWithModel:(APBAppModel *)model placement:(APBPlacement)placement {
    if ((self = [super init])) {
        _placement = [placement copy];
        _window = FloatingPanel();
        _view = [[APBHoverPreviewView alloc] initWithModel:model];
        _window.contentView = _view;
        // Follows the content, such as a device being renamed or muted while
        // the preview is up.
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(modelDidChange:)
                                                   name:APBAppModelDidChangeNotification
                                                 object:model];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)isVisible {
    return _window.isVisible;
}

- (void)modelDidChange:(NSNotification *)notification {
    if (!_window.isVisible) return;
    [_view update];
    [self fit];
}

- (void)fit {
    [_view layoutSubtreeIfNeeded];
    NSSize size = _view.fittingSize;
    [_window setContentSize:size];
    NSValue *origin = _placement(size);
    if (origin) [_window setFrameOrigin:origin.pointValue];
}

- (void)show {
    [_view update];
    [self fit];
    [_window orderFrontRegardless];
}

- (void)hide {
    [_window orderOut:nil];
}

@end
