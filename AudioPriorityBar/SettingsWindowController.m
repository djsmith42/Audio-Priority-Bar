#import "SettingsWindowController.h"
#import "AppDelegate.h"
#import "KeyboardShortcuts.h"
#import "StatusItemRouting.h"
#import "StatusLabel.h"
#import "UIHelpers.h"

static const CGFloat FormWidth = 460;
/// A section's width inside the form's 20-point margins.
static const CGFloat SectionWidth = FormWidth - 40;
static NSString *const HomePage = @"https://github.com/camguillory/Audio-Priority-Bar/";

static void Pin(NSView *view, NSView *container, NSEdgeInsets insets) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
    ]];
}

static NSTextField *Wrapping(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = font;
    label.textColor = color;
    label.selectable = NO;
    return label;
}

/// A grouped form, like System Settings: rounded sections of rows, each
/// with an optional heading above and note below.
@interface APBForm : NSObject
@property (nonatomic, readonly) NSStackView *view;
- (void)addSection:(nullable NSString *)header rows:(NSArray<NSView *> *)rows footer:(nullable NSString *)footer;
/// A title, an optional note under it, and a control at the trailing edge.
+ (NSView *)rowWithTitle:(nullable NSString *)title subtitle:(nullable NSString *)subtitle control:(nullable NSView *)control;
/// A row of arbitrary content.
+ (NSView *)rowWithContent:(NSView *)content;
@end

@implementation APBForm

- (instancetype)init {
    if ((self = [super init])) {
        _view = [[NSStackView alloc] init];
        _view.orientation = NSUserInterfaceLayoutOrientationVertical;
        _view.alignment = NSLayoutAttributeCenterX;
        _view.spacing = 20;
        _view.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
        [_view.widthAnchor constraintEqualToConstant:FormWidth].active = YES;
    }
    return self;
}

- (void)addSection:(NSString *)header rows:(NSArray<NSView *> *)rows footer:(NSString *)footer {
    NSStackView *section = [[NSStackView alloc] init];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.spacing = 6;
    if (header) {
        NSTextField *title = APBLabel(header, [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
        title.accessibilityRole = NSAccessibilityStaticTextRole;
        APBAddArranged(section, [self indented:title by:10], SectionWidth);
    }
    APBFillView *box = [[APBFillView alloc] init];
    box.fillColor = NSColor.quaternarySystemFillColor;
    box.cornerRadius = 8;
    NSStackView *rowStack = [[NSStackView alloc] init];
    rowStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rowStack.spacing = 0;
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger index, BOOL *stop) {
        if (index > 0) APBAddArranged(rowStack, [self indented:[[APBSeparatorView alloc] init] by:10], SectionWidth);
        APBAddArranged(rowStack, row, SectionWidth);
    }];
    [box addSubview:rowStack];
    Pin(rowStack, box, NSEdgeInsetsZero);
    APBAddArranged(section, box, SectionWidth);
    if (footer) {
        APBAddArranged(section, [self indented:Wrapping(footer, [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor) by:10], SectionWidth);
    }
    APBAddArranged(_view, section, SectionWidth);
}

- (NSView *)indented:(NSView *)view by:(CGFloat)inset {
    NSView *container = [[NSView alloc] init];
    [container addSubview:view];
    Pin(view, container, NSEdgeInsetsMake(0, inset, 0, inset));
    return container;
}

+ (NSView *)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle control:(NSView *)control {
    NSStackView *labels = [[NSStackView alloc] init];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 2;
    if (title) [labels addArrangedSubview:Wrapping(title, [NSFont systemFontOfSize:13], NSColor.labelColor)];
    if (subtitle) [labels addArrangedSubview:Wrapping(subtitle, [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor)];
    [labels setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labels setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:control ? @[labels, spacer, control] : @[labels, spacer]];
    row.spacing = 12;
    row.alignment = NSLayoutAttributeCenterY;
    if (control) {
        [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        if (title) control.accessibilityLabel = control.accessibilityLabel ?: title;
    }
    return [self rowWithContent:row];
}

+ (NSView *)rowWithContent:(NSView *)content {
    NSView *container = [[NSView alloc] init];
    [container addSubview:content];
    Pin(content, container, NSEdgeInsetsMake(8, 10, 8, 10));
    [container.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    return container;
}

@end

/// One tab, rebuilt or refreshed as its settings change.
@interface APBSettingsPane : NSViewController
@property (nonatomic, copy, nullable) void (^onSizeChange)(void);
- (void)refresh;
@end

@implementation APBSettingsPane

- (void)refresh {
}

/// Replaces the pane's content with `form`, keeping the window sized to it.
- (void)show:(APBForm *)form {
    self.view = form.view;
    [self.view layoutSubtreeIfNeeded];
    self.preferredContentSize = self.view.fittingSize;
    if (_onSizeChange) _onSizeChange();
}

- (NSSwitch *)switchWithAction:(SEL)action {
    NSSwitch *control = [[NSSwitch alloc] init];
    control.target = self;
    control.action = action;
    return control;
}

@end

static NSControlStateValue State(BOOL on) {
    return on ? NSControlStateValueOn : NSControlStateValueOff;
}

static BOOL IsOn(id sender) {
    // NSSwitch and NSButton both answer `state`.
    return [(NSSwitch *)sender state] == NSControlStateValueOn;
}

#pragma mark - Menu Bar

@interface APBMenuBarPane : APBSettingsPane
@end

@implementation APBMenuBarPane {
    APBAppModel *_model;
    NSImageView *_preview;
    NSTextField *_clock;
    NSPopUpButton *_shows;
    NSSwitch *_outline, *_volume, *_switchNotice, *_reminder;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    if ((self = [super initWithNibName:nil bundle:nil])) _model = model;
    return self;
}

- (void)loadView {
    APBForm *form = [[APBForm alloc] init];
    [form addSection:nil rows:@[[APBForm rowWithContent:self.menuBarPreview]] footer:nil];

    _shows = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_shows addItemsWithTitles:@[@"Output only", @"Output and microphone", @"Output and microphone, labeled"]];
    _shows.target = self;
    _shows.action = @selector(showsChanged:);
    _outline = [self switchWithAction:@selector(outlineToggled:)];
    _volume = [self switchWithAction:@selector(volumeToggled:)];
    [form addSection:@"Icon" rows:@[
        [APBForm rowWithTitle:@"Shows" subtitle:nil control:_shows],
        [APBForm rowWithTitle:@"Outline" subtitle:nil control:_outline],
        [APBForm rowWithTitle:@"Volume level" subtitle:@"Shown beside AirPods and other device icons." control:_volume],
    ] footer:nil];

    _switchNotice = [self switchWithAction:@selector(switchNoticeToggled:)];
    _reminder = [self switchWithAction:@selector(reminderToggled:)];
    [form addSection:@"Notices" rows:@[
        [APBForm rowWithTitle:@"Show a notice when switching automatically" subtitle:nil control:_switchNotice],
        [APBForm rowWithTitle:@"Remind me when an app records while muted" subtitle:nil control:_reminder],
    ] footer:nil];
    [self show:form];
    [self refresh];
}

/// The real menu bar icon between the system items it sits beside, so the
/// icon options show their effect instead of describing it.
- (NSView *)menuBarPreview {
    NSImageView *wifi = [NSImageView imageViewWithImage:APBSymbol(@"wifi", 14, NSFontWeightRegular)];
    NSImageView *sound = [NSImageView imageViewWithImage:APBSymbol(@"speaker.wave.2.fill", 14, NSFontWeightRegular)];
    wifi.contentTintColor = sound.contentTintColor = NSColor.secondaryLabelColor;
    _preview = [[NSImageView alloc] init];
    _preview.contentTintColor = NSColor.labelColor;
    _clock = APBLabel(@"", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
    NSStackView *items = [NSStackView stackViewWithViews:@[wifi, sound, _preview, _clock]];
    items.spacing = 14;
    APBFillView *bar = [[APBFillView alloc] init];
    bar.fillColor = NSColor.quaternaryLabelColor;
    bar.cornerRadius = 7;
    [bar addSubview:items];
    items.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [items.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [items.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-14],
        [items.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [bar.heightAnchor constraintEqualToConstant:30],
    ]];
    bar.accessibilityElement = NO;
    NSView *centered = [[NSView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [centered addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.centerXAnchor constraintEqualToAnchor:centered.centerXAnchor],
        [bar.topAnchor constraintEqualToAnchor:centered.topAnchor constant:4],
        [bar.bottomAnchor constraintEqualToAnchor:centered.bottomAnchor constant:-4],
    ]];
    return centered;
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    _preview.image = [APBStatusLabel imageForModel:_model];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocalizedDateFormatFromTemplate:@"EEEjmm"];
    _clock.stringValue = [formatter stringFromDate:[NSDate date]];
    [_shows selectItemAtIndex:(NSInteger)_model.menuBarDevices];
    _outline.state = State(_model.outlinesMenuBarIcon);
    _volume.state = State(_model.showsMenuBarVolume);
    _switchNotice.state = State(_model.showsSwitchNotice);
    _reminder.state = State(_model.remindsWhenMuted);
}

- (void)showsChanged:(NSPopUpButton *)sender {
    [_model setMenuBarDevicesChoice:(APBMenuBarDevices)sender.indexOfSelectedItem];
}

- (void)outlineToggled:(id)sender { [_model setOutlinesMenuBarIconEnabled:IsOn(sender)]; }
- (void)volumeToggled:(id)sender { [_model setShowsMenuBarVolumeEnabled:IsOn(sender)]; }
- (void)switchNoticeToggled:(id)sender { [_model setShowsSwitchNoticeEnabled:IsOn(sender)]; }
- (void)reminderToggled:(id)sender { [_model setRemindsWhenMutedEnabled:IsOn(sender)]; }

@end

#pragma mark - Devices

@interface APBDevicesPane : APBSettingsPane
@end

@implementation APBDevicesPane {
    APBAppModel *_model;
    NSSwitch *_paired, *_hideDisplays, *_muteSpeakers;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    if ((self = [super initWithNibName:nil bundle:nil])) _model = model;
    return self;
}

- (void)loadView {
    APBForm *form = [[APBForm alloc] init];
    _paired = [self switchWithAction:@selector(pairedToggled:)];
    _hideDisplays = [self switchWithAction:@selector(hideDisplaysToggled:)];
    _muteSpeakers = [self switchWithAction:@selector(muteSpeakersToggled:)];
    [form addSection:nil rows:@[
        [APBForm rowWithTitle:@"Select headset input and output together" subtitle:nil control:_paired],
        [APBForm rowWithTitle:@"Hide new HDMI and DisplayPort outputs"
                     subtitle:@"Find them under “Show hidden and disconnected devices” in the panel."
                      control:_hideDisplays],
        [APBForm rowWithTitle:@"Mute speakers when headphones disconnect"
                     subtitle:@"Including when they're turned off or run out of battery."
                      control:_muteSpeakers],
    ] footer:nil];
    [self show:form];
    [self refresh];
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    _paired.state = State(_model.selectsPairedDevice);
    _hideDisplays.state = State(_model.hideNewDisplayOutputs);
    _muteSpeakers.state = State(_model.mutesSpeakersWhenHeadphonesDisconnect);
}

- (void)pairedToggled:(id)sender { [_model setSelectsPairedDeviceEnabled:IsOn(sender)]; }
- (void)hideDisplaysToggled:(id)sender { [_model setHideNewDisplayOutputsEnabled:IsOn(sender)]; }
- (void)muteSpeakersToggled:(id)sender { [_model setMutesSpeakersWhenHeadphonesDisconnectEnabled:IsOn(sender)]; }

@end

#pragma mark - Shortcuts

@interface APBShortcutsPane : APBSettingsPane
@end

@implementation APBShortcutsPane

- (NSString *)titleForCommand:(APBURLCommand)command {
    switch (command) {
        case APBURLCommandToggleMicMute: return @"Toggle microphone mute";
        case APBURLCommandMuteMic: return @"Mute microphone";
        case APBURLCommandUnmuteMic: return @"Unmute microphone";
        case APBURLCommandNone: return @"";
    }
    return @"";
}

- (void)loadView {
    APBForm *form = [[APBForm alloc] init];
    APBShortcutRecorder *recorder = [[APBShortcutRecorder alloc] initWithName:APBToggleMicrophoneMuteShortcut];
    [form addSection:nil rows:@[[APBForm rowWithTitle:@"Mute microphone" subtitle:nil control:recorder]] footer:nil];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSNumber *command in APBURLCommandAllCases()) {
        NSString *url = [NSString stringWithFormat:@"%@://%@", APBURLCommandScheme, APBURLCommandRawValue(command.integerValue)];
        NSButton *copy = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyURL:)];
        copy.identifier = url;
        copy.accessibilityLabel = [NSString stringWithFormat:@"Copy %@", url];
        NSTextField *title = APBLabel([self titleForCommand:command.integerValue], [NSFont systemFontOfSize:13], NSColor.labelColor);
        NSTextField *link = APBLabel(url, [NSFont monospacedSystemFontOfSize:APBCaptionSize weight:NSFontWeightRegular],
                                     NSColor.secondaryLabelColor);
        link.selectable = YES;
        NSStackView *labels = [NSStackView stackViewWithViews:@[title, link]];
        labels.orientation = NSUserInterfaceLayoutOrientationVertical;
        labels.alignment = NSLayoutAttributeLeading;
        labels.spacing = 2;
        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *row = [NSStackView stackViewWithViews:@[labels, spacer, copy]];
        [rows addObject:[APBForm rowWithContent:row]];
    }
    [form addSection:@"URLs" rows:rows footer:@"Open them from Shortcuts, Raycast, a Stream Deck or Terminal."];
    [self show:form];
}

- (void)copyURL:(NSButton *)sender {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:sender.identifier forType:NSPasteboardTypeString];
}

@end

#pragma mark - App

@interface APBAppPane : APBSettingsPane
@end

@implementation APBAppPane {
    APBLaunchAtLoginController *_launchAtLogin;
    APBUpdateChecker *_updates;
    NSSwitch *_openAtLogin;
    NSSwitch *_automaticUpdates;
    BOOL _builtRequiresApproval;
    NSString *_builtError;
}

- (instancetype)initWithLaunchAtLogin:(APBLaunchAtLoginController *)launchAtLogin updates:(APBUpdateChecker *)updates {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _launchAtLogin = launchAtLogin;
        _updates = updates;
        // Approving in System Settings happens while this window stays open.
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(appDidBecomeActive:)
                                                   name:NSApplicationDidBecomeActiveNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    [_launchAtLogin refresh];
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [_launchAtLogin refresh];
}

- (void)loadView {
    [self build];
}

- (void)build {
    APBForm *form = [[APBForm alloc] init];
    _openAtLogin = [self switchWithAction:@selector(openAtLoginToggled:)];
    NSMutableArray *loginRows = [NSMutableArray arrayWithObject:
        [APBForm rowWithTitle:@"Open at Login" subtitle:nil control:_openAtLogin]];
    _builtRequiresApproval = _launchAtLogin.requiresApproval;
    _builtError = _launchAtLogin.errorMessage;
    if (_builtRequiresApproval) {
        NSButton *open = [NSButton buttonWithTitle:@"Open Login Items" target:self action:@selector(openLoginItems:)];
        [loginRows addObject:[APBForm rowWithTitle:@"Approval needed in Login Items" subtitle:nil control:open]];
    }
    if (_builtError) {
        NSTextField *error = Wrapping([NSString stringWithFormat:@"Open at Login failed: %@", _builtError],
                                      [NSFont systemFontOfSize:13], NSColor.systemRedColor);
        [loginRows addObject:[APBForm rowWithContent:error]];
    }
    [form addSection:nil rows:loginRows footer:nil];

    if (_updates.isAvailable) {
        _automaticUpdates = [self switchWithAction:@selector(automaticUpdatesToggled:)];
        NSButton *check = [NSButton buttonWithTitle:@"Check for Updates…" target:self action:@selector(checkForUpdates:)];
        NSStackView *checkRow = [NSStackView stackViewWithViews:@[check]];
        checkRow.alignment = NSLayoutAttributeCenterY;
        [form addSection:@"Updates" rows:@[
            [APBForm rowWithTitle:@"Install updates automatically"
                         subtitle:@"Checks daily and restarts the app after installing."
                          control:_automaticUpdates],
            [APBForm rowWithContent:checkRow],
        ] footer:nil];
    } else {
        _automaticUpdates = nil;
        [form addSection:@"Updates" rows:@[[APBForm rowWithContent:Wrapping(@"Updates are off in development builds.",
                                                                              [NSFont systemFontOfSize:13],
                                                                              NSColor.secondaryLabelColor)]] footer:nil];
    }

    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;
    [icon.heightAnchor constraintEqualToConstant:22].active = YES;
    icon.accessibilityElement = NO;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSTextField *versionLabel = APBLabel([NSString stringWithFormat:@"Version %@", version],
                                         [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    NSButton *home = [NSButton buttonWithTitle:@"Home Page" target:self action:@selector(openHomePage:)];
    home.bordered = NO;
    home.attributedTitle = [[NSAttributedString alloc] initWithString:@"Home Page" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: NSColor.linkColor,
    }];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *quit = [NSButton buttonWithTitle:@"Quit Audio Priority Bar" target:NSApp action:@selector(terminate:)];
    NSStackView *about = [NSStackView stackViewWithViews:@[icon, versionLabel, home, spacer, quit]];
    about.spacing = 8;
    [form addSection:nil rows:@[[APBForm rowWithContent:about]] footer:nil];
    [self show:form];
    [self refresh];
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    if (_builtRequiresApproval != _launchAtLogin.requiresApproval
        || !(_builtError == _launchAtLogin.errorMessage || [_builtError isEqualToString:_launchAtLogin.errorMessage])) {
        [self build];
        return;
    }
    _openAtLogin.state = State(_launchAtLogin.isEnabled);
    _automaticUpdates.state = State(_updates.automaticUpdatesEnabled);
}

- (void)openAtLoginToggled:(id)sender { [_launchAtLogin setEnabled:IsOn(sender)]; }
- (void)automaticUpdatesToggled:(id)sender { [_updates setAutomaticUpdatesEnabled:IsOn(sender)]; }
- (void)checkForUpdates:(id)sender { [_updates checkForUpdates]; }
- (void)openLoginItems:(id)sender { [SMAppService openSystemSettingsLoginItems]; }

- (void)openHomePage:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:HomePage]];
}

@end

#pragma mark - Window

/// Sizes the window to each tab, which is as tall as its content.
@interface APBSettingsTabs : NSTabViewController
@end

@implementation APBSettingsTabs

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [super tabView:tabView didSelectTabViewItem:tabViewItem];
    [self fitWindow];
}

- (void)fitWindow {
    NSWindow *window = self.view.window;
    APBSettingsPane *pane = (APBSettingsPane *)self.tabViewItems[(NSUInteger)self.selectedTabViewItemIndex].viewController;
    if (!window || !pane.isViewLoaded) return;
    NSSize size = pane.view.fittingSize;
    NSRect content = [window contentRectForFrameRect:window.frame];
    if (NSEqualSizes(content.size, size)) return;
    NSRect frame = [window frameRectForContentRect:NSMakeRect(NSMinX(content), NSMaxY(content) - size.height,
                                                              size.width, size.height)];
    [window setFrame:frame display:YES animate:window.isVisible && !APBReduceMotion()];
}

@end

@implementation APBSettingsWindowController {
    APBAppModel *_model;
    NSArray<APBSettingsPane *> *_panes;
    APBSettingsTabs *_tabs;
}

- (instancetype)initWithModel:(APBAppModel *)model
                launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                      updates:(APBUpdateChecker *)updates {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, FormWidth, 300)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    if ((self = [super initWithWindow:window])) {
        _model = model;
        window.title = [NSString stringWithFormat:@"%@ Settings", APBAppDisplayName];
        _panes = @[
            [[APBMenuBarPane alloc] initWithModel:model],
            [[APBDevicesPane alloc] initWithModel:model],
            [[APBShortcutsPane alloc] init],
            [[APBAppPane alloc] initWithLaunchAtLogin:launchAtLogin updates:updates],
        ];
        NSArray *labels = @[@"Menu Bar", @"Devices", @"Shortcuts", @"App"];
        NSArray *symbols = @[@"menubar.rectangle", @"hifispeaker.2", @"command", @"gearshape"];
        _tabs = [[APBSettingsTabs alloc] init];
        _tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
        __weak typeof(self) weakSelf = self;
        [_panes enumerateObjectsUsingBlock:^(APBSettingsPane *pane, NSUInteger index, BOOL *stop) {
            pane.onSizeChange = ^{
                APBSettingsWindowController *controller = weakSelf;
                if (controller) [controller->_tabs fitWindow];
            };
            NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:pane];
            item.label = labels[index];
            item.image = [NSImage imageWithSystemSymbolName:symbols[index] accessibilityDescription:nil];
            [self->_tabs addTabViewItem:item];
        }];
        window.contentViewController = _tabs;
        window.toolbarStyle = NSWindowToolbarStylePreference;
        window.releasedWhenClosed = NO;
        [_tabs fitWindow];
        [window center];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(refresh)
                                                   name:APBAppModelDidChangeNotification
                                                 object:model];
        launchAtLogin.onChange = ^{ [weakSelf refresh]; };
        updates.onChange = ^{ [weakSelf refresh]; };
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refresh {
    if (!self.window.isVisible) return;
    for (APBSettingsPane *pane in _panes) [pane refresh];
}

- (void)showSettingsOnScreen:(NSScreen *)screen {
    [NSApp activateIgnoringOtherApps:YES];
    NSWindow *window = self.window;
    NSScreen *target = screen ?: NSScreen.mainScreen;
    if (window && target) {
        NSValue *origin = [APBSettingsPlacement originForWindow:window.frame
                                                    screenFrame:target.frame
                                                   visibleFrame:target.visibleFrame];
        if (origin) [window setFrameOrigin:origin.pointValue];
    }
    for (APBSettingsPane *pane in _panes) [pane refresh];
    [self showWindow:nil];
    // The recorder records only when clicked, not when the window opens.
    [window makeFirstResponder:nil];
}

@end
