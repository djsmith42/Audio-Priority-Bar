#import "APBNoticePanel.h"
#import "APBDeviceIcon.h"
#import "APBUI.h"

static const NSTimeInterval SwitchDuration = 1.5;

@implementation APBNoticeLine

+ (instancetype)lineWithIcon:(NSString *)icon text:(NSString *)text {
    APBNoticeLine *line = [[self alloc] init];
    line->_icon = [icon copy];
    line->_text = [text copy];
    return line;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBNoticeLine.class]) return NO;
    APBNoticeLine *other = object;
    return [_icon isEqualToString:other->_icon] && [_text isEqualToString:other->_text];
}

- (NSUInteger)hash {
    return _text.hash ^ _icon.hash;
}

@end

@implementation APBNoticeContent

- (instancetype)initWithLines:(NSArray<APBNoticeLine *> *)lines announcement:(NSString *)announcement {
    self = [super init];
    if (self) {
        _lines = [lines copy];
        _announcement = [announcement copy];
    }
    return self;
}

+ (APBNoticeContent *)mutedWhileRecording {
    static APBNoticeContent *content;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        content = [[APBNoticeContent alloc] initWithLines:@[ [APBNoticeLine lineWithIcon:@"mic.slash.fill" text:@"Microphone muted"] ]
                                             announcement:@"Microphone muted"];
    });
    return content;
}

+ (APBNoticeContent *)currentWithSwitchNotice:(APBNoticeContent *)switchNotice
                           showsMutedReminder:(BOOL)showsMutedReminder
                                 isSuppressed:(BOOL)isSuppressed {
    if (isSuppressed) return nil;
    return switchNotice ?: (showsMutedReminder ? self.mutedWhileRecording : nil);
}

+ (APBNoticeContent *)switchedTo:(NSArray<APBAudioDevice *> *)devices icon:(NSString *(^)(APBAudioDevice *))icon {
    if (devices.count == 2 && [devices[0].name isEqualToString:devices[1].name]) {
        return [[APBNoticeContent alloc]
            initWithLines:@[ [APBNoticeLine lineWithIcon:icon(devices[0]) text:devices[0].name] ]
             announcement:[NSString stringWithFormat:@"Output and microphone: %@", devices[0].name]];
    }
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray *announcements = [NSMutableArray array];
    for (APBAudioDevice *device in devices) {
        [lines addObject:[APBNoticeLine lineWithIcon:icon(device) text:device.name]];
        [announcements addObject:[NSString stringWithFormat:@"%@: %@",
                                  device.role == APBDeviceRoleInput ? @"Microphone" : @"Output", device.name]];
    }
    return [[APBNoticeContent alloc] initWithLines:lines announcement:[announcements componentsJoinedByString:@", "]];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBNoticeContent.class]) return NO;
    APBNoticeContent *other = object;
    return [_lines isEqualToArray:other->_lines] && [_announcement isEqualToString:other->_announcement];
}

- (NSUInteger)hash {
    return _announcement.hash;
}

@end

@implementation APBMutedReminderState

- (BOOL)updateApplies:(BOOL)applies {
    if (!applies) _isDismissed = NO;
    return applies && !_isDismissed;
}

- (void)dismiss {
    _isDismissed = YES;
}

@end

#pragma mark - Notice view

/// A capsule for one line; two lines would make its ends look swollen.
@interface APBNoticeView : APBHoverView
- (void)showContent:(APBNoticeContent *)content dismissible:(BOOL)dismissible;
@end

@implementation APBNoticeView {
    APBMaterialView *_material;
    NSStackView *_stack;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _material = [[APBMaterialView alloc] init];
        _material.material = NSVisualEffectMaterialHUDWindow;
        _material.translatesAutoresizingMaskIntoConstraints = NO;
        _stack = [[NSStackView alloc] init];
        _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _stack.alignment = NSLayoutAttributeLeading;
        _stack.spacing = 6;
        _stack.edgeInsets = NSEdgeInsetsMake(8, 14, 8, 14);
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_material];
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_material.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_material.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_material.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_material.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)showContent:(APBNoticeContent *)content dismissible:(BOOL)dismissible {
    for (NSView *view in _stack.arrangedSubviews.copy) [view removeFromSuperview];
    for (APBNoticeLine *line in content.lines) {
        // A shared width keeps the text of every line aligned.
        NSImageView *icon = [NSImageView imageViewWithImage:APBSymbol(line.icon, 13, NSFontWeightRegular)];
        icon.contentTintColor = NSColor.labelColor;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.widthAnchor constraintEqualToConstant:18].active = YES;
        NSTextField *text = APBLabel(line.text, [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.labelColor);
        NSStackView *row = [NSStackView stackViewWithViews:@[ icon, text ]];
        row.spacing = 8;
        [_stack addArrangedSubview:row];
    }
    BOOL isCapsule = content.lines.count <= 1;
    _material.isCapsule = isCapsule;
    _material.cornerRadius = isCapsule ? 0 : 14;
    [self setAccessibilityElement:YES];
    [self setAccessibilityLabel:[[content.lines valueForKey:@"text"] componentsJoinedByString:@", "]];
    [self setAccessibilityRole:dismissible ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole];
    [self setAccessibilityHelp:dismissible ? @"Hides the reminder until you next record while muted" : nil];
    __weak typeof(self) weakSelf = self;
    [self setAccessibilityCustomActions:dismissible
        ? @[ [[NSAccessibilityCustomAction alloc] initWithName:@"Dismiss" handler:^BOOL {
                 typeof(self) self = weakSelf;
                 if (self.onClick) self.onClick();
                 return YES;
             }] ]
        : @[]];
}

- (BOOL)accessibilityPerformPress {
    if (self.onClick) self.onClick();
    return self.onClick != nil;
}

@end

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

#pragma mark - Notice panel

@implementation APBNoticePanel {
    NSPanel *_window;
    APBNoticeView *_view;
    NSValue *(^_placement)(NSSize);
    APBNoticeContent *_switchNotice;
    NSInteger _switchGeneration;
    APBNoticeContent *_shown;
}

- (instancetype)initWithPlacement:(NSValue *(^)(NSSize))placement {
    self = [super init];
    if (self) {
        _placement = [placement copy];
        _window = FloatingPanel();
        _view = [[APBNoticeView alloc] initWithFrame:NSZeroRect];
        _window.contentView = _view;
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
    NSInteger generation = ++_switchGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SwitchDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || self->_switchGeneration != generation) return;
        self->_switchNotice = nil;
        [self update];
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
        NSPanel *window = _window;
        __weak typeof(self) weakSelf = self;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            window.animator.alphaValue = 0;
        } completionHandler:^{
            typeof(self) self = weakSelf;
            if (self && !self->_shown) [window orderOut:nil];
        }];
        return;
    }
    __weak typeof(self) weakSelf = self;
    _view.onClick = isReminder ? ^{
        typeof(self) self = weakSelf;
        if (self.onDismissMutedReminder) self.onDismissMutedReminder();
    } : nil;
    [_view showContent:content dismissible:isReminder];
    NSSize size = _view.fittingSize;
    [_window setContentSize:size];
    NSValue *origin = _placement(size);
    if (origin) [_window setFrameOrigin:origin.pointValue];
    if (!_window.isVisible) _window.alphaValue = animates ? 0 : 1;
    [_window orderFrontRegardless];
    if (animates) {
        NSPanel *window = _window;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            window.animator.alphaValue = 1;
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

#pragma mark - Hover preview

@implementation APBHoverPreviewPanel {
    APBAppModel *_model;
    NSPanel *_window;
    NSValue *(^_placement)(NSSize);
    NSStackView *_content;
    NSTextField *_mode;
    NSStackView *_linkDown;
    NSImageView *_outputIcon;
    NSTextField *_outputName;
    APBLevelBar *_outputLevel;
    NSImageView *_inputIcon;
    NSTextField *_inputName;
    APBLevelBar *_inputLevel;
}

- (instancetype)initWithModel:(APBAppModel *)model placement:(NSValue *(^)(NSSize))placement {
    self = [super init];
    if (self) {
        _model = model;
        _placement = [placement copy];
        _window = FloatingPanel();
        [self build];
    }
    return self;
}

- (BOOL)isVisible {
    return _window.isVisible;
}

- (NSStackView *)rowWithIcon:(NSImageView *__strong *)icon name:(NSTextField *__strong *)name level:(APBLevelBar *__strong *)level {
    *icon = [[NSImageView alloc] init];
    (*icon).translatesAutoresizingMaskIntoConstraints = NO;
    [(*icon).widthAnchor constraintEqualToConstant:20].active = YES;
    *name = APBLabel(@"", [NSFont systemFontOfSize:13], NSColor.labelColor);
    *level = [[APBLevelBar alloc] init];
    NSStackView *text = [NSStackView stackViewWithViews:@[ *name, *level ]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 4;
    text.detachesHiddenViews = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[ *icon, text ]];
    row.spacing = 8;
    row.alignment = NSLayoutAttributeCenterY;
    return row;
}

- (void)build {
    // In the panel's order: its header, then output, then microphone.
    NSTextField *title = APBLabel(@"Automatic switching", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    _mode = APBLabel(@"", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    NSView *spacer = [[NSView alloc] init];
    [spacer.widthAnchor constraintGreaterThanOrEqualToConstant:16].active = YES;
    NSStackView *titleRow = [NSStackView stackViewWithViews:@[ title, spacer, _mode ]];
    titleRow.spacing = 0;
    // What the tooltip used to explain behind the warning glyph.
    NSImageView *warning = [NSImageView imageViewWithImage:APBSymbol(@"exclamationmark.triangle.fill", 10, NSFontWeightRegular)];
    warning.contentTintColor = NSColor.secondaryLabelColor;
    _linkDown = [NSStackView stackViewWithViews:@[ warning, APBLabel(@"Headset off", [NSFont systemFontOfSize:10], NSColor.secondaryLabelColor) ]];
    _linkDown.spacing = 4;
    NSStackView *header = [NSStackView stackViewWithViews:@[ titleRow, _linkDown ]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 2;
    header.detachesHiddenViews = YES;
    [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor].active = YES;

    NSImageView *outputIcon, *inputIcon;
    NSTextField *outputName, *inputName;
    APBLevelBar *outputLevel, *inputLevel;
    NSStackView *outputRow = [self rowWithIcon:&outputIcon name:&outputName level:&outputLevel];
    NSStackView *inputRow = [self rowWithIcon:&inputIcon name:&inputName level:&inputLevel];
    _outputIcon = outputIcon;
    _outputName = outputName;
    _outputLevel = outputLevel;
    _inputIcon = inputIcon;
    _inputName = inputName;
    _inputLevel = inputLevel;
    NSStackView *devices = [NSStackView stackViewWithViews:@[ outputRow, inputRow ]];
    devices.orientation = NSUserInterfaceLayoutOrientationVertical;
    devices.alignment = NSLayoutAttributeLeading;
    devices.spacing = 14;

    APBSeparator *separator = [APBSeparator separator];
    _content = [NSStackView stackViewWithViews:@[ header, separator, devices ]];
    _content.orientation = NSUserInterfaceLayoutOrientationVertical;
    _content.alignment = NSLayoutAttributeLeading;
    _content.spacing = 10;
    _content.edgeInsets = NSEdgeInsetsMake(10, 12, 12, 12);
    [separator.widthAnchor constraintEqualToAnchor:_content.widthAnchor constant:-24].active = YES;
    [header.widthAnchor constraintEqualToAnchor:_content.widthAnchor constant:-24].active = YES;

    APBPanelBackgroundView *background = [[APBPanelBackgroundView alloc] initWithContent:_content];
    NSView *root = [[NSView alloc] init];
    [root addSubview:background];
    [NSLayoutConstraint activateConstraints:@[
        [background.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [background.topAnchor constraintEqualToAnchor:root.topAnchor],
        [background.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    _window.contentView = root;
}

- (void)updateIcon:(NSImageView *)icon
              name:(NSTextField *)name
             level:(APBLevelBar *)levelBar
            device:(APBAudioDevice *)device
       placeholder:(NSString *)placeholder
         showsLevel:(BOOL)showsLevel
             level:(float)level {
    BOOL isMuted = device && [_model isMuted:device];
    // No circle, unlike the panel's buttons, since nothing here can be
    // clicked. Muted shows as the panel's mute button does.
    NSString *symbol;
    if (isMuted) {
        symbol = device.role == APBDeviceRoleInput ? @"mic.slash.fill" : @"speaker.slash.fill";
    } else if (device) {
        symbol = [device hardwareIconForCategory:device.role == APBDeviceRoleOutput
                      ? [_model.store categoryForDevice:device]
                      : APBOutputCategoryNone];
    } else {
        symbol = @"questionmark";
    }
    icon.image = APBSymbol(symbol, 14, NSFontWeightRegular);
    icon.contentTintColor = isMuted ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    name.stringValue = device.name ?: placeholder;
    name.textColor = device ? NSColor.labelColor : NSColor.secondaryLabelColor;
    levelBar.hidden = !(device && showsLevel);
    levelBar.level = level;
    levelBar.isMuted = isMuted;
}

- (void)refresh {
    _mode.stringValue = _model.isManualMode ? @"Off" : @"On";
    _linkDown.hidden = !_model.isActiveOutputLinkDown;
    [self updateIcon:_outputIcon name:_outputName level:_outputLevel device:_model.currentOutputDevice
         placeholder:@"No output" showsLevel:_model.isVolumeControllable level:_model.volume];
    [self updateIcon:_inputIcon name:_inputName level:_inputLevel device:_model.currentInputDevice
         placeholder:@"No microphone" showsLevel:_model.isMicrophoneLevelControllable level:_model.microphoneLevel];
    if (_window.isVisible) [self place];
}

- (void)place {
    NSView *root = _window.contentView;
    [root layoutSubtreeIfNeeded];
    NSSize size = root.fittingSize;
    [_window setContentSize:size];
    NSValue *origin = _placement(size);
    if (origin) [_window setFrameOrigin:origin.pointValue];
}

- (void)show {
    [self refresh];
    [self place];
    [_window orderFrontRegardless];
}

- (void)hide {
    [_window orderOut:nil];
}

@end
