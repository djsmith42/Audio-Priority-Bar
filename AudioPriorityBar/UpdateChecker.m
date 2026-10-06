#import "UpdateChecker.h"
#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

/// Keys written by the GitHub API checker that Sparkle replaced.
static NSString *const LegacyAutomaticChecksEnabled = @"automaticUpdateChecksEnabled";
static NSString *const LegacyLastNotifiedVersion = @"lastNotifiedUpdateVersion";

@interface APBUpdateChecker () <SPUUpdaterDelegate>
@end

@implementation APBUpdateChecker {
    SPUStandardUpdaterController *_controller;
    NSUserDefaults *_defaults;
    BOOL (^_isIdle)(void);
    void (^_pendingInstall)(void);
    NSTimer *_idleTimer;
}

- (instancetype)init {
    return [self initWithIsIdle:nil];
}

- (instancetype)initWithIsIdle:(BOOL (^)(void))isIdle {
    return [self initWithDefaults:NSUserDefaults.standardUserDefaults bundle:NSBundle.mainBundle isIdle:isIdle];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          bundle:(NSBundle *)bundle
                          isIdle:(BOOL (^)(void))isIdle {
    if ((self = [super init])) {
        _defaults = defaults;
        _isIdle = isIdle ?: ^BOOL { return YES; };
        id feed = [bundle objectForInfoDictionaryKey:@"SUFeedURL"];
        _isAvailable = [feed isKindOfClass:NSString.class] && [feed length] > 0;
        _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO
                                                                    updaterDelegate:self
                                                                 userDriverDelegate:nil];
    }
    return self;
}

- (void)dealloc {
    [_idleTimer invalidate];
}

- (void)start {
    if (!_isAvailable) return;
    SPUUpdater *updater = _controller.updater;
    // Honor an opt-out made before Sparkle, then forget the old keys.
    id legacy = [_defaults objectForKey:LegacyAutomaticChecksEnabled];
    if ([legacy isKindOfClass:NSNumber.class] && ![legacy boolValue]) {
        updater.automaticallyChecksForUpdates = NO;
    }
    [_defaults removeObjectForKey:LegacyAutomaticChecksEnabled];
    [_defaults removeObjectForKey:LegacyLastNotifiedVersion];
    [_controller startUpdater];
    _automaticUpdatesEnabled = updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates;
    if (_onChange) _onChange();
}

- (void)setAutomaticUpdatesEnabled:(BOOL)enabled {
    if (!_isAvailable || enabled == _automaticUpdatesEnabled) return;
    _automaticUpdatesEnabled = enabled;
    _controller.updater.automaticallyChecksForUpdates = enabled;
    _controller.updater.automaticallyDownloadsUpdates = enabled;
    if (_onChange) _onChange();
}

- (void)checkForUpdates {
    if (!_isAvailable) return;
    // An accessory app is never frontmost on its own, so Sparkle's window
    // would open behind whatever the user is working in.
    [NSApp activateIgnoringOtherApps:YES];
    [_controller checkForUpdates:nil];
}

- (void)installWhenIdle:(void (^)(void))install {
    _pendingInstall = [install copy];
    [_idleTimer invalidate];
    // ponytail: polls once a minute rather than observing the model, so an
    // update can land up to a minute after a call ends.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf installPendingUpdateIfIdle];
    });
    _idleTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        APBUpdateChecker *checker = weakSelf;
        if (!checker || !checker->_pendingInstall) {
            [timer invalidate];
            return;
        }
        [checker installPendingUpdateIfIdle];
    }];
}

- (void)installPendingUpdateIfIdle {
    void (^install)(void) = _pendingInstall;
    if (!install || !_isIdle()) return;
    _pendingInstall = nil;
    [_idleTimer invalidate];
    _idleTimer = nil;
    install();
}

#pragma mark - SPUUpdaterDelegate

/// Sparkle would otherwise wait for a quit that a menu bar app rarely sees,
/// so a downloaded update is installed and relaunched once idle.
- (BOOL)updater:(SPUUpdater *)updater
    willInstallUpdateOnQuit:(SUAppcastItem *)item
    immediateInstallationBlock:(void (^)(void))immediateInstallHandler {
    [self installWhenIdle:immediateInstallHandler];
    return YES;
}

@end
