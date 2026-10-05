#import "APBServices.h"
#import <Sparkle/Sparkle.h>

NSString *const APBAppDisplayName = @"Audio Priority Bar";

#pragma mark - Launch at login

@implementation APBLaunchAtLoginController {
    SMAppServiceStatus (^_status)(void);
    APBLoginItemAction _register;
    APBLoginItemAction _unregister;
}

- (instancetype)init {
    return [self initWithStatus:^SMAppServiceStatus {
        return SMAppService.mainAppService.status;
    } register:^BOOL(NSError **error) {
        return [SMAppService.mainAppService registerAndReturnError:error];
    } unregister:^BOOL(NSError **error) {
        return [SMAppService.mainAppService unregisterAndReturnError:error];
    }];
}

- (instancetype)initWithStatus:(SMAppServiceStatus (^)(void))status
                      register:(APBLoginItemAction)registerAction
                    unregister:(APBLoginItemAction)unregisterAction {
    self = [super init];
    if (self) {
        _status = [status copy];
        _register = [registerAction copy];
        _unregister = [unregisterAction copy];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    SMAppServiceStatus current = _status();
    _isEnabled = current == SMAppServiceStatusEnabled || current == SMAppServiceStatusRequiresApproval;
    _requiresApproval = current == SMAppServiceStatusRequiresApproval;
    _errorMessage = nil;
}

- (void)setEnabled:(BOOL)enabled {
    NSError *error = nil;
    BOOL succeeded = enabled ? _register(&error) : _unregister(&error);
    if (!succeeded) {
        [self refresh];
        _errorMessage = error.localizedDescription ?: @"The operation couldn’t be completed.";
        return;
    }
    if (enabled) {
        [self refresh];
    } else {
        _isEnabled = NO;
        _requiresApproval = NO;
        _errorMessage = nil;
    }
}

@end

#pragma mark - Updates

/// Keys written by the GitHub API checker that Sparkle replaced.
static NSString *const LegacyAutomaticChecksEnabled = @"automaticUpdateChecksEnabled";
static NSString *const LegacyLastNotifiedVersion = @"lastNotifiedUpdateVersion";

@interface APBUpdateChecker () <SPUUpdaterDelegate>
@end

@implementation APBUpdateChecker {
    SPUStandardUpdaterController *_controller;
    NSUserDefaults *_defaults;
    BOOL (^_isIdle)(void);
    dispatch_block_t _pendingInstall;
    NSTimer *_idleTimer;
}

- (instancetype)initWithIsIdle:(BOOL (^)(void))isIdle {
    return [self initWithDefaults:NSUserDefaults.standardUserDefaults bundle:NSBundle.mainBundle isIdle:isIdle];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults bundle:(NSBundle *)bundle isIdle:(BOOL (^)(void))isIdle {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _isIdle = [isIdle copy];
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
}

- (void)setAutomaticUpdatesEnabled:(BOOL)enabled {
    if (!_isAvailable || enabled == _automaticUpdatesEnabled) return;
    _automaticUpdatesEnabled = enabled;
    _controller.updater.automaticallyChecksForUpdates = enabled;
    _controller.updater.automaticallyDownloadsUpdates = enabled;
}

- (void)checkForUpdates {
    if (!_isAvailable) return;
    // An accessory app is never frontmost on its own, so Sparkle's window would
    // open behind whatever the user is working in.
    [NSApp activateIgnoringOtherApps:YES];
    [_controller checkForUpdates:nil];
}

- (void)installWhenIdle:(dispatch_block_t)install {
    _pendingInstall = [install copy];
    [_idleTimer invalidate];
    // ponytail: polls once a minute rather than observing the model, so an
    // update can land up to a minute after a call ends.
    [self installPendingUpdateIfIdle];
    if (!_pendingInstall) return;
    __weak typeof(self) weakSelf = self;
    _idleTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
        typeof(self) self = weakSelf;
        if (!self || !self->_pendingInstall) {
            [timer invalidate];
            return;
        }
        [self installPendingUpdateIfIdle];
    }];
}

- (void)installPendingUpdateIfIdle {
    if (!_pendingInstall || !_isIdle()) return;
    dispatch_block_t install = _pendingInstall;
    _pendingInstall = nil;
    [_idleTimer invalidate];
    _idleTimer = nil;
    install();
}

/// Sparkle would otherwise wait for a quit that a menu bar app rarely sees, so
/// a downloaded update is installed and relaunched once idle.
- (BOOL)updater:(SPUUpdater *)updater
    willInstallUpdateOnQuit:(SUAppcastItem *)item
    immediateInstallationBlock:(void (^)(void))immediateInstallHandler {
    [self installWhenIdle:immediateInstallHandler];
    return YES;
}

@end

#pragma mark - System sound picker

@implementation APBSystemSoundPicker

+ (BOOL)isInUse {
    NSArray *windows = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    NSMutableSet *pids = [NSMutableSet set];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.controlcenter"]) {
        [pids addObject:@(app.processIdentifier)];
    }
    return [self isInUseWithWindows:windows ?: @[]
                  controlCenterPIDs:pids
                  frontmostBundleID:NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier];
}

+ (BOOL)isInUseWithWindows:(NSArray<NSDictionary<NSString *, id> *> *)windows
         controlCenterPIDs:(NSSet<NSNumber *> *)controlCenterPIDs
          frontmostBundleID:(NSString *)frontmostBundleID {
    if ([frontmostBundleID isEqualToString:@"com.apple.systempreferences"]) return YES;
    NSInteger menuBarLayer = CGWindowLevelForKey(kCGStatusWindowLevelKey);
    for (NSDictionary *window in windows) {
        NSNumber *pid = window[(__bridge NSString *)kCGWindowOwnerPID];
        NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
        if (![pid isKindOfClass:NSNumber.class] || ![controlCenterPIDs containsObject:@(pid.intValue)]) continue;
        if (![layer isKindOfClass:NSNumber.class] || layer.integerValue != menuBarLayer) return YES;
    }
    return NO;
}

@end
