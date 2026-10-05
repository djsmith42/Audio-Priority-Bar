#import "APBTestSupport.h"
#import <QuartzCore/QuartzCore.h>
#import "APBHotKey.h"
#import "APBNoticePanel.h"
#import "APBPanelView.h"
#import "APBServices.h"
#import "APBSettingsWindowController.h"
#import "APBStatusItemController.h"

/// Renders the panel, the menu bar icon and every Settings tab to PNGs, so
/// the layout can be inspected without a screen. Writes only when
/// `APB_SNAPSHOT_DIR` is set; otherwise it just checks the views lay out.
@interface APBSnapshotTests : XCTestCase
@end

@implementation APBSnapshotTests

- (APBAppModel *)populatedModel {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[
        APBOutput(1, @"builtin-out", @"MacBook Pro Speakers"),
        APBOutput(2, @"airpods-out", @"AirPods Pro"),
        APBOutput(3, @"AppleUSBAudioEngine:GN:Jabra Link 380:ABC:1", @"Jabra Link 380"),
        APBInput(4, @"builtin-in", @"MacBook Pro Microphone"),
        APBInput(5, @"AppleUSBAudioEngine:GN:Jabra Link 380:ABC:2", @"Jabra Link 380"),
    ];
    audio.volume = @0.55f;
    audio.inputVolumes[@4] = @0.7f;
    audio.inputVolumes[@5] = @0.8f;
    NSUserDefaults *defaults = APBIsolatedDefaults();
    // Puts the switched-off headset first, so the panel explains skipping it.
    [[[APBPriorityStore alloc] initWithDefaults:defaults] savePriorities:@[ audio.catalog[2], audio.catalog[1] ]
                                                                category:APBOutputCategoryHeadphone];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return ![device.name containsString:@"Jabra"];
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.name containsString:@"Jabra"] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);
    [model start];
    // CoreAudio echoes the selection, which rereads the levels.
    [model refreshVolume];
    return model;
}

- (NSString *)snapshotDirectory {
    return NSProcessInfo.processInfo.environment[@"APB_SNAPSHOT_DIR"];
}

- (void)write:(NSView *)view named:(NSString *)name appearance:(NSAppearanceName)appearanceName {
    NSAppearance *appearance = [NSAppearance appearanceNamed:appearanceName];
    view.appearance = appearance;
    [view layoutSubtreeIfNeeded];
    NSSize size = view.fittingSize;
    if (size.width < 1 || size.height < 1) size = view.frame.size;
    XCTAssertGreaterThan(size.width, 0, @"%@ has no width", name);
    XCTAssertGreaterThan(size.height, 0, @"%@ has no height", name);
    NSString *directory = self.snapshotDirectory;
    if (!directory) return;

    // A window gives the view a backing and real appearance resolution.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    window.appearance = appearance;
    window.backgroundColor = [appearanceName isEqualToString:NSAppearanceNameDarkAqua]
        ? [NSColor colorWithWhite:0.15 alpha:1]
        : [NSColor colorWithWhite:0.93 alpha:1];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    window.contentView = container;
    view.translatesAutoresizingMaskIntoConstraints = YES;
    view.frame = container.bounds;
    [container addSubview:view];
    [container layoutSubtreeIfNeeded];
    container.wantsLayer = YES;
    [container displayIfNeeded];
    [CATransaction flush];

    // Rendering the layer tree draws layer-backed fills and borders, which
    // `cacheDisplayInRect:` skips. Materials still render flat offscreen.
    CGFloat scale = 2;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                       pixelsWide:(NSInteger)(size.width * scale)
                                                                       pixelsHigh:(NSInteger)(size.height * scale)
                                                                    bitsPerSample:8
                                                                  samplesPerPixel:4
                                                                         hasAlpha:YES
                                                                         isPlanar:NO
                                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                                      bytesPerRow:0
                                                                     bitsPerPixel:0];
    bitmap.size = size;
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    // The context is already in points, since the bitmap's size is.
    CGContextRef cg = context.CGContext;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    [window.backgroundColor setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [appearance performAsCurrentDrawingAppearance:^{
        [container.layer renderInContext:cg];
    }];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString *suffix = [appearanceName isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light";
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", name, suffix]];
    [png writeToFile:path atomically:YES];
    [view removeFromSuperview];
    [window close];
}

/// The panel's content without its glass, which only the window server can
/// draw and which renders opaque offscreen.
- (NSView *)contentOf:(APBPanelView *)panel {
    NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:panel];
    while (queue.count) {
        NSView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:NSStackView.class]) {
            [view removeFromSuperview];
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [view.widthAnchor constraintEqualToConstant:APBPanelWidth].active = YES;
            return view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return panel;
}

- (void)testPanelLaysOut {
    APBAppModel *model = [self populatedModel];
    for (NSAppearanceName appearance in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]) {
        APBPanelView *panel = [[APBPanelView alloc] initWithModel:model];
        [panel refresh];
        [panel layoutSubtreeIfNeeded];
        XCTAssertEqual(panel.fittingSize.width, APBPanelWidth);
        [self write:[self contentOf:panel] named:@"panel" appearance:appearance];
    }
}

- (void)testPanelWithHiddenAndDisconnectedDevicesLaysOut {
    APBAppModel *model = [self populatedModel];
    [model setManualMode:YES];
    [model setMicrophoneMuted:YES];
    model.showAll = YES;
    [model refreshDevices];
    APBPanelView *panel = [[APBPanelView alloc] initWithModel:model];
    [panel refresh];
    [panel layoutSubtreeIfNeeded];
    [self write:[self contentOf:panel] named:@"panel-manual" appearance:NSAppearanceNameAqua];
}

- (void)testMenuBarIconsDraw {
    APBAppModel *model = [self populatedModel];
    NSMutableArray *images = [NSMutableArray array];
    for (NSNumber *devices in @[ @(APBMenuBarDevicesOutputOnly), @(APBMenuBarDevicesBoth), @(APBMenuBarDevicesBothLabeled) ]) {
        [model setMenuBarDevices:devices.integerValue];
        for (NSNumber *outlined in @[ @NO, @YES ]) {
            [model setOutlinesMenuBarIcon:outlined.boolValue];
            NSImage *image = [APBStatusLabel imageForModel:model];
            XCTAssertTrue(image.isTemplate);
            XCTAssertGreaterThan(image.size.width, 10);
            [images addObject:image];
        }
    }
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    for (NSImage *image in images) {
        NSImageView *view = [NSImageView imageViewWithImage:image];
        view.contentTintColor = NSColor.labelColor;
        [stack addArrangedSubview:view];
    }
    [self write:stack named:@"menubar-icons" appearance:NSAppearanceNameAqua];
    [self write:stack named:@"menubar-icons" appearance:NSAppearanceNameDarkAqua];
}

- (void)testSettingsTabsLayOut {
    APBAppModel *model = [self populatedModel];
    APBLaunchAtLoginController *login = [[APBLaunchAtLoginController alloc]
        initWithStatus:^SMAppServiceStatus { return SMAppServiceStatusRequiresApproval; }
              register:^BOOL(NSError **error) { return YES; }
            unregister:^BOOL(NSError **error) { return YES; }];
    APBUpdateChecker *updates = [[APBUpdateChecker alloc] initWithIsIdle:^BOOL { return YES; }];
    APBHotKey *hotKey = [[APBHotKey alloc] initWithName:[@"snapshot." stringByAppendingString:NSUUID.UUID.UUIDString]
                                                initial:APBShortcut.optionShiftM];
    APBSettingsWindowController *settings = [[APBSettingsWindowController alloc] initWithModel:model
                                                                                 launchAtLogin:login
                                                                                       updates:updates
                                                                                    muteHotKey:hotKey];
    NSTabViewController *tabs = (NSTabViewController *)settings.window.contentViewController;
    XCTAssertEqual(tabs.tabViewItems.count, 4u);
    for (NSTabViewItem *item in tabs.tabViewItems) {
        NSView *view = item.viewController.view;
        [self write:view named:[@"settings-" stringByAppendingString:item.label.lowercaseString] appearance:NSAppearanceNameAqua];
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"KeyboardShortcuts_" stringByAppendingString:hotKey.name]];
}

- (void)testNoticesAndHoverPreviewLayOut {
    APBAppModel *model = [self populatedModel];
    APBHoverPreviewPanel *preview = [[APBHoverPreviewPanel alloc] initWithModel:model placement:^NSValue *(NSSize size) {
        return nil;
    }];
    [preview refresh];
    [preview show];
    XCTAssertTrue(preview.isVisible);
    [preview hide];
}

@end
