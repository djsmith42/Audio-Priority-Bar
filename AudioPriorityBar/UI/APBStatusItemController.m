#import "APBStatusItemController.h"
#import "APBDeviceIcon.h"
#import "APBNoticePanel.h"
#import "APBPanelView.h"
#import "APBSettingsWindowController.h"
#import "APBUI.h"

static const NSTimeInterval SuppressionLifetime = 2;

@implementation APBClickRouting

+ (APBStatusItemClickAction)actionForEventType:(NSEventType)type modifiers:(NSEventModifierFlags)modifiers {
    if (type == NSEventTypeRightMouseUp
        || (type == NSEventTypeLeftMouseUp && (modifiers & NSEventModifierFlagControl))) {
        return APBStatusItemClickActionShowMenu;
    }
    if (type == NSEventTypeLeftMouseUp && (modifiers & NSEventModifierFlagOption)) {
        return APBStatusItemClickActionToggleMute;
    }
    return APBStatusItemClickActionTogglePanel;
}

+ (BOOL)shouldSuppressOpenSuppressedAt:(NSTimeInterval)suppressedAt now:(NSTimeInterval)now {
    if (suppressedAt < 0) return NO;
    return now - suppressedAt < SuppressionLifetime;
}

@end

@implementation APBPanelPlacement

+ (NSPoint)originForButtonRect:(NSRect)buttonRect size:(NSSize)size visibleFrame:(NSRect)visible {
    CGFloat maxX = MAX(NSMaxX(visible) - size.width - 4, NSMinX(visible) + 4);
    CGFloat x = MIN(MAX(NSMidX(buttonRect) - size.width / 2, NSMinX(visible) + 4), maxX);
    CGFloat y = MAX(NSMinY(buttonRect) - size.height - 4, NSMinY(visible) + 4);
    return NSMakePoint(x, y);
}

@end

#pragma mark - Status label

/// One glyph in the menu bar icon, drawn over a slot as wide as the widest of
/// its reserved glyphs so the item keeps its width as the device changes.
typedef struct {
    __unsafe_unretained NSImage *image;
    CGFloat slotWidth;
    CGFloat opacity;
} APBGlyph;

@implementation APBStatusLabel

/// The 13-point menu bar font draws glyphs smaller than the system's own menu
/// extras, such as Sound and Wi-Fi.
static const CGFloat GlyphSize = 14;

/// The menu bar uses filled glyphs; not every hardware symbol has one.
+ (NSString *)filled:(NSString *)name {
    NSString *fill = [name stringByAppendingString:@".fill"];
    return [NSImage imageWithSystemSymbolName:fill accessibilityDescription:nil] ? fill : name;
}

+ (NSImage *)glyph:(NSString *)name {
    return APBSymbol(name, GlyphSize, NSFontWeightRegular);
}

+ (CGFloat)widestOf:(NSArray<NSString *> *)names {
    CGFloat widest = 0;
    for (NSString *name in names) widest = MAX(widest, [self glyph:[self filled:name]].size.width);
    return ceil(widest);
}

+ (CGFloat)reservedInputWidth {
    static CGFloat width;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        width = [self widestOf:[APBAudioDevice.hardwareIcons arrayByAddingObject:@"mic.slash"]];
    });
    return width;
}

+ (CGFloat)reservedOutputWidth {
    static CGFloat width;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        width = [self widestOf:[APBAudioDevice.hardwareIcons arrayByAddingObjectsFromArray:@[ @"speaker.wave.3", @"speaker.slash" ]]];
    });
    return width;
}

/// The current output's hardware icon, or nil for a generic speaker, which
/// shows the volume level instead. Falls back to the category while no output
/// is known.
+ (NSString *)hardwareIconForModel:(APBAppModel *)model {
    APBAudioDevice *output = model.currentOutputDevice;
    NSString *icon = output
        ? [output menuBarIconForCategory:model.activeOutputCategory]
        : (model.activeOutputCategory == APBOutputCategoryHeadphone ? @"headphones" : nil);
    return [icon isEqualToString:APBGenericSpeakerIcon] ? nil : icon;
}

+ (NSImage *)imageForModel:(APBAppModel *)model {
    NSMutableArray *parts = [NSMutableArray array];
    NSDictionary *textAttributes = @{ NSFontAttributeName: [NSFont menuBarFontOfSize:0] };
    BOOL isLabeled = model.menuBarDevices == APBMenuBarDevicesBothLabeled;
    BOOL reduceMotion = APBReduceMotion();
    CGFloat mutedOpacity = reduceMotion || model.micFlashState ? 1 : 0.45;

    void (^addGlyph)(NSImage *, CGFloat, CGFloat) = ^(NSImage *image, CGFloat slot, CGFloat opacity) {
        if (!image) return;
        [parts addObject:@{ @"image": image, @"slot": @(MAX(slot, image.size.width)), @"opacity": @(opacity) }];
    };
    void (^addText)(NSString *) = ^(NSString *text) {
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:textAttributes];
        [parts addObject:@{ @"text": string, @"leading": @4 }];
    };

    if (model.menuBarDevices != APBMenuBarDevicesOutputOnly) {
        if (isLabeled) addText(@"in:");
        // Every possible glyph is reserved, so the item keeps the widest one's
        // width instead of resizing as the device changes.
        if (model.isActiveInputMuted) {
            addGlyph([self glyph:@"mic.slash.fill"], self.reservedInputWidth, mutedOpacity);
        } else {
            NSString *input = [model.currentInputDevice menuBarIconForCategory:APBOutputCategoryNone] ?: @"mic";
            addGlyph([self glyph:[self filled:input]], self.reservedInputWidth, 1);
        }
        if (isLabeled) addText(@"out:");
    } else if (model.isActiveInputMuted) {
        addGlyph([self glyph:@"mic.slash.fill"], 0, mutedOpacity);
    }

    NSString *hardwareIcon = [self hardwareIconForModel:model];
    NSImage *output;
    if (model.isActiveOutputMuted) {
        output = [self glyph:@"speaker.slash.fill"];
    } else if (hardwareIcon) {
        output = [self glyph:[self filled:hardwareIcon]];
    } else if (!model.isVolumeControllable) {
        output = [self glyph:@"speaker.wave.3.fill"];
    } else {
        output = APBVariableSymbol(@"speaker.wave.3.fill", model.volume, GlyphSize, NSFontWeightRegular);
    }
    addGlyph(output, self.reservedOutputWidth, 1);

    // Only beside hardware glyphs, which have no waves of their own. Kept
    // while muted so muting does not change the width.
    if (model.showsMenuBarVolume && hardwareIcon) {
        NSImage *waves = APBVariableSymbol(@"wave.3.right", model.volume, GlyphSize, NSFontWeightRegular);
        BOOL showsWaves = !model.isActiveOutputMuted && model.isVolumeControllable;
        addGlyph(waves, waves.size.width, showsWaves ? 1 : 0);
    }

    // Beside the audio glyph rather than replacing it: that glyph still
    // identifies the app and the active category, while this one flags the
    // exceptional state. Monochrome like the rest, since colored menu bar
    // icons fight light and dark contrast.
    if (model.isActiveOutputLinkDown) addGlyph([self glyph:@"exclamationmark.triangle.fill"], 0, 1);

    const CGFloat spacing = 2;
    BOOL outlined = model.outlinesMenuBarIcon;
    CGFloat contentWidth = 0, contentHeight = 0;
    for (NSDictionary *part in parts) {
        if (contentWidth > 0) contentWidth += spacing;
        if (part[@"text"]) {
            NSSize size = [part[@"text"] size];
            contentWidth += [part[@"leading"] doubleValue] + ceil(size.width);
            contentHeight = MAX(contentHeight, ceil(size.height));
        } else {
            NSImage *image = part[@"image"];
            contentWidth += [part[@"slot"] doubleValue];
            contentHeight = MAX(contentHeight, image.size.height);
        }
    }
    CGFloat paddingX = (outlined ? 4 : 0) + 1;
    CGFloat paddingY = outlined ? 2 : 0;
    NSSize size = NSMakeSize(ceil(contentWidth + paddingX * 2), ceil(MAX(contentHeight, 16) + paddingY * 2));

    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        CGFloat x = paddingX;
        BOOL first = YES;
        for (NSDictionary *part in parts) {
            if (!first) x += spacing;
            first = NO;
            if (part[@"text"]) {
                NSAttributedString *text = part[@"text"];
                x += [part[@"leading"] doubleValue];
                NSSize textSize = text.size;
                [text drawAtPoint:NSMakePoint(x, round((size.height - textSize.height) / 2))];
                x += ceil(textSize.width);
                continue;
            }
            NSImage *glyph = part[@"image"];
            CGFloat slot = [part[@"slot"] doubleValue];
            NSSize glyphSize = glyph.size;
            NSRect target = NSMakeRect(x + round((slot - glyphSize.width) / 2),
                                       round((size.height - glyphSize.height) / 2),
                                       glyphSize.width, glyphSize.height);
            [glyph drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                     fraction:[part[@"opacity"] doubleValue]];
            x += slot;
        }
        if (outlined) {
            // Whole points only: a fractional width lands on half pixels and
            // draws some edges softer than others.
            NSRect outline = NSInsetRect(NSMakeRect(1, 0, size.width - 2, size.height), 0.5, 0.5);
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:outline xRadius:4 yRadius:4];
            path.lineWidth = 1;
            [NSColor.blackColor setStroke];
            [path stroke];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

@end

#pragma mark - Panel window

@interface APBPanelWindow : NSPanel
@property (nonatomic, copy, nullable) dispatch_block_t onCancel;
@end

@implementation APBPanelWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (void)cancelOperation:(id)sender {
    if (_onCancel) _onCancel();
}

@end

#pragma mark - Status item controller

@implementation APBStatusItemController {
    APBAppModel *_model;
    APBSettingsWindowController *_settings;
    APBUpdateChecker *_updates;
    NSStatusItem *_statusItem;
    APBPanelWindow *_panel;
    APBPanelView *_panelView;
    NSMenu *_menu;
    NSMenuItem *_updatesItem;
    NSMenuItem *_muteItem;
    NSTimeInterval _suppressNextClickAt;
    /// The status item's center when the panel opened. The item widens and
    /// narrows with its glyphs, like the muted microphone, and re-centering on
    /// it would slide the open panel sideways.
    CGFloat _panelAnchorX;
    BOOL _hasPanelAnchor;
    /// Rereads AirPods battery levels while the panel stays open.
    NSTimer *_batteryTimer;
    APBNoticePanel *_notice;
    APBHoverPreviewPanel *_hoverPreview;
    /// Set by a click so the preview stays away until the pointer leaves.
    BOOL _isHoverDismissed;
    NSInteger _hoverGeneration;
    BOOL _isHoverPending;
    APBMutedReminderState *_mutedReminder;
    id _globalMonitor;
    id _localMonitor;
    NSString *_lastStatusSignature;
}

- (instancetype)initWithModel:(APBAppModel *)model
                     settings:(APBSettingsWindowController *)settings
                      updates:(APBUpdateChecker *)updates {
    self = [super init];
    if (self) {
        _model = model;
        _settings = settings;
        _updates = updates;
        _suppressNextClickAt = -1;
        _mutedReminder = [[APBMutedReminderState alloc] init];
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        __weak typeof(self) weakSelf = self;
        _notice = [[APBNoticePanel alloc] initWithPlacement:^NSValue *(NSSize size) {
            return [weakSelf originUnderButtonForSize:size anchored:NO];
        }];
        _hoverPreview = [[APBHoverPreviewPanel alloc] initWithModel:model placement:^NSValue *(NSSize size) {
            return [weakSelf originUnderButtonForSize:size anchored:NO];
        }];
        [self configureStatusItem];
        [self configurePanel];
        [self configureMenu];
        [self observePointer];
        _notice.onDismissMutedReminder = ^{
            typeof(self) self = weakSelf;
            [self->_mutedReminder dismiss];
            [self refreshMutedReminder];
        };
        model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) {
            [weakSelf showSwitchNotice:devices];
        };
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelDidChange:)
                                                   name:APBAppModelDidChangeNotification object:model];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screensDidChange:)
                                                   name:NSApplicationDidChangeScreenParametersNotification object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(screensDidChange:)
                                                               name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
        [self updateStatus];
        [self refreshMutedReminder];
        // Launch with `--args -previewNotices YES` to see both notices without
        // changing any hardware.
        if ([NSUserDefaults.standardUserDefaults boolForKey:@"previewNotices"]) [self previewNotices];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    if (_globalMonitor) [NSEvent removeMonitor:_globalMonitor];
    if (_localMonitor) [NSEvent removeMonitor:_localMonitor];
}

- (void)previewNotices {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        NSMutableArray *devices = [NSMutableArray array];
        if (self->_model.currentOutputDevice) [devices addObject:self->_model.currentOutputDevice];
        if (self->_model.currentInputDevice) [devices addObject:self->_model.currentInputDevice];
        [self showSwitchNotice:devices];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self->_notice.showsMutedReminder = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self refreshMutedReminder];
            });
        });
    });
}

#pragma mark Configuration

- (void)configureStatusItem {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;
    button.target = self;
    button.action = @selector(handleClick:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    button.imagePosition = NSImageOnly;
    [button setAccessibilityLabel:APBAppDisplayName];
    [button setAccessibilityHelp:@"Activate to show audio devices; open the context menu to mute the microphone, or for Settings and Quit"];
}

- (void)configurePanel {
    _panel = [[APBPanelWindow alloc] initWithContentRect:NSZeroRect
                                               styleMask:NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    _panelView = [[APBPanelView alloc] initWithModel:_model];
    __weak typeof(self) weakSelf = self;
    _panelView.onShowSettings = ^{
        [weakSelf hidePanelSuppressingNextClick:NO];
        [weakSelf showSettings];
    };
    _panelView.onSizeChange = ^{
        [weakSelf fitPanel];
    };
    _panel.contentView = _panelView;
    [_panel setAccessibilityLabel:APBAppDisplayName];
    _panel.initialFirstResponder = _panelView;
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.movable = NO;
    _panel.releasedWhenClosed = NO;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _panel.delegate = self;
    _panel.onCancel = ^{
        [weakSelf hidePanelSuppressingNextClick:NO];
    };
}

- (void)configureMenu {
    _menu = [[NSMenu alloc] init];
    _menu.autoenablesItems = NO;
    _muteItem = [[NSMenuItem alloc] initWithTitle:@"Mute Microphone" action:@selector(toggleMute) keyEquivalent:@""];
    _muteItem.target = self;
    [_menu addItem:_muteItem];
    [_menu addItem:NSMenuItem.separatorItem];
    _updatesItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…" action:@selector(handleUpdatesItem) keyEquivalent:@""];
    _updatesItem.target = self;
    [_menu addItem:_updatesItem];
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings = [_menu addItemWithTitle:@"Settings…" action:@selector(showSettings) keyEquivalent:@","];
    settings.target = self;
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [_menu addItemWithTitle:@"Quit Audio Priority Bar" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
}

#pragma mark Observation

- (void)modelDidChange:(NSNotification *)notification {
    [self updateStatus];
    [self refreshMutedReminder];
    if (_panel.isVisible) [_panelView refresh];
    if (_hoverPreview.isVisible) [_hoverPreview refresh];
}

- (void)screensDidChange:(NSNotification *)notification {
    _lastStatusSignature = nil;
    [self updateStatus];
}

/// Everything the icon depends on, so an unchanged icon is not redrawn on
/// every model change.
- (NSString *)statusSignature {
    APBAppModel *model = _model;
    return [NSString stringWithFormat:@"%@|%@|%@|%d%d%d%d%d%d%d%ld|%.3f|%@",
            model.currentOutputDevice.identifier, model.currentInputDevice.identifier,
            @(model.activeOutputCategory),
            model.isActiveInputMuted, model.isActiveOutputMuted, model.isVolumeControllable,
            model.showsMenuBarVolume, model.outlinesMenuBarIcon, model.micFlashState,
            model.isActiveOutputLinkDown, (long)model.menuBarDevices, model.volume,
            NSApp.effectiveAppearance.name];
}

- (void)updateStatus {
    NSString *signature = self.statusSignature;
    if (![signature isEqualToString:_lastStatusSignature]) {
        _lastStatusSignature = signature;
        NSImage *image = [APBStatusLabel imageForModel:_model];
        _statusItem.button.image = image;
        _statusItem.length = ceil(image.size.width);
    }
    // Sighted users get the hover preview instead, which names the devices
    // behind the glyphs.
    [_statusItem.button setAccessibilityValue:self.statusDescription];
    if (_panel.isVisible) [self positionPanel];
}

- (NSString *)statusDescription {
    NSMutableArray *values = [NSMutableArray arrayWithObject:_model.isManualMode ? @"Manual" : @"Automatic"];
    APBOutputCategory category = _model.activeOutputCategory;
    if (category != APBOutputCategoryNone) {
        [values addObject:category == APBOutputCategorySpeaker ? @"speakers" : @"headphones"];
    }
    if (_model.isActiveOutputLinkDown) [values addObject:@"headset off"];
    if (_model.isActiveOutputMuted) [values addObject:@"output muted"];
    if (_model.isActiveInputMuted) [values addObject:@"microphone muted"];
    if (_model.isVolumeControllable) {
        [values addObject:[NSString stringWithFormat:@"volume %d percent", (int)(_model.volume * 100)]];
    }
    return [values componentsJoinedByString:@", "];
}

#pragma mark Clicks

- (void)handleClick:(id)sender {
    _isHoverDismissed = YES;
    [self hideHoverPreview];
    NSEvent *event = NSApp.currentEvent;
    APBStatusItemClickAction action = APBStatusItemClickActionTogglePanel;
    if (event && NSProcessInfo.processInfo.systemUptime - event.timestamp < 1
        && [self isPointInStatusItem:NSEvent.mouseLocation]) {
        action = [APBClickRouting actionForEventType:event.type modifiers:event.modifierFlags];
    }
    switch (action) {
        case APBStatusItemClickActionTogglePanel: [self togglePanel]; break;
        case APBStatusItemClickActionShowMenu: [self showMenu]; break;
        case APBStatusItemClickActionToggleMute: [self toggleMute]; break;
    }
}

- (void)toggleMute {
    [_model setMicrophoneMuted:!_model.isMicrophoneMuted];
}

- (void)togglePanel {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;
    if (_panel.isVisible) {
        [self hidePanelSuppressingNextClick:NO];
        return;
    }
    if (_suppressNextClickAt >= 0) {
        NSTimeInterval suppressedAt = _suppressNextClickAt;
        _suppressNextClickAt = -1;
        if ([APBClickRouting shouldSuppressOpenSuppressedAt:suppressedAt now:NSProcessInfo.processInfo.systemUptime]) return;
    }
    [_panelView refresh];
    [self fitPanel];
    NSWindow *window = button.window;
    if (window) {
        _panelAnchorX = NSMidX([window convertRectToScreen:[button convertRect:button.bounds toView:nil]]);
        _hasPanelAnchor = YES;
    }
    [self positionPanel];
    [_model.battery refresh];
    APBAppModel *model = _model;
    _batteryTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        [model.battery refresh];
    }];
    [_panel orderFrontRegardless];
    [_panel makeKeyWindow];
    [button highlight:YES];
    _notice.isSuppressed = YES;
}

- (void)fitPanel {
    [_panelView layoutSubtreeIfNeeded];
    NSSize size = _panelView.fittingSize;
    if (NSEqualSizes(size, _panel.frame.size)) return;
    // Grows and shrinks downward, keeping the top edge under the menu bar.
    [_panel setContentSize:size];
    [_panel invalidateShadow];
    if (_panel.isVisible) [self positionPanel];
}

- (void)showMenu {
    [self hidePanelSuppressingNextClick:NO];
    // The items are read fresh here rather than kept in sync continuously,
    // since they are only ever visible for the moment the menu is open.
    _updatesItem.enabled = _updates.isAvailable;
    _muteItem.title = _model.isMicrophoneMuted ? @"Unmute Microphone" : @"Mute Microphone";
    _muteItem.enabled = _model.isMicrophoneMutable;
    _statusItem.menu = _menu;
    [_statusItem.button performClick:nil];
    _statusItem.menu = nil;
}

- (void)showSettings {
    // The status item lives in the menu bar of the screen being used, which is
    // the same screen the panel is positioned against.
    [_settings showSettingsOnScreen:_statusItem.button.window.screen];
}

- (void)handleUpdatesItem {
    [_updates checkForUpdates];
}

- (void)hidePanelSuppressingNextClick:(BOOL)suppressNextClick {
    [_statusItem.button highlight:NO];
    if (!_panel.isVisible) return;
    if (suppressNextClick) _suppressNextClickAt = NSProcessInfo.processInfo.systemUptime;
    [_panelView cancelDrag];
    [_panel orderOut:nil];
    _hasPanelAnchor = NO;
    [_batteryTimer invalidate];
    _batteryTimer = nil;
    _notice.isSuppressed = NO;
}

- (void)positionPanel {
    NSValue *origin = [self originUnderButtonForSize:_panel.frame.size anchored:YES];
    if (origin) [_panel setFrameOrigin:origin.pointValue];
}

- (NSValue *)originUnderButtonForSize:(NSSize)size anchored:(BOOL)anchored {
    NSStatusBarButton *button = _statusItem.button;
    NSWindow *window = button.window;
    NSScreen *screen = window.screen;
    if (!window || !screen) return nil;
    NSRect buttonRect = [window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
    if (anchored && _hasPanelAnchor) buttonRect.origin.x = _panelAnchorX - NSWidth(buttonRect) / 2;
    return [NSValue valueWithPoint:[APBPanelPlacement originForButtonRect:buttonRect size:size visibleFrame:screen.visibleFrame]];
}

#pragma mark Hover preview

/// Follows the pointer across the whole screen rather than through a tracking
/// area, which never fires for a pointer sliding in along the screen's top
/// edge. Moves over other apps arrive through the global monitor and moves
/// over this app's own windows through the local one.
- (void)observePointer {
    __weak typeof(self) weakSelf = self;
    _globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^(NSEvent *event) {
        [weakSelf updateHoverPreview];
    }];
    _localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^NSEvent *(NSEvent *event) {
        [weakSelf updateHoverPreview];
        return event;
    }];
}

- (void)updateHoverPreview {
    if (![self isPointInHoverColumn:NSEvent.mouseLocation]) {
        _isHoverDismissed = NO;
        [self hideHoverPreview];
        return;
    }
    if (_isHoverDismissed || _panel.isVisible || _hoverPreview.isVisible || _isHoverPending) return;
    // Waits like a tooltip, so sweeping across the menu bar does not flash the
    // preview.
    _isHoverPending = YES;
    NSInteger generation = ++_hoverGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || self->_hoverGeneration != generation) return;
        self->_isHoverPending = NO;
        if (self->_isHoverDismissed || self->_panel.isVisible) return;
        self->_notice.isSuppressed = YES;
        [self->_hoverPreview show];
    });
}

/// The status item's window from the bottom of the menu bar up through the
/// screen's top edge, where the pointer reports a point just outside the
/// window. Capped at that edge so a display stacked above does not count.
- (BOOL)isPointInHoverColumn:(NSPoint)point {
    NSWindow *window = _statusItem.button.window;
    NSScreen *screen = window.screen;
    if (!window || !screen) return NO;
    NSRect frame = window.frame;
    return point.x >= NSMinX(frame) && point.x < NSMaxX(frame)
        && point.y >= NSMinY(frame) && point.y <= NSMaxY(screen.frame);
}

- (void)hideHoverPreview {
    _hoverGeneration += 1;
    _isHoverPending = NO;
    if (!_hoverPreview.isVisible) return;
    [_hoverPreview hide];
    _notice.isSuppressed = _panel.isVisible;
}

#pragma mark Notices

- (void)refreshMutedReminder {
    _notice.showsMutedReminder = [_mutedReminder updateApplies:_model.remindsWhenMuted
                                                               && _model.isMicrophoneMuted
                                                               && _model.isInputRecording];
}

- (void)showSwitchNotice:(NSArray<APBAudioDevice *> *)devices {
    if (!_model.showsSwitchNotice || devices.count == 0) return;
    APBPriorityStore *store = _model.store;
    [_notice showSwitch:[APBNoticeContent switchedTo:devices icon:^NSString *(APBAudioDevice *device) {
        return [device hardwareIconForCategory:device.role == APBDeviceRoleOutput
                    ? [store categoryForDevice:device]
                    : APBOutputCategoryNone];
    }]];
}

#pragma mark NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
    [_panel invalidateShadow];
    if (_panel.isVisible) [self positionPanel];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [_panelView cancelDrag];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_panel.isVisible || self->_panel.attachedSheet || NSApp.modalWindow
            || [self isRelatedToPanel:NSApp.keyWindow]) {
            return;
        }
        [self hidePanelSuppressingNextClick:[self isPointInStatusItem:NSEvent.mouseLocation]];
    });
}

- (BOOL)isRelatedToPanel:(NSWindow *)window {
    NSWindow *candidate = window;
    while (candidate) {
        if (candidate == _panel) return YES;
        candidate = candidate.parentWindow ?: candidate.sheetParent;
    }
    return NO;
}

- (BOOL)isPointInStatusItem:(NSPoint)point {
    NSStatusBarButton *button = _statusItem.button;
    NSWindow *window = button.window;
    if (!window) return NO;
    return NSPointInRect(point, [window convertRectToScreen:[button convertRect:button.bounds toView:nil]]);
}

@end
