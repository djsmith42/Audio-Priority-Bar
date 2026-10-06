#import "StatusItemController.h"
#import "AppDelegate.h"
#import "DeviceIcon.h"
#import "NoticePanel.h"
#import "PanelViewController.h"
#import "StatusItemRouting.h"
#import "StatusLabel.h"

@interface APBPanelWindow : NSPanel
@property (nonatomic, copy, nullable) void (^onCancel)(void);
@end

@implementation APBPanelWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (void)cancelOperation:(id)sender {
    if (_onCancel) _onCancel();
}

@end

@implementation APBStatusItemController {
    APBAppModel *_model;
    APBSettingsWindowController *_settings;
    APBUpdateChecker *_updates;
    NSStatusItem *_statusItem;
    APBPanelWindow *_panel;
    APBPanelViewController *_panelController;
    NSMenu *_menu;
    NSMenuItem *_updatesItem;
    NSMenuItem *_muteItem;
    NSNumber *_suppressNextClickAt;
    /// The status item's center when the panel opened. The item widens and
    /// narrows with its glyphs, like the muted microphone, and re-centering
    /// on it would slide the open panel sideways.
    NSNumber *_panelAnchorX;
    /// Rereads AirPods battery levels while the panel stays open.
    NSTimer *_batteryTimer;
    APBNoticePanel *_notice;
    APBHoverPreviewPanel *_hoverPreview;
    /// Set by a click so the preview stays away until the pointer leaves.
    BOOL _isHoverDismissed;
    NSUInteger _hoverGeneration;
    BOOL _isHoverPending;
    APBMutedReminderState *_mutedReminder;
    NSString *_shownDescription;
    id _globalMonitor;
    id _localMonitor;
}

- (instancetype)initWithModel:(APBAppModel *)model
                     settings:(APBSettingsWindowController *)settings
                      updates:(APBUpdateChecker *)updates {
    if ((self = [super init])) {
        _model = model;
        _settings = settings;
        _updates = updates;
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        _mutedReminder = [[APBMutedReminderState alloc] init];
        __weak typeof(self) weakSelf = self;
        APBPlacement placement = ^NSValue *(NSSize size) {
            APBStatusItemController *controller = weakSelf;
            NSStatusBarButton *button = controller ? controller->_statusItem.button : nil;
            return button ? [controller originUnder:button size:size anchorX:nil] : nil;
        };
        _notice = [[APBNoticePanel alloc] initWithPlacement:placement];
        _hoverPreview = [[APBHoverPreviewPanel alloc] initWithModel:model placement:placement];
        [self configureStatusItem];
        [self configurePanel];
        [self configureMenu];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(modelDidChange:)
                                                   name:APBAppModelDidChangeNotification
                                                 object:model];
        [self updateStatus];
        [self refreshMutedReminder];
        [self observePointer];
        _notice.onDismissMutedReminder = ^{
            APBStatusItemController *controller = weakSelf;
            if (!controller) return;
            [controller->_mutedReminder dismiss];
            [controller refreshMutedReminder];
        };
        model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) {
            [weakSelf showSwitchNotice:devices];
        };
        // Launch with `--args -previewNotices YES` to see both notices
        // without changing any hardware.
        if ([NSUserDefaults.standardUserDefaults boolForKey:@"previewNotices"]) [self previewNotices];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_globalMonitor) [NSEvent removeMonitor:_globalMonitor];
    if (_localMonitor) [NSEvent removeMonitor:_localMonitor];
}

- (void)previewNotices {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        APBStatusItemController *controller = weakSelf;
        if (!controller) return;
        NSMutableArray *devices = [NSMutableArray array];
        if (controller->_model.currentOutputDevice) [devices addObject:controller->_model.currentOutputDevice];
        if (controller->_model.currentInputDevice) [devices addObject:controller->_model.currentInputDevice];
        [controller showSwitchNotice:devices];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            APBStatusItemController *later = weakSelf;
            if (!later) return;
            later->_notice.showsMutedReminder = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakSelf refreshMutedReminder];
            });
        });
    });
}

- (void)configureStatusItem {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;
    button.target = self;
    button.action = @selector(handleClick:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    button.imagePosition = NSImageOnly;
    button.accessibilityLabel = APBAppDisplayName;
    button.accessibilityHelp = @"Activate to show audio devices; open the context menu to mute the microphone, or for Settings and Quit";
}

- (void)configurePanel {
    _panel = [[APBPanelWindow alloc] initWithContentRect:NSZeroRect
                                               styleMask:NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    __weak typeof(self) weakSelf = self;
    _panelController = [[APBPanelViewController alloc] initWithModel:_model showSettings:^{
        [weakSelf hidePanelSuppressingNextClick:NO];
        [weakSelf showSettings:nil];
    }];
    _panelController.onSizeChange = ^{ [weakSelf fitPanel]; };
    _panel.contentViewController = _panelController;
    _panel.accessibilityLabel = APBAppDisplayName;
    _panel.initialFirstResponder = _panelController.view;
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.movable = NO;
    _panel.releasedWhenClosed = NO;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _panel.delegate = self;
    _panel.onCancel = ^{ [weakSelf hidePanelSuppressingNextClick:NO]; };
}

- (void)configureMenu {
    _menu = [[NSMenu alloc] init];
    _menu.autoenablesItems = NO;
    _muteItem = [[NSMenuItem alloc] initWithTitle:@"Mute Microphone" action:@selector(toggleMute:) keyEquivalent:@""];
    _muteItem.target = self;
    [_menu addItem:_muteItem];
    [_menu addItem:NSMenuItem.separatorItem];
    _updatesItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…" action:@selector(handleUpdatesItem:) keyEquivalent:@""];
    _updatesItem.target = self;
    [_menu addItem:_updatesItem];
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings = [_menu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [_menu addItemWithTitle:@"Quit Audio Priority Bar" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
}

- (void)modelDidChange:(NSNotification *)notification {
    [self updateStatus];
    [self refreshMutedReminder];
    if (_panel.isVisible) [_panelController reload];
}

- (void)updateStatus {
    NSImage *image = [APBStatusLabel imageForModel:_model];
    NSStatusBarButton *button = _statusItem.button;
    button.image = image;
    _statusItem.length = ceil(image.size.width);
    // Sighted users get the hover preview instead, which names the devices
    // behind the glyphs.
    NSString *description = self.statusDescription;
    if (![description isEqualToString:_shownDescription]) {
        _shownDescription = description;
        button.accessibilityValue = description;
    }
    if (_panel.isVisible && button) [self positionPanelRelativeTo:button];
}

#pragma mark - Clicks

- (void)handleClick:(id)sender {
    _isHoverDismissed = YES;
    [self hideHoverPreview];
    APBStatusItemClickAction action = APBStatusItemClickActionTogglePanel;
    NSEvent *event = NSApp.currentEvent;
    if (event && NSProcessInfo.processInfo.systemUptime - event.timestamp < 1
        && [self isPointInStatusItem:NSEvent.mouseLocation]) {
        action = [APBClickRouting actionForEventType:event.type modifiers:event.modifierFlags];
    }
    switch (action) {
        case APBStatusItemClickActionTogglePanel: [self togglePanel]; break;
        case APBStatusItemClickActionShowMenu: [self showMenu]; break;
        case APBStatusItemClickActionToggleMute: [self toggleMute:nil]; break;
    }
}

- (void)toggleMute:(id)sender {
    [_model setMicrophoneMuted:!_model.isMicrophoneMuted];
}

- (void)togglePanel {
    NSStatusBarButton *button = _statusItem.button;
    if (!button) return;
    if (_panel.isVisible) {
        [self hidePanelSuppressingNextClick:NO];
        return;
    }
    if (_suppressNextClickAt) {
        NSNumber *suppressedAt = _suppressNextClickAt;
        _suppressNextClickAt = nil;
        if ([APBClickRouting shouldSuppressOpenSuppressedAt:suppressedAt now:NSProcessInfo.processInfo.systemUptime]) {
            return;
        }
    }
    [_panelController reload];
    NSView *content = _panelController.view;
    [content layoutSubtreeIfNeeded];
    [_panel setContentSize:content.fittingSize];
    NSWindow *window = button.window;
    _panelAnchorX = window ? @(NSMidX([window convertRectToScreen:[button convertRect:button.bounds toView:nil]])) : nil;
    [self positionPanelRelativeTo:button];
    [_model.battery refresh];
    __weak typeof(self) weakSelf = self;
    _batteryTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        APBStatusItemController *controller = weakSelf;
        if (controller) [controller->_model.battery refresh];
    }];
    [_panel orderFrontRegardless];
    [_panel makeKeyWindow];
    [button highlight:YES];
    _notice.isSuppressed = YES;
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

- (void)showSettings:(id)sender {
    // The status item lives in the menu bar of the screen being used, which
    // is the same screen the panel is positioned against.
    [_settings showSettingsOnScreen:_statusItem.button.window.screen];
}

- (void)handleUpdatesItem:(id)sender {
    [_updates checkForUpdates];
}

- (void)hidePanelSuppressingNextClick:(BOOL)suppressNextClick {
    [_statusItem.button highlight:NO];
    if (!_panel.isVisible) return;
    if (suppressNextClick) _suppressNextClickAt = @(NSProcessInfo.processInfo.systemUptime);
    [_panelController cancelDrag];
    [_panel orderOut:nil];
    _panelAnchorX = nil;
    [_batteryTimer invalidate];
    _batteryTimer = nil;
    _notice.isSuppressed = NO;
}

#pragma mark - Placement

- (void)fitPanel {
    NSView *content = _panelController.view;
    NSSize size = content.fittingSize;
    if (NSEqualSizes(size, _panel.contentLayoutRect.size)) return;
    [_panel setContentSize:size];
    [_panel invalidateShadow];
    NSStatusBarButton *button = _statusItem.button;
    if (_panel.isVisible && button) [self positionPanelRelativeTo:button];
}

- (void)positionPanelRelativeTo:(NSStatusBarButton *)button {
    NSValue *origin = [self originUnder:button size:_panel.frame.size anchorX:_panelAnchorX];
    if (origin) [_panel setFrameOrigin:origin.pointValue];
}

- (NSValue *)originUnder:(NSStatusBarButton *)button size:(NSSize)size anchorX:(NSNumber *)anchorX {
    NSWindow *window = button.window;
    NSScreen *screen = window.screen;
    if (!window || !screen) return nil;
    NSRect buttonRect = [window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
    if (anchorX) buttonRect.origin.x = anchorX.doubleValue - NSWidth(buttonRect) / 2;
    return [NSValue valueWithPoint:[APBPanelPlacement originForButtonRect:buttonRect
                                                                     size:size
                                                             visibleFrame:screen.visibleFrame]];
}

#pragma mark - Hover preview

/// Follows the pointer across the whole screen rather than through a
/// tracking area, which never fires for a pointer sliding in along the
/// screen's top edge. Moves over other apps arrive through the global monitor
/// and moves over this app's own windows through the local one.
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
    // Waits like a tooltip, so sweeping across the menu bar does not flash
    // the preview.
    _isHoverPending = YES;
    NSUInteger generation = ++_hoverGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        APBStatusItemController *controller = weakSelf;
        if (!controller || controller->_hoverGeneration != generation) return;
        controller->_isHoverPending = NO;
        if (controller->_isHoverDismissed || controller->_panel.isVisible) return;
        controller->_notice.isSuppressed = YES;
        [controller->_hoverPreview show];
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

#pragma mark - Notices

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
                ? [store categoryForDevice:device] : APBOutputCategoryNone];
    }]];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
    [_panel invalidateShadow];
    NSStatusBarButton *button = _statusItem.button;
    if (_panel.isVisible && button) [self positionPanelRelativeTo:button];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        APBStatusItemController *controller = weakSelf;
        if (!controller) return;
        NSWindow *panel = controller->_panel;
        if (!panel.isVisible || panel.attachedSheet || NSApp.modalWindow
            || [controller isRelatedToPanel:NSApp.keyWindow]) {
            return;
        }
        [controller hidePanelSuppressingNextClick:[controller isPointInStatusItem:NSEvent.mouseLocation]];
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
    if (!button || !window) return NO;
    return NSPointInRect(point, [window convertRectToScreen:[button convertRect:button.bounds toView:nil]]);
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

@end
