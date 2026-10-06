#import "AppDelegate.h"
#import "AppRuntime.h"
#import "AudioPriorityCore.h"
#import "LaunchAtLoginController.h"
#import "SettingsWindowController.h"
#import "StatusItemController.h"

NSString *const APBAppDisplayName = @"Audio Priority Bar";

@implementation APBAppDelegate {
    APBAppRuntime *_runtime;
    APBSettingsWindowController *_settingsController;
    APBStatusItemController *_statusController;
    /// A URL that launched the app can arrive before the runtime exists.
    NSMutableArray<NSNumber *> *_pendingCommands;
}

- (instancetype)init {
    if ((self = [super init])) _pendingCommands = [NSMutableArray array];
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (NSProcessInfo.processInfo.environment[@"XCTestConfigurationFilePath"] != nil) return;
    [self configureMainMenu];
    APBAppRuntime *runtime = [[APBAppRuntime alloc] init];
    APBSettingsWindowController *settings = [[APBSettingsWindowController alloc]
        initWithModel:runtime.model
        launchAtLogin:[[APBLaunchAtLoginController alloc] init]
              updates:runtime.updates];
    _runtime = runtime;
    _settingsController = settings;
    _statusController = [[APBStatusItemController alloc] initWithModel:runtime.model
                                                              settings:settings
                                                               updates:runtime.updates];
    if (![runtime start]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp activateIgnoringOtherApps:YES];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Audio monitoring unavailable";
            alert.informativeText = @"Audio Priority Bar loaded the current devices but cannot monitor "
                                    @"audio changes. Quit and reopen the app to try again.";
            [alert runModal];
        });
    }
    for (NSNumber *command in _pendingCommands) [runtime.model perform:command.integerValue];
    [_pendingCommands removeAllObjects];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_runtime stop];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        APBURLCommand command = APBURLCommandFromURL(url);
        if (command == APBURLCommandNone) continue;
        if (_runtime) {
            [_runtime.model perform:command];
        } else {
            [_pendingCommands addObject:@(command)];
        }
    }
}

- (void)configureMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *settings = [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [appMenu addItemWithTitle:@"Quit Audio Priority Bar"
                                          action:@selector(terminate:)
                                   keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

- (void)showSettings:(id)sender {
    [_settingsController showSettingsOnScreen:nil];
}

@end
