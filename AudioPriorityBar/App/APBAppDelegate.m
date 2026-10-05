#import "APBAppDelegate.h"
#import "APBCoreAudio.h"
#import "APBJabraHIDMonitor.h"
#import "APBSettingsWindowController.h"
#import "APBStatusItemController.h"

@implementation APBAppRuntime {
    APBCoreAudioObserver *_audioObserver;
    APBJabraHIDMonitor *_jabra;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        APBCoreAudioObserver *audioObserver = [[APBCoreAudioObserver alloc] init];
        APBJabraHIDMonitor *jabra = [[APBJabraHIDMonitor alloc] init];
        _audioObserver = audioObserver;
        _jabra = jabra;
        __weak APBJabraHIDMonitor *weakJabra = jabra;
        _model = [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] init]
                                              audio:[[APBCoreAudioProperties alloc] init]
                                           isUsable:^BOOL(APBAudioDevice *device) {
                                               return device.isConnected && [weakJabra isUsable:device];
                                           }
                                          linkState:^APBLinkState(APBAudioDevice *device) {
                                              return [weakJabra monitoredStateForDevice:device];
                                          }
                                            battery:[[APBBluetoothBatteryMonitor alloc] init]
                                       reduceMotion:nil
                                      isUserPicking:^BOOL {
                                          return APBSystemSoundPicker.isInUse;
                                      }];
        __weak APBAppModel *weakModel = _model;
        _updates = [[APBUpdateChecker alloc] initWithIsIdle:^BOOL {
            APBAppModel *model = weakModel;
            return model ? !model.isMicrophoneMuted && !model.isInputRecording : YES;
        }];
        _muteHotKey = [[APBHotKey alloc] initWithName:@"toggleMicrophoneMute" initial:APBShortcut.optionShiftM];

        audioObserver.onDevicesChanged = ^{
            [weakModel handleDevicesChanged];
        };
        audioObserver.onDefaultChanged = ^(APBDeviceRole role) {
            [weakModel handleDefaultChanged:role];
        };
        audioObserver.onMuteOrVolumeChanged = ^{
            [weakModel handleMuteOrVolumeChanged];
        };
        jabra.onLinkChange = ^{
            [weakModel handleLinkChanged];
        };
    }
    return self;
}

- (BOOL)start {
    [_jabra start];
    BOOL isListening = [_audioObserver startListening];
    [_model start];
    [_updates start];
    __weak APBAppModel *weakModel = _model;
    _muteHotKey.onKeyUp = ^{
        [weakModel performCommand:APBURLCommandToggleMicMute];
    };
    return isListening;
}

- (void)stop {
    // Producers first: once they are down, no callback, timeout or debounce
    // can reach the model and restart work it just tore down.
    [_jabra stop];
    [_audioObserver stopListening];
    [_model stop];
}

@end

@implementation APBAppDelegate {
    APBAppRuntime *_runtime;
    APBSettingsWindowController *_settingsController;
    APBStatusItemController *_statusController;
    /// A URL that launched the app can arrive before the runtime exists.
    NSMutableArray<NSNumber *> *_pendingCommands;
}

- (instancetype)init {
    self = [super init];
    if (self) _pendingCommands = [NSMutableArray array];
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (NSProcessInfo.processInfo.environment[@"XCTestConfigurationFilePath"]) return;
    [self configureMainMenu];
    APBAppRuntime *runtime = [[APBAppRuntime alloc] init];
    APBSettingsWindowController *settings = [[APBSettingsWindowController alloc] initWithModel:runtime.model
                                                                                 launchAtLogin:[[APBLaunchAtLoginController alloc] init]
                                                                                       updates:runtime.updates
                                                                                    muteHotKey:runtime.muteHotKey];
    _runtime = runtime;
    _settingsController = settings;
    _statusController = [[APBStatusItemController alloc] initWithModel:runtime.model settings:settings updates:runtime.updates];
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
    for (NSNumber *command in _pendingCommands) [runtime.model performCommand:command.integerValue];
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
            [_runtime.model performCommand:command];
        } else {
            [_pendingCommands addObject:@(command)];
        }
    }
}

- (void)configureMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *settings = [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings) keyEquivalent:@","];
    settings.target = self;
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [appMenu addItemWithTitle:@"Quit Audio Priority Bar" action:@selector(terminate:) keyEquivalent:@"q"];
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

- (void)showSettings {
    [_settingsController showSettingsOnScreen:nil];
}

@end
