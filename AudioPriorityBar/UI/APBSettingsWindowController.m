#import "APBSettingsWindowController.h"
#import <objc/runtime.h>
#import "APBStatusItemController.h"
#import "APBUI.h"

/// Links a form row to the divider drawn above it. Rows and dividers live in
/// the same list, so neither outlives the other.
static char DividerKey;

static NSString *const HomePageURL = @"https://github.com/camguillory/Audio-Priority-Bar/";
static const CGFloat FormWidth = 460;
static const CGFloat FormInset = 20;
static const CGFloat RowInset = 10;

@implementation APBSettingsPlacement

+ (NSValue *)originForWindow:(NSRect)frame screenFrame:(NSRect)screenFrame visibleFrame:(NSRect)visibleFrame {
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    if (NSPointInRect(center, screenFrame)) return nil;
    return [NSValue valueWithPoint:NSMakePoint(NSMidX(visibleFrame) - NSWidth(frame) / 2,
                                               NSMidY(visibleFrame) - NSHeight(frame) / 2)];
}

@end

#pragma mark - Form building

/// A grouped form section: an optional header, rounded box of rows divided by
/// separators, and an optional footer, like SwiftUI's grouped `Form`.
@interface APBFormSection : NSStackView
+ (instancetype)sectionWithHeader:(nullable NSString *)header rows:(NSArray<NSView *> *)rows footer:(nullable NSString *)footer;
@end

@implementation APBFormSection

+ (instancetype)sectionWithHeader:(NSString *)header rows:(NSArray<NSView *> *)rows footer:(NSString *)footer {
    APBFormSection *section = [[self alloc] init];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 6;
    section.detachesHiddenViews = YES;

    if (header) {
        NSTextField *title = APBLabel(header, [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
        NSStackView *titleRow = [NSStackView stackViewWithViews:@[ title ]];
        titleRow.edgeInsets = NSEdgeInsetsMake(0, RowInset, 0, RowInset);
        [section addArrangedSubview:titleRow];
    }

    APBFillView *box = [[APBFillView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.cornerRadius = 8;
    box.fillColor = APBPrimary(0.04);
    box.borderColor = APBPrimary(0.06);
    box.borderWidth = 1;
    NSStackView *list = [[NSStackView alloc] init];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 0;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    list.detachesHiddenViews = YES;
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger index, BOOL *stop) {
        if (index > 0) {
            NSView *divider = [[NSView alloc] init];
            APBSeparator *line = [APBSeparator separator];
            [divider addSubview:line];
            [NSLayoutConstraint activateConstraints:@[
                [line.leadingAnchor constraintEqualToAnchor:divider.leadingAnchor constant:RowInset],
                [line.trailingAnchor constraintEqualToAnchor:divider.trailingAnchor constant:-RowInset],
                [line.centerYAnchor constraintEqualToAnchor:divider.centerYAnchor],
                [divider.heightAnchor constraintEqualToConstant:1],
            ]];
            [list addArrangedSubview:divider];
            [divider.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
            objc_setAssociatedObject(row, &DividerKey, divider, OBJC_ASSOCIATION_ASSIGN);
        }
        [list addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    }];
    [box addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [list.topAnchor constraintEqualToAnchor:box.topAnchor],
        [list.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
    ]];
    [section addArrangedSubview:box];
    [box.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;

    if (footer) {
        NSTextField *text = APBWrappingLabel(footer, [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor, 0);
        NSStackView *footerRow = [NSStackView stackViewWithViews:@[ text ]];
        footerRow.edgeInsets = NSEdgeInsetsMake(0, RowInset, 0, RowInset);
        [section addArrangedSubview:footerRow];
        [footerRow.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    }
    return section;
}

@end

/// Hides a form row together with the divider above it.
static void SetRowHidden(NSView *row, BOOL hidden) {
    row.hidden = hidden;
    NSView *divider = objc_getAssociatedObject(row, &DividerKey);
    divider.hidden = hidden;
}

/// One form row: a title with an optional subtitle on the left, a control on
/// the right.
static NSView *FormRow(NSString *title, NSString *subtitle, NSView *control) {
    NSTextField *titleLabel = APBWrappingLabel(title, [NSFont systemFontOfSize:13], NSColor.labelColor, 0);
    NSStackView *labels = [NSStackView stackViewWithViews:@[ titleLabel ]];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 2;
    if (subtitle) {
        [labels addArrangedSubview:APBWrappingLabel(subtitle, [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor, 0)];
    }
    [labels setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray *views = [NSMutableArray arrayWithObject:labels];
    if (control) {
        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [views addObjectsFromArray:@[ spacer, control ]];
        [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    row.edgeInsets = NSEdgeInsetsMake(8, RowInset, 8, RowInset);
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    if (control) {
        [titleLabel setAccessibilityElement:NO];
        if (!control.accessibilityLabel) [control setAccessibilityLabel:title];
    }
    return row;
}

static NSSwitch *Switch(id target, SEL action) {
    NSSwitch *control = [[NSSwitch alloc] init];
    control.target = target;
    control.action = action;
    control.controlSize = NSControlSizeMini;
    return control;
}

#pragma mark - Pane

typedef NS_ENUM(NSInteger, APBSettingsPane) {
    APBSettingsPaneMenuBar,
    APBSettingsPaneDevices,
    APBSettingsPaneShortcuts,
    APBSettingsPaneApp,
};

/// The real menu bar icon between the system items it sits beside, so the
/// icon options show their effect instead of describing it.
@interface APBMenuBarPreview : APBFillView
- (instancetype)initWithModel:(APBAppModel *)model;
- (void)refresh;
@end

@implementation APBMenuBarPreview {
    APBAppModel *_model;
    NSImageView *_icon;
    NSTextField *_clock;
}

- (instancetype)initWithModel:(APBAppModel *)model {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _model = model;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.cornerRadius = 7;
        self.fillColor = APBPrimary(0.1);
        NSImageView *wifi = [NSImageView imageViewWithImage:APBSymbol(@"wifi", 14, NSFontWeightRegular)];
        NSImageView *speaker = [NSImageView imageViewWithImage:APBSymbol(@"speaker.wave.2.fill", 14, NSFontWeightRegular)];
        wifi.contentTintColor = NSColor.secondaryLabelColor;
        speaker.contentTintColor = NSColor.secondaryLabelColor;
        _icon = [[NSImageView alloc] init];
        _icon.contentTintColor = NSColor.labelColor;
        _clock = APBLabel(@"", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
        NSStackView *stack = [NSStackView stackViewWithViews:@[ wifi, speaker, _icon, _clock ]];
        stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:30],
        ]];
        [self setAccessibilityElement:NO];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    _icon.image = [APBStatusLabel imageForModel:_model];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = NSLocale.currentLocale;
    [formatter setLocalizedDateFormatFromTemplate:@"EEEjmm"];
    _clock.stringValue = [formatter stringFromDate:[NSDate date]];
}

@end

@interface APBSettingsPaneController : NSViewController
- (instancetype)initWithPane:(APBSettingsPane)pane
                       model:(APBAppModel *)model
               launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                     updates:(APBUpdateChecker *)updates
                  muteHotKey:(APBHotKey *)muteHotKey;
- (void)refresh;
@end

@implementation APBSettingsPaneController {
    APBSettingsPane _pane;
    APBAppModel *_model;
    APBLaunchAtLoginController *_launchAtLogin;
    APBUpdateChecker *_updates;
    APBHotKey *_muteHotKey;

    APBMenuBarPreview *_preview;
    NSPopUpButton *_shows;
    NSSwitch *_outline;
    NSSwitch *_volume;
    NSSwitch *_switchNotice;
    NSSwitch *_mutedReminder;
    NSSwitch *_pairs;
    NSSwitch *_hideDisplays;
    NSSwitch *_openAtLogin;
    NSView *_approvalRow;
    NSTextField *_loginError;
    NSSwitch *_automaticUpdates;
}

- (instancetype)initWithPane:(APBSettingsPane)pane
                       model:(APBAppModel *)model
               launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                     updates:(APBUpdateChecker *)updates
                  muteHotKey:(APBHotKey *)muteHotKey {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pane = pane;
        _model = model;
        _launchAtLogin = launchAtLogin;
        _updates = updates;
        _muteHotKey = muteHotKey;
    }
    return self;
}

- (void)loadView {
    NSArray<NSView *> *sections;
    switch (_pane) {
        case APBSettingsPaneMenuBar: sections = self.menuBarSections; break;
        case APBSettingsPaneDevices: sections = self.devicesSections; break;
        case APBSettingsPaneShortcuts: sections = self.shortcutsSections; break;
        case APBSettingsPaneApp: sections = self.appSections; break;
    }
    NSStackView *stack = [NSStackView stackViewWithViews:sections];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 18;
    stack.edgeInsets = NSEdgeInsetsMake(FormInset, FormInset, FormInset, FormInset);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *section in sections) {
        [section.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-FormInset * 2].active = YES;
    }
    // Each tab is as tall as its content, so the window resizes to fit it.
    [stack.widthAnchor constraintEqualToConstant:FormWidth].active = YES;
    self.view = stack;
    [self refresh];
}

- (void)viewWillAppear {
    [super viewWillAppear];
    if (_pane == APBSettingsPaneApp) [_launchAtLogin refresh];
    [self refresh];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    // Matches the window to this tab's content.
    self.preferredContentSize = self.view.fittingSize;
}

#pragma mark Menu Bar

- (NSArray<NSView *> *)menuBarSections {
    _preview = [[APBMenuBarPreview alloc] initWithModel:_model];
    NSView *previewRow = [[NSView alloc] init];
    [previewRow addSubview:_preview];
    [NSLayoutConstraint activateConstraints:@[
        [_preview.centerXAnchor constraintEqualToAnchor:previewRow.centerXAnchor],
        [_preview.topAnchor constraintEqualToAnchor:previewRow.topAnchor constant:14],
        [_preview.bottomAnchor constraintEqualToAnchor:previewRow.bottomAnchor constant:-14],
    ]];

    _shows = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_shows addItemsWithTitles:@[ @"Output only", @"Output and microphone", @"Output and microphone, labeled" ]];
    _shows.target = self;
    _shows.action = @selector(showsChanged:);
    _outline = Switch(self, @selector(outlineChanged:));
    _volume = Switch(self, @selector(volumeChanged:));
    _switchNotice = Switch(self, @selector(switchNoticeChanged:));
    _mutedReminder = Switch(self, @selector(mutedReminderChanged:));

    return @[
        [APBFormSection sectionWithHeader:nil rows:@[ previewRow ] footer:nil],
        [APBFormSection sectionWithHeader:@"Icon" rows:@[
            FormRow(@"Shows", nil, _shows),
            FormRow(@"Outline", nil, _outline),
            FormRow(@"Volume level", @"Shown beside AirPods and other device icons.", _volume),
        ] footer:nil],
        [APBFormSection sectionWithHeader:@"Notices" rows:@[
            FormRow(@"Show a notice when switching automatically", nil, _switchNotice),
            FormRow(@"Remind me when an app records while muted", nil, _mutedReminder),
        ] footer:nil],
    ];
}

- (void)showsChanged:(NSPopUpButton *)sender {
    [_model setMenuBarDevices:(APBMenuBarDevices)sender.indexOfSelectedItem];
}

- (void)outlineChanged:(NSSwitch *)sender {
    [_model setOutlinesMenuBarIcon:sender.state == NSControlStateValueOn];
}

- (void)volumeChanged:(NSSwitch *)sender {
    [_model setShowsMenuBarVolume:sender.state == NSControlStateValueOn];
}

- (void)switchNoticeChanged:(NSSwitch *)sender {
    [_model setShowsSwitchNotice:sender.state == NSControlStateValueOn];
}

- (void)mutedReminderChanged:(NSSwitch *)sender {
    [_model setRemindsWhenMuted:sender.state == NSControlStateValueOn];
}

#pragma mark Devices

- (NSArray<NSView *> *)devicesSections {
    _pairs = Switch(self, @selector(pairsChanged:));
    _hideDisplays = Switch(self, @selector(hideDisplaysChanged:));
    return @[
        [APBFormSection sectionWithHeader:nil rows:@[
            FormRow(@"Select headset input and output together", nil, _pairs),
            FormRow(@"Hide new HDMI and DisplayPort outputs",
                    @"Find them under “Show hidden and disconnected devices” in the panel.", _hideDisplays),
        ] footer:nil],
    ];
}

- (void)pairsChanged:(NSSwitch *)sender {
    [_model setSelectsPairedDevice:sender.state == NSControlStateValueOn];
}

- (void)hideDisplaysChanged:(NSSwitch *)sender {
    [_model setHideNewDisplayOutputs:sender.state == NSControlStateValueOn];
}

#pragma mark Shortcuts

static NSString *CommandTitle(APBURLCommand command) {
    switch (command) {
        case APBURLCommandToggleMicMute: return @"Toggle microphone mute";
        case APBURLCommandMuteMic: return @"Mute microphone";
        case APBURLCommandUnmuteMic: return @"Unmute microphone";
        case APBURLCommandNone: return @"";
    }
    return @"";
}

- (NSArray<NSView *> *)shortcutsSections {
    APBShortcutRecorder *recorder = [[APBShortcutRecorder alloc] initWithHotKey:_muteHotKey];
    NSMutableArray *urlRows = [NSMutableArray array];
    for (NSNumber *command in APBURLCommandAll()) {
        NSString *url = [NSString stringWithFormat:@"%@://%@", APBURLCommandScheme, APBURLCommandRawValue(command.integerValue)];
        NSButton *copy = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyURL:)];
        copy.identifier = url;
        [copy setAccessibilityLabel:[NSString stringWithFormat:@"Copy %@", url]];
        NSView *row = FormRow(CommandTitle(command.integerValue), nil, copy);
        // The URL itself, selectable so it can be copied by hand too.
        NSStackView *labels = (NSStackView *)((NSStackView *)row).arrangedSubviews.firstObject;
        NSTextField *urlLabel = [NSTextField labelWithString:url];
        urlLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        urlLabel.textColor = NSColor.secondaryLabelColor;
        urlLabel.selectable = YES;
        [labels addArrangedSubview:urlLabel];
        [urlRows addObject:row];
    }
    return @[
        [APBFormSection sectionWithHeader:nil rows:@[ FormRow(@"Mute microphone", nil, recorder) ] footer:nil],
        [APBFormSection sectionWithHeader:@"URLs" rows:urlRows
                                   footer:@"Open them from Shortcuts, Raycast, a Stream Deck or Terminal."],
    ];
}

- (void)copyURL:(NSButton *)sender {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:sender.identifier forType:NSPasteboardTypeString];
}

#pragma mark App

- (NSArray<NSView *> *)appSections {
    _openAtLogin = Switch(self, @selector(openAtLoginChanged:));
    NSButton *openLoginItems = [NSButton buttonWithTitle:@"Open Login Items" target:self action:@selector(openLoginItems:)];
    _approvalRow = FormRow(@"Approval needed in Login Items", nil, openLoginItems);
    _loginError = APBWrappingLabel(@"", [NSFont systemFontOfSize:13], NSColor.systemRedColor, 0);
    NSStackView *errorRow = [NSStackView stackViewWithViews:@[ _loginError ]];
    errorRow.edgeInsets = NSEdgeInsetsMake(8, RowInset, 8, RowInset);

    NSArray *updateRows;
    if (_updates.isAvailable) {
        _automaticUpdates = Switch(self, @selector(automaticUpdatesChanged:));
        NSButton *check = [NSButton buttonWithTitle:@"Check for Updates…" target:self action:@selector(checkForUpdates:)];
        NSStackView *checkRow = [NSStackView stackViewWithViews:@[ check ]];
        checkRow.edgeInsets = NSEdgeInsetsMake(8, RowInset, 8, RowInset);
        updateRows = @[
            FormRow(@"Install updates automatically", @"Checks daily and restarts the app after installing.", _automaticUpdates),
            checkRow,
        ];
    } else {
        NSStackView *row = [NSStackView stackViewWithViews:@[
            APBLabel(@"Updates are off in development builds.", [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor),
        ]];
        row.edgeInsets = NSEdgeInsetsMake(10, RowInset, 10, RowInset);
        updateRows = @[ row ];
    }

    NSImageView *appIcon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    appIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [appIcon setAccessibilityElement:NO];
    [NSLayoutConstraint activateConstraints:@[
        [appIcon.widthAnchor constraintEqualToConstant:22],
        [appIcon.heightAnchor constraintEqualToConstant:22],
    ]];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSTextField *versionLabel = APBLabel([NSString stringWithFormat:@"Version %@", version], [NSFont systemFontOfSize:13], NSColor.secondaryLabelColor);
    NSButton *homePage = [NSButton buttonWithTitle:@"Home Page" target:self action:@selector(openHomePage:)];
    homePage.bordered = NO;
    homePage.attributedTitle = [[NSAttributedString alloc] initWithString:@"Home Page" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: NSColor.linkColor,
    }];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *quit = [NSButton buttonWithTitle:@"Quit Audio Priority Bar" target:NSApp action:@selector(terminate:)];
    NSStackView *aboutRow = [NSStackView stackViewWithViews:@[ appIcon, versionLabel, homePage, spacer, quit ]];
    aboutRow.spacing = 8;
    aboutRow.edgeInsets = NSEdgeInsetsMake(8, RowInset, 8, RowInset);

    // Approving in System Settings happens while this window stays open.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidBecomeActive:)
                                               name:NSApplicationDidBecomeActiveNotification object:nil];

    return @[
        [APBFormSection sectionWithHeader:nil rows:@[ FormRow(@"Open at Login", nil, _openAtLogin), _approvalRow, errorRow ] footer:nil],
        [APBFormSection sectionWithHeader:@"Updates" rows:updateRows footer:nil],
        [APBFormSection sectionWithHeader:nil rows:@[ aboutRow ] footer:nil],
    ];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    [_launchAtLogin refresh];
    [self refresh];
}

- (void)openAtLoginChanged:(NSSwitch *)sender {
    [_launchAtLogin setEnabled:sender.state == NSControlStateValueOn];
    [self refresh];
}

- (void)openLoginItems:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

- (void)automaticUpdatesChanged:(NSSwitch *)sender {
    [_updates setAutomaticUpdatesEnabled:sender.state == NSControlStateValueOn];
}

- (void)checkForUpdates:(id)sender {
    [_updates checkForUpdates];
}

- (void)openHomePage:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:HomePageURL]];
}

#pragma mark Refresh

static NSControlStateValue State(BOOL on) {
    return on ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)refresh {
    if (!self.isViewLoaded) return;
    APBAppModel *model = _model;
    [_preview refresh];
    [_shows selectItemAtIndex:model.menuBarDevices];
    _outline.state = State(model.outlinesMenuBarIcon);
    _volume.state = State(model.showsMenuBarVolume);
    _switchNotice.state = State(model.showsSwitchNotice);
    _mutedReminder.state = State(model.remindsWhenMuted);
    _pairs.state = State(model.selectsPairedDevice);
    _hideDisplays.state = State(model.hideNewDisplayOutputs);
    _openAtLogin.state = State(_launchAtLogin.isEnabled);
    if (_approvalRow) SetRowHidden(_approvalRow, !_launchAtLogin.requiresApproval);
    if (_loginError) SetRowHidden(_loginError.superview, _launchAtLogin.errorMessage == nil);
    _loginError.stringValue = _launchAtLogin.errorMessage
        ? [NSString stringWithFormat:@"Open at Login failed: %@", _launchAtLogin.errorMessage]
        : @"";
    _automaticUpdates.state = State(_updates.automaticUpdatesEnabled);
    if (self.view.window) self.preferredContentSize = self.view.fittingSize;
}

@end

#pragma mark - Window controller

@implementation APBSettingsWindowController {
    NSArray<APBSettingsPaneController *> *_panes;
}

- (instancetype)initWithModel:(APBAppModel *)model
                launchAtLogin:(APBLaunchAtLoginController *)launchAtLogin
                      updates:(APBUpdateChecker *)updates
                   muteHotKey:(APBHotKey *)muteHotKey {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSZeroRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = [NSString stringWithFormat:@"%@ Settings", APBAppDisplayName];
    NSTabViewController *tabs = [[NSTabViewController alloc] init];
    tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
    NSArray *panes = @[
        @[ @(APBSettingsPaneMenuBar), @"Menu Bar", @"menubar.rectangle" ],
        @[ @(APBSettingsPaneDevices), @"Devices", @"hifispeaker.2" ],
        @[ @(APBSettingsPaneShortcuts), @"Shortcuts", @"command" ],
        @[ @(APBSettingsPaneApp), @"App", @"gearshape" ],
    ];
    NSMutableArray *controllers = [NSMutableArray array];
    for (NSArray *pane in panes) {
        APBSettingsPaneController *controller = [[APBSettingsPaneController alloc] initWithPane:[pane[0] integerValue]
                                                                                        model:model
                                                                                launchAtLogin:launchAtLogin
                                                                                      updates:updates
                                                                                   muteHotKey:muteHotKey];
        // Gives the window its real size before it is ever placed, so the
        // first open on another screen is centered on the actual height.
        [controller view];
        controller.preferredContentSize = controller.view.fittingSize;
        NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:controller];
        item.label = pane[1];
        item.image = [NSImage imageWithSystemSymbolName:pane[2] accessibilityDescription:nil];
        [tabs addTabViewItem:item];
        [controllers addObject:controller];
    }
    window.contentViewController = tabs;
    window.toolbarStyle = NSWindowToolbarStylePreference;
    window.releasedWhenClosed = NO;
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        _panes = controllers;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelDidChange:)
                                                   name:APBAppModelDidChangeNotification object:model];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)modelDidChange:(NSNotification *)notification {
    if (!self.window.isVisible) return;
    for (APBSettingsPaneController *pane in _panes) [pane refresh];
}

- (void)showSettingsOnScreen:(NSScreen *)screen {
    [NSApp activateIgnoringOtherApps:YES];
    for (APBSettingsPaneController *pane in _panes) [pane refresh];
    NSScreen *target = screen ?: NSScreen.mainScreen;
    NSWindow *window = self.window;
    if (window && target) {
        NSValue *origin = [APBSettingsPlacement originForWindow:window.frame
                                                    screenFrame:target.frame
                                                   visibleFrame:target.visibleFrame];
        if (origin) [window setFrameOrigin:origin.pointValue];
    }
    [self showWindow:nil];
}

@end
