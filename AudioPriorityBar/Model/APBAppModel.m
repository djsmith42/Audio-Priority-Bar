#import "APBAppModel.h"
#import <AppKit/AppKit.h>

NSNotificationName const APBAppModelDidChangeNotification = @"APBAppModelDidChange";

static NSTimeInterval Uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static NSNumber *RoleKey(APBDeviceRole role) {
    return @(role);
}

@implementation APBSkippedOutput

- (instancetype)initWithDevice:(APBAudioDevice *)device reason:(APBOutputSkipReason)reason {
    self = [super init];
    if (self) {
        _device = device;
        _reason = reason;
    }
    return self;
}

@end

@implementation APBAutomaticOutputDecision

- (instancetype)initWithTarget:(APBAudioDevice *)target skipped:(APBSkippedOutput *)skipped deferred:(BOOL)isDeferred {
    self = [super init];
    if (self) {
        _target = target;
        _skipped = skipped;
        _isDeferred = isDeferred;
    }
    return self;
}

@end

@interface APBAppModel ()
@property (nonatomic, readwrite, copy) NSArray<APBAudioDevice *> *inputDevices;
@property (nonatomic, readwrite, copy) NSArray<APBAudioDevice *> *speakerDevices;
@property (nonatomic, readwrite, copy) NSArray<APBAudioDevice *> *headphoneDevices;
@property (nonatomic, readwrite, copy) NSArray<APBAudioDevice *> *hiddenSpeakerDevices;
@property (nonatomic, readwrite, copy) NSArray<APBAudioDevice *> *hiddenHeadphoneDevices;
@property (nonatomic, readwrite) UInt32 currentInputID;
@property (nonatomic, readwrite) UInt32 currentOutputID;
@property (nonatomic, readwrite) float volume;
@property (nonatomic, readwrite) BOOL isVolumeControllable;
@property (nonatomic, readwrite) BOOL isOutputMutable;
@property (nonatomic, readwrite) float microphoneLevel;
@property (nonatomic, readwrite) BOOL isMicrophoneLevelControllable;
@property (nonatomic, readwrite) BOOL isMicrophoneMutable;
@property (nonatomic, readwrite) BOOL isManualMode;
@property (nonatomic, readwrite) BOOL selectsPairedDevice;
@property (nonatomic, readwrite) BOOL hideNewDisplayOutputs;
@property (nonatomic, readwrite) BOOL isActiveOutputMuted;
@property (nonatomic, readwrite) BOOL isActiveInputMuted;
@property (nonatomic, readwrite) BOOL micFlashState;
@property (nonatomic, readwrite) BOOL isMicrophoneMuted;
@property (nonatomic, readwrite) BOOL isInputRecording;
@property (nonatomic, readwrite) BOOL showsSwitchNotice;
@property (nonatomic, readwrite) BOOL remindsWhenMuted;
@property (nonatomic, readwrite) BOOL outlinesMenuBarIcon;
@property (nonatomic, readwrite) APBMenuBarDevices menuBarDevices;
@property (nonatomic, readwrite) BOOL showsMenuBarVolume;
@end

@implementation APBAppModel {
    APBLinkUsable _isUsable;
    APBLinkStateProvider _linkState;
    BOOL (^_reduceMotion)(void);
    BOOL (^_isUserPicking)(void);
    NSSet<NSString *> *_mutedRoles;
    /// The microphone currently carrying `isMicrophoneMuted`, by UID.
    NSString *_mutedInputUID;
    NSSet<NSString *> *_connectedInputUIDs;
    NSSet<NSString *> *_connectedOutputUIDs;
    NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSString *> *> *_connectedUIDsByID;
    NSMutableDictionary<NSNumber *, NSSet<NSString *> *> *_recentlyAddedUIDs;
    NSMutableDictionary<NSNumber *, NSNumber *> *_topologyChangedAt;
    NSTimer *_micFlashTimer;
    BOOL _isMuteVolumeRefreshPending;
    NSInteger _muteVolumeRefreshGeneration;
    BOOL _hasStarted;
    BOOL _isChangePending;
}

- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(id<APBAudioOperations>)audio
                     isUsable:(APBLinkUsable)isUsable
                    linkState:(APBLinkStateProvider)linkState
                      battery:(APBBluetoothBatteryMonitor *)battery
                 reduceMotion:(BOOL (^)(void))reduceMotion
                isUserPicking:(BOOL (^)(void))isUserPicking {
    self = [super init];
    if (self) {
        _store = store;
        _audio = audio;
        _isUsable = [isUsable copy];
        _linkState = [linkState copy];
        _battery = battery ?: [[APBBluetoothBatteryMonitor alloc] initWithRead:^(APBBatteryReadCompletion completion) {
            completion(nil);
        }];
        _reduceMotion = [reduceMotion copy];
        if (!_reduceMotion) {
            _reduceMotion = ^BOOL {
                return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
            };
        }
        _isUserPicking = [isUserPicking copy];
        if (!_isUserPicking) _isUserPicking = ^BOOL { return NO; };
        _inputDevices = @[];
        _speakerDevices = @[];
        _headphoneDevices = @[];
        _hiddenSpeakerDevices = @[];
        _hiddenHeadphoneDevices = @[];
        _isVolumeControllable = YES;
        _isOutputMutable = YES;
        _mutedRoles = [NSSet set];
        _connectedInputUIDs = [NSSet set];
        _connectedOutputUIDs = [NSSet set];
        _connectedUIDsByID = @{};
        _recentlyAddedUIDs = [NSMutableDictionary dictionary];
        _topologyChangedAt = [NSMutableDictionary dictionary];
        _keptPicks = [NSMutableDictionary dictionary];
        _switchedBackAt = [NSMutableDictionary dictionary];
        _takeoverUIDs = [NSMutableDictionary dictionary];
        _isManualMode = store.isManualMode;
        _selectsPairedDevice = store.selectsPairedDevice;
        _hideNewDisplayOutputs = store.hideNewDisplayOutputs;
        _showsSwitchNotice = store.showsSwitchNotice;
        _remindsWhenMuted = store.remindsWhenMuted;
        _outlinesMenuBarIcon = store.outlinesMenuBarIcon;
        _menuBarDevices = store.menuBarDevices;
        _showsMenuBarVolume = store.showsMenuBarVolume;
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(batteryDidChange:)
                                                   name:APBBluetoothBatteryDidChangeNotification
                                                 object:_battery];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_micFlashTimer invalidate];
}

- (void)batteryDidChange:(NSNotification *)notification {
    [self changed];
}

/// Coalesces every change made in one turn of the run loop into a single
/// notification, so views redraw once.
- (void)changed {
    if (_isChangePending) return;
    _isChangePending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        self->_isChangePending = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:APBAppModelDidChangeNotification object:self];
    });
}

#pragma mark Lifecycle

- (void)start {
    if (_hasStarted) return;
    [self refreshDevices];
    [self refreshVolume];
    [_battery refresh];
    if (!_isManualMode) {
        [self applyHighestPriorityDevices];
    } else {
        [self refreshMute];
    }
    _hasStarted = YES;
}

- (void)stop {
    _muteVolumeRefreshGeneration += 1;
    _isMuteVolumeRefreshPending = NO;
    [_micFlashTimer invalidate];
    _micFlashTimer = nil;
    self.micFlashState = NO;
    // The muted indicator leaves with the app, so the mute must too.
    for (NSString *uid in _store.appliedMicrophoneMutes.allKeys) [self restoreMicrophone:uid];
    _mutedInputUID = nil;
    self.isMicrophoneMuted = NO;
    _hasStarted = NO;
    [self changed];
}

#pragma mark Events

- (void)handleDevicesChanged {
    NSDictionary *before = self.currentUIDs;
    NSSet *oldInputs = _connectedInputUIDs;
    NSSet *oldOutputs = _connectedOutputUIDs;
    [self refreshDevices];
    if (![_connectedInputUIDs isEqualToSet:oldInputs] || ![_connectedOutputUIDs isEqualToSet:oldOutputs]) {
        [_battery refresh];
    }
    NSMutableSet *addedInputs = [_connectedInputUIDs mutableCopy];
    [addedInputs minusSet:oldInputs];
    NSMutableSet *addedOutputs = [_connectedOutputUIDs mutableCopy];
    [addedOutputs minusSet:oldOutputs];
    NSDictionary *additions = @{ RoleKey(APBDeviceRoleInput): addedInputs, RoleKey(APBDeviceRoleOutput): addedOutputs };
    for (NSNumber *role in additions) {
        NSSet *added = additions[role];
        if (added.count == 0) continue;
        _recentlyAddedUIDs[role] = added;
        _topologyChangedAt[role] = @(Uptime());
    }
    if (_isManualMode || !_hasStarted) {
        [self refreshMute];
        return;
    }
    [self applyHighestPriorityDevices];
    [self announceAutomaticSwitchesSince:before];
}

- (void)handleLinkChanged {
    // Every row reads its link state afresh on the next change notification,
    // so a new verdict redraws its badge right away.
    [self changed];
    [self handleDevicesChanged];
}

/// CoreAudio does not report whether a default changed because of the user or
/// topology; disappearing and newly-current devices identify topology.
- (BOOL)topologyExplainsChange:(APBDeviceRole)role
                  previousUIDs:(NSDictionary<NSNumber *, NSString *> *)previousUIDs
         previousConnectedUIDs:(NSDictionary<NSNumber *, NSSet<NSString *> *> *)previousConnectedUIDs {
    NSSet *connectedUIDs = role == APBDeviceRoleInput ? _connectedInputUIDs : _connectedOutputUIDs;
    NSString *currentUID = self.currentUIDs[RoleKey(role)];
    NSString *previousUID = previousUIDs[RoleKey(role)];
    if (previousUID && ![connectedUIDs containsObject:previousUID]) return YES;
    if (!currentUID) return NO;
    NSSet *previousConnected = previousConnectedUIDs[RoleKey(role)];
    if (previousConnected && ![previousConnected containsObject:currentUID]) return YES;
    return [_recentlyAddedUIDs[RoleKey(role)] containsObject:currentUID]
        && Uptime() - [_topologyChangedAt[RoleKey(role)] doubleValue] < 2;
}

- (void)handleDefaultChanged:(APBDeviceRole)role {
    NSDictionary<NSNumber *, NSString *> *before = self.currentUIDs;
    // Both roles, because the refresh below reads both defaults: macOS moves
    // the output and microphone to AirPods a few milliseconds apart, so by the
    // microphone's own event it no longer looks moved.
    NSDictionary<NSNumber *, NSString *> *previousUIDs = before;
    NSMutableDictionary<NSNumber *, APBAudioDevice *> *previousDevices = [NSMutableDictionary dictionary];
    previousDevices[RoleKey(APBDeviceRoleInput)] = self.currentInputDevice;
    previousDevices[RoleKey(APBDeviceRoleOutput)] = self.currentOutputDevice;
    NSDictionary *previousConnectedUIDs = @{
        RoleKey(APBDeviceRoleInput): _connectedInputUIDs,
        RoleKey(APBDeviceRoleOutput): _connectedOutputUIDs,
    };
    [self refreshDevices];
    [self refreshVolume];
    UInt32 currentID = role == APBDeviceRoleInput ? _currentInputID : _currentOutputID;
    NSString *currentUID = currentID ? _connectedUIDsByID[RoleKey(role)][@(currentID)] : nil;
    if (!_hasStarted) {
        [self refreshMute];
        return;
    }
    if (_isManualMode) {
        BOOL switchedBack = NO;
        for (NSNumber *movedRole in @[ @(role), @(APBDeviceRoleOther(role)) ]) {
            APBDeviceRole moved = movedRole.integerValue;
            NSSet *connectedUIDs = moved == APBDeviceRoleInput ? _connectedInputUIDs : _connectedOutputUIDs;
            APBAudioDevice *previousDevice = previousDevices[movedRole];
            NSString *movedUID = self.currentUIDs[movedRole];
            if ([self topologyExplainsChange:moved previousUIDs:previousUIDs previousConnectedUIDs:previousConnectedUIDs]
                || !previousDevice
                || !movedUID
                || [previousDevice.uid isEqualToString:movedUID]
                || ![connectedUIDs containsObject:previousDevice.uid]
                || _isUserPicking()
                || ![self shouldSwitchBack:moved fromUID:movedUID]) {
                continue;
            }
            // macOS or another app moved it, as when AirPods in the ears take
            // the output back, so the user's own pick wins.
            [self select:previousDevice automatically:NO includesPairedDevice:NO];
            switchedBack = YES;
        }
        if (switchedBack) {
            [self refreshMute];
            return;
        }
        if (role == APBDeviceRoleOutput) {
            APBAudioDevice *output = self.currentOutputDevice;
            if (![output.uid isEqualToString:_selectedOnlyOutputUID] && !(output == nil && _selectedOnlyOutputUID == nil)) {
                _selectedOnlyOutputUID = nil;
                if (output) [self selectPairedDeviceOf:output automatically:NO];
            }
        }
        [self refreshMute];
        return;
    }
    if ([self topologyExplainsChange:role previousUIDs:previousUIDs previousConnectedUIDs:previousConnectedUIDs]) {
        [self applyHighestPriorityDevices];
        [self announceAutomaticSwitchesSince:before];
        return;
    }
    APBAudioDevice *target = [self automaticTargetForRole:role];
    if (target && target.platformID != currentID && currentUID) {
        if (!_isUserPicking() && [self shouldSwitchBack:role fromUID:currentUID]) {
            // macOS or another app moved it, as when AirPods take the
            // microphone on ear detection, so the list wins.
            NSDictionary *moved = self.currentUIDs;
            [self applyHighestPriority:role];
            [self refreshMute];
            [self announceAutomaticSwitchesSince:moved];
            return;
        }
        _keptPicks[RoleKey(role)] = currentUID;
    }
    APBAudioDevice *output = self.currentOutputDevice;
    if (role == APBDeviceRoleOutput && output) {
        [self selectPairedDeviceOf:output automatically:!_isManualMode];
    }
    [self refreshMute];
}

/// Whether to switch `role` back from `uid`. AirPods Smart Routing ignores a
/// default set through CoreAudio and retries every few seconds, so once the
/// same role is taken again soon after a switch back, the app stops rather
/// than fight it.
- (BOOL)shouldSwitchBack:(APBDeviceRole)role fromUID:(NSString *)uid {
    if ([_takeoverUIDs[RoleKey(role)] isEqualToString:uid]) return NO;
    NSTimeInterval now = Uptime();
    // ponytail: a fixed 30 s window. A retry slower than that still loops, at
    // its own pace; counting retries per pick would close that.
    NSNumber *last = _switchedBackAt[RoleKey(role)];
    if (last && now - last.doubleValue < 30) {
        _takeoverUIDs[RoleKey(role)] = uid;
        [self changed];
        return NO;
    }
    _switchedBackAt[RoleKey(role)] = @(now);
    return YES;
}

- (APBAudioDevice *)takeoverDevice {
    APBAudioDevice *output = self.currentOutputDevice;
    if (output && [_takeoverUIDs[RoleKey(APBDeviceRoleOutput)] isEqualToString:output.uid]) return output;
    APBAudioDevice *input = self.currentInputDevice;
    if (input && [_takeoverUIDs[RoleKey(APBDeviceRoleInput)] isEqualToString:input.uid]) return input;
    return nil;
}

- (void)handleMuteOrVolumeChanged {
    if (_isMuteVolumeRefreshPending) return;
    _isMuteVolumeRefreshPending = YES;
    NSInteger generation = _muteVolumeRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || self->_muteVolumeRefreshGeneration != generation) return;
        self->_isMuteVolumeRefreshPending = NO;
        [self refreshMute];
        [self refreshVolume];
    });
}

#pragma mark Refresh

- (void)refreshDevices {
    NSArray<APBAudioDevice *> *connected = [_audio devices];
    NSMutableSet *inputUIDs = [NSMutableSet set];
    NSMutableSet *outputUIDs = [NSMutableSet set];
    NSMutableDictionary *inputIDs = [NSMutableDictionary dictionary];
    NSMutableDictionary *outputIDs = [NSMutableDictionary dictionary];
    NSMutableArray *inputs = [NSMutableArray array];
    NSMutableArray *outputs = [NSMutableArray array];
    for (APBAudioDevice *device in connected) {
        BOOL isInput = device.role == APBDeviceRoleInput;
        [isInput ? inputUIDs : outputUIDs addObject:device.uid];
        NSMutableDictionary *ids = isInput ? inputIDs : outputIDs;
        if (!ids[@(device.platformID)]) ids[@(device.platformID)] = device.uid;
        [isInput ? inputs : outputs addObject:device];
    }
    if (![inputUIDs isEqualToSet:_connectedInputUIDs] || ![outputUIDs isEqualToSet:_connectedOutputUIDs]) {
        [_keptPicks removeAllObjects];
        [_switchedBackAt removeAllObjects];
        [_takeoverUIDs removeAllObjects];
    }
    _connectedInputUIDs = inputUIDs;
    _connectedOutputUIDs = outputUIDs;
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    if (inputIDs.count) byID[RoleKey(APBDeviceRoleInput)] = inputIDs;
    if (outputIDs.count) byID[RoleKey(APBDeviceRoleOutput)] = outputIDs;
    _connectedUIDsByID = byID;
    [_store rememberDevices:connected];
    // Read before the lists are split, because splitting keeps whatever is
    // playing visible even when it is hidden.
    self.currentInputID = [_audio defaultDeviceForRole:APBDeviceRoleInput];
    self.currentOutputID = [_audio defaultDeviceForRole:APBDeviceRoleOutput];

    if (_showAll) {
        for (APBStoredDevice *stored in _store.knownDevices) {
            NSSet *connectedUIDs = stored.role == APBDeviceRoleInput ? _connectedInputUIDs : _connectedOutputUIDs;
            if ([connectedUIDs containsObject:stored.uid]) continue;
            [stored.role == APBDeviceRoleInput ? inputs : outputs addObject:stored.disconnectedDevice];
        }
    }
    // Hiding the active microphone would leave no way to see which one is in
    // use, so it stays listed and shows as hidden, matching outputs.
    NSMutableArray *visibleInputs = [NSMutableArray array];
    for (APBAudioDevice *device in inputs) {
        if (_showAll || ![_store isHidden:device]
            || (device.isConnected && device.platformID == _currentInputID)) {
            [visibleInputs addObject:device];
        }
    }
    self.inputDevices = [_store sorted:visibleInputs role:APBDeviceRoleInput];
    NSArray *hidden = nil;
    self.speakerDevices = [self split:outputs category:APBOutputCategorySpeaker hidden:&hidden];
    self.hiddenSpeakerDevices = hidden;
    self.headphoneDevices = [self split:outputs category:APBOutputCategoryHeadphone hidden:&hidden];
    self.hiddenHeadphoneDevices = hidden;
    [self changed];
}

/// Splits one output category into the list the panel shows and the list it
/// hides. `showAll` collapses the two by leaving the hidden list empty.
- (NSArray<APBAudioDevice *> *)split:(NSArray<APBAudioDevice *> *)outputs
                            category:(APBOutputCategory)category
                              hidden:(NSArray<APBAudioDevice *> **)hidden {
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *invisible = [NSMutableArray array];
    for (APBAudioDevice *device in outputs) {
        if ([_store categoryForDevice:device] != category) continue;
        // Hiding whatever is currently playing would leave no way to see where
        // the sound is going, so it stays listed and shows as hidden.
        BOOL isVisible = _showAll
            || ![_store isHidden:device inCategory:category]
            || (device.isConnected && device.platformID == _currentOutputID);
        [isVisible ? visible : invisible addObject:device];
    }
    *hidden = invisible;
    return [_store sorted:visible category:category];
}

- (void)refreshVolume {
    NSNumber *current = [_audio outputVolume];
    if (current) {
        _volume = current.floatValue;
        self.isVolumeControllable = YES;
    } else {
        _volume = 0;
        self.isVolumeControllable = NO;
    }
    self.isOutputMutable = _currentOutputID ? [_audio canSetMute:_currentOutputID role:APBDeviceRoleOutput] : NO;
    NSNumber *level = _currentInputID ? [_audio inputVolume:_currentInputID] : nil;
    if (level) {
        NSString *uid = _connectedUIDsByID[RoleKey(APBDeviceRoleInput)][@(_currentInputID)];
        NSNumber *saved = uid ? [_store appliedMicrophoneMuteForUID:uid] : nil;
        BOOL hasSavedLevel = saved && saved.doubleValue != APBPriorityStore.mutedByProperty;
        _microphoneLevel = hasSavedLevel ? saved.floatValue : level.floatValue;
        self.isMicrophoneLevelControllable = YES;
    } else {
        _microphoneLevel = 0;
        self.isMicrophoneLevelControllable = NO;
    }
    self.isMicrophoneMutable = _isMicrophoneLevelControllable
        || (_currentInputID && [_audio canSetMute:_currentInputID role:APBDeviceRoleInput]);
    [self changed];
}

- (void)refreshMute {
    [self reconcileMicrophoneMute];
    NSMutableSet *muted = [NSMutableSet set];
    NSArray *connected = [[_inputDevices arrayByAddingObjectsFromArray:_speakerDevices] arrayByAddingObjectsFromArray:_headphoneDevices];
    for (APBAudioDevice *device in connected) {
        if (device.isConnected && [self isHardwareMuted:device]) [muted addObject:device.identifier];
    }
    _mutedRoles = muted;
    self.isActiveOutputMuted = _currentOutputID ? [_audio isMuted:_currentOutputID role:APBDeviceRoleOutput] : NO;
    // The current microphone is always listed, even when hidden.
    APBAudioDevice *input = self.currentInputDevice;
    self.isActiveInputMuted = input ? [_mutedRoles containsObject:input.identifier] : NO;
    self.isInputRecording = _currentInputID ? [_audio isRunning:_currentInputID] : NO;
    [self updateMicFlash];
    [self changed];
}

/// Keeps the microphone mute on whichever microphone is current, and follows
/// mutes and unmutes made outside the app, like System Settings or a headset's
/// mute button.
- (void)reconcileMicrophoneMute {
    APBAudioDevice *current = self.currentInputDevice;
    if (current) {
        BOOL muted = [self isHardwareMuted:current];
        if ([current.uid isEqualToString:_mutedInputUID] && !muted) {
            self.isMicrophoneMuted = NO;
            _mutedInputUID = nil;
            [_store setAppliedMicrophoneMute:nil forUID:current.uid];
        } else if (!_mutedInputUID && muted && !_isMicrophoneMuted
                   && ![_store appliedMicrophoneMuteForUID:current.uid]) {
            self.isMicrophoneMuted = YES;
            _mutedInputUID = current.uid;
        }
    }
    if (_isMicrophoneMuted && current && ![current.uid isEqualToString:_mutedInputUID]) {
        if (_mutedInputUID) [self restoreMicrophone:_mutedInputUID];
        _mutedInputUID = [self applyMicrophoneMute:current] ? current.uid : nil;
        self.isMicrophoneMuted = _mutedInputUID != nil;
    } else if (!_isMicrophoneMuted && _mutedInputUID) {
        [self restoreMicrophone:_mutedInputUID];
        _mutedInputUID = nil;
    }
    // Anything else still recorded was muted before a crash, or while it was
    // unplugged, and must not come back silently dead.
    for (NSString *uid in _store.appliedMicrophoneMutes.allKeys) {
        if (![uid isEqualToString:_mutedInputUID]) [self restoreMicrophone:uid];
    }
}

/// Mutes through the device's mute property, or by zeroing its input volume
/// when it has none. Recorded before touching the hardware, so a crash in
/// between still leaves something to restore.
- (BOOL)applyMicrophoneMute:(APBAudioDevice *)device {
    UInt32 deviceID = device.platformID;
    [_store setAppliedMicrophoneMute:@(APBPriorityStore.mutedByProperty) forUID:device.uid];
    if ([_audio setMute:deviceID role:APBDeviceRoleInput muted:YES]) return YES;
    NSNumber *level = [_audio inputVolume:deviceID];
    if (level) {
        [_store setAppliedMicrophoneMute:@(level.doubleValue) forUID:device.uid];
        if ([_audio setInputVolume:deviceID value:0]) return YES;
    }
    [_store setAppliedMicrophoneMute:nil forUID:device.uid];
    return NO;
}

/// Undoes a mute the same way it was applied. A disconnected microphone stays
/// recorded and is restored once it reconnects.
- (void)restoreMicrophone:(NSString *)uid {
    NSNumber *level = [_store appliedMicrophoneMuteForUID:uid];
    NSNumber *deviceID = [_connectedUIDsByID[RoleKey(APBDeviceRoleInput)] allKeysForObject:uid].firstObject;
    if (!deviceID) {
        if (!level) [_store setAppliedMicrophoneMute:@(APBPriorityStore.mutedByProperty) forUID:uid];
        return;
    }
    if (level && level.doubleValue != APBPriorityStore.mutedByProperty) {
        [_audio setInputVolume:deviceID.unsignedIntValue value:level.floatValue];
    } else {
        [_audio setMute:deviceID.unsignedIntValue role:APBDeviceRoleInput muted:NO];
    }
    [_store setAppliedMicrophoneMute:nil forUID:uid];
}

/// A zeroed input only counts as muted when this app zeroed it: some virtual
/// microphones, like ZoomAudioDevice, rest at zero volume.
- (BOOL)isHardwareMuted:(APBAudioDevice *)device {
    if ([_audio isMuted:device.platformID role:device.role]) return YES;
    if (device.role != APBDeviceRoleInput) return NO;
    NSNumber *level = [_store appliedMicrophoneMuteForUID:device.uid];
    if (!level || level.doubleValue == APBPriorityStore.mutedByProperty) return NO;
    NSNumber *volume = [_audio inputVolume:device.platformID];
    return (volume ? volume.floatValue : 1) < 0.01;
}

#pragma mark Derived state

- (APBAudioDevice *)currentInputDevice {
    for (APBAudioDevice *device in _inputDevices) {
        if (device.isConnected && device.platformID == _currentInputID && _currentInputID != 0) return device;
    }
    return nil;
}

- (NSDictionary<NSNumber *, NSString *> *)currentUIDs {
    NSMutableDictionary *uids = [NSMutableDictionary dictionary];
    if (_currentInputID) uids[RoleKey(APBDeviceRoleInput)] = _connectedUIDsByID[RoleKey(APBDeviceRoleInput)][@(_currentInputID)];
    if (_currentOutputID) uids[RoleKey(APBDeviceRoleOutput)] = _connectedUIDsByID[RoleKey(APBDeviceRoleOutput)][@(_currentOutputID)];
    return uids;
}

/// Our own selection updates the current IDs immediately, so CoreAudio's echo
/// of it finds nothing new and cannot announce the same switch twice.
- (void)announceAutomaticSwitchesSince:(NSDictionary<NSNumber *, NSString *> *)before {
    if (!_hasStarted || _isManualMode || !_onAutomaticSwitch) return;
    NSDictionary *after = self.currentUIDs;
    NSMutableArray *switched = [NSMutableArray array];
    NSString *outputAfter = after[RoleKey(APBDeviceRoleOutput)];
    NSString *outputBefore = before[RoleKey(APBDeviceRoleOutput)];
    APBAudioDevice *output = self.currentOutputDevice;
    if (!(outputAfter == outputBefore || [outputAfter isEqualToString:outputBefore]) && output) {
        [switched addObject:output];
    }
    NSString *inputAfter = after[RoleKey(APBDeviceRoleInput)];
    NSString *inputBefore = before[RoleKey(APBDeviceRoleInput)];
    APBAudioDevice *input = self.currentInputDevice;
    if (!(inputAfter == inputBefore || [inputAfter isEqualToString:inputBefore]) && input) {
        [switched addObject:input];
    }
    if (switched.count > 0) _onAutomaticSwitch(switched);
}

- (BOOL)isMuted:(APBAudioDevice *)device {
    return [_mutedRoles containsObject:device.identifier];
}

- (APBBatteryLevels *)batteryLevelsForDevice:(APBAudioDevice *)device {
    return [_battery levelsForDevice:device];
}

- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device {
    return device.isConnected ? _linkState(device) : APBLinkStateNone;
}

- (BOOL)isLinkUsable:(APBAudioDevice *)device {
    return _isUsable(device);
}

- (NSArray<APBAudioDevice *> *)allOutputs {
    return [[[_speakerDevices arrayByAddingObjectsFromArray:_headphoneDevices]
        arrayByAddingObjectsFromArray:_hiddenSpeakerDevices] arrayByAddingObjectsFromArray:_hiddenHeadphoneDevices];
}

- (APBAudioDevice *)currentOutputDevice {
    if (!_currentOutputID) return nil;
    for (APBAudioDevice *device in self.allOutputs) {
        if (device.platformID == _currentOutputID) return device;
    }
    return nil;
}

- (APBOutputCategory)activeOutputCategory {
    APBAudioDevice *output = self.currentOutputDevice;
    return output ? [_store categoryForDevice:output] : APBOutputCategoryNone;
}

- (BOOL)isActiveOutputLinkDown {
    APBAudioDevice *output = self.currentOutputDevice;
    return output && [self linkStateForDevice:output] == APBLinkStateDown;
}

- (APBAutomaticOutputDecision *)automaticOutputDecision {
    if (_isManualMode) return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:nil deferred:NO];
    NSString *keptUID = _keptPicks[RoleKey(APBDeviceRoleOutput)];
    if (keptUID) {
        for (APBAudioDevice *device in self.allOutputs) {
            if ([device.uid isEqualToString:keptUID] && device.isConnected) {
                return [[APBAutomaticOutputDecision alloc] initWithTarget:device skipped:nil deferred:NO];
            }
        }
    }
    APBSkippedOutput *skipped = nil;
    for (APBAudioDevice *device in [_headphoneDevices arrayByAddingObjectsFromArray:_speakerDevices]) {
        APBOutputCategory category = [_store categoryForDevice:device];
        if (!device.isConnected || [_store isHidden:device inCategory:category]) continue;
        if ([_store isNeverUse:device]) {
            if (!skipped) skipped = [[APBSkippedOutput alloc] initWithDevice:device reason:APBOutputSkipReasonNeverAutoSelect];
            continue;
        }
        // Waiting a moment beats routing audio to this device and then
        // immediately moving away from it once the answer arrives.
        if ([self linkStateForDevice:device] == APBLinkStateChecking) {
            return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:skipped deferred:YES];
        }
        if (!_isUsable(device)) {
            if (!skipped) skipped = [[APBSkippedOutput alloc] initWithDevice:device reason:APBOutputSkipReasonOff];
            continue;
        }
        return [[APBAutomaticOutputDecision alloc] initWithTarget:device skipped:skipped deferred:NO];
    }
    return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:skipped deferred:NO];
}

#pragma mark Selection

- (void)applyHighestPriorityDevices {
    [self applyHighestPriority:APBDeviceRoleOutput];
    [self applyHighestPriority:APBDeviceRoleInput];
    [self refreshMute];
}

- (void)applyHighestPriorityInput {
    [self applyHighestPriority:APBDeviceRoleInput];
    [self refreshMute];
}

- (void)applyHighestPriorityOutput {
    [self applyHighestPriority:APBDeviceRoleOutput];
    [self refreshMute];
}

- (void)applyHighestPriority:(APBDeviceRole)role {
    // Deferral covers both roles: picking a microphone now could pair it with
    // an output we are about to change.
    if (self.automaticOutputDecision.isDeferred) return;
    APBAudioDevice *first = [self automaticTargetForRole:role];
    if (first) [self select:first automatically:YES includesPairedDevice:YES];
}

- (APBAudioDevice *)automaticTargetForRole:(APBDeviceRole)role {
    if (role == APBDeviceRoleInput) {
        NSString *keptUID = _keptPicks[RoleKey(APBDeviceRoleInput)];
        if (keptUID) {
            for (APBAudioDevice *device in _inputDevices) {
                if ([device.uid isEqualToString:keptUID] && device.isConnected) return device;
            }
        }
        APBAudioDevice *output = self.currentOutputDevice;
        if (output && [self.automaticOutputDecision.target.identifier isEqualToString:output.identifier]
            && _selectsPairedDevice) {
            APBAudioDevice *paired = [self pairedDeviceFor:output];
            if (paired && ![_store isNeverUse:paired] && _isUsable(paired)) return paired;
        }
        return [_store firstSelectableIn:_inputDevices isUsable:_isUsable];
    }
    return self.automaticOutputDecision.target;
}

- (BOOL)select:(APBAudioDevice *)device {
    return [self select:device automatically:NO includesPairedDevice:YES];
}

- (BOOL)select:(APBAudioDevice *)device automatically:(BOOL)automatically includesPairedDevice:(BOOL)includesPairedDevice {
    UInt32 currentID = device.role == APBDeviceRoleInput ? _currentInputID : _currentOutputID;
    if (currentID != device.platformID) {
        if (![_audio setDefaultDevice:device.platformID role:device.role]) return NO;
        if (device.role == APBDeviceRoleInput) {
            self.currentInputID = device.platformID;
        } else {
            self.currentOutputID = device.platformID;
        }
        [self changed];
    }
    if (includesPairedDevice) [self selectPairedDeviceOf:device automatically:automatically];
    return YES;
}

- (void)selectPairedDeviceOf:(APBAudioDevice *)device automatically:(BOOL)automatically {
    _selectedOnlyOutputUID = nil;
    if (!_selectsPairedDevice) return;
    APBAudioDevice *partner = [self pairedDeviceFor:device];
    if (!partner) return;
    if (device.role != APBDeviceRoleOutput && automatically) return;
    UInt32 partnerCurrentID = partner.role == APBDeviceRoleInput ? _currentInputID : _currentOutputID;
    if (partner.platformID == partnerCurrentID) return;
    if (automatically && ([_store isNeverUse:partner] || !_isUsable(partner))) return;
    [self select:partner];
}

- (APBAudioDevice *)pairedDeviceFor:(APBAudioDevice *)device {
    if (device.isVirtual) return nil;
    NSArray *candidates = device.role == APBDeviceRoleOutput
        ? _inputDevices
        : [_speakerDevices arrayByAddingObjectsFromArray:_headphoneDevices];
    NSString *key = device.pairingKey;
    for (APBAudioDevice *candidate in candidates) {
        if ([candidate.pairingKey isEqualToString:key] && candidate.isConnected && !candidate.isVirtual
            && ![_store isHidden:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (void)updateMicFlash {
    if (_isActiveInputMuted && _reduceMotion()) {
        [_micFlashTimer invalidate];
        _micFlashTimer = nil;
        self.micFlashState = YES;
    } else if (_isActiveInputMuted && !_micFlashTimer) {
        __weak typeof(self) weakSelf = self;
        _micFlashTimer = [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *timer) {
            typeof(self) self = weakSelf;
            if (!self) return;
            self.micFlashState = !self.micFlashState;
            [self changed];
        }];
    } else if (!_isActiveInputMuted) {
        [_micFlashTimer invalidate];
        _micFlashTimer = nil;
        self.micFlashState = NO;
    }
}

#pragma mark Actions

- (void)setManualMode:(BOOL)enabled {
    self.isManualMode = enabled;
    _store.isManualMode = enabled;
    [_keptPicks removeAllObjects];
    [_switchedBackAt removeAllObjects];
    [_takeoverUIDs removeAllObjects];
    [self changed];
    if (!enabled) [self applyHighestPriorityDevices];
}

- (void)setSelectsPairedDevice:(BOOL)enabled {
    _selectsPairedDevice = enabled;
    _store.selectsPairedDevice = enabled;
    [self changed];
    APBAudioDevice *output = self.currentOutputDevice;
    if (enabled && output) {
        [self selectPairedDeviceOf:output automatically:!_isManualMode];
    } else if (!_isManualMode) {
        [self applyHighestPriorityInput];
    }
}

- (void)setHideNewDisplayOutputs:(BOOL)enabled {
    _hideNewDisplayOutputs = enabled;
    _store.hideNewDisplayOutputs = enabled;
    [self changed];
}

- (void)setShowsSwitchNotice:(BOOL)enabled {
    _showsSwitchNotice = enabled;
    _store.showsSwitchNotice = enabled;
    [self changed];
}

- (void)setRemindsWhenMuted:(BOOL)enabled {
    _remindsWhenMuted = enabled;
    _store.remindsWhenMuted = enabled;
    [self changed];
}

- (void)setOutlinesMenuBarIcon:(BOOL)enabled {
    _outlinesMenuBarIcon = enabled;
    _store.outlinesMenuBarIcon = enabled;
    [self changed];
}

- (void)setMenuBarDevices:(APBMenuBarDevices)devices {
    _menuBarDevices = devices;
    _store.menuBarDevices = devices;
    [self changed];
}

- (void)setShowsMenuBarVolume:(BOOL)enabled {
    _showsMenuBarVolume = enabled;
    _store.showsMenuBarVolume = enabled;
    [self changed];
}

- (void)setShowAll:(BOOL)showAll {
    _showAll = showAll;
    [self changed];
}

- (void)setMicrophoneMuted:(BOOL)muted {
    self.isMicrophoneMuted = muted;
    [self refreshMute];
    [self refreshVolume];
}

- (void)performCommand:(APBURLCommand)command {
    switch (command) {
        case APBURLCommandToggleMicMute: [self setMicrophoneMuted:!_isMicrophoneMuted]; break;
        case APBURLCommandMuteMic: [self setMicrophoneMuted:YES]; break;
        case APBURLCommandUnmuteMic: [self setMicrophoneMuted:NO]; break;
        case APBURLCommandNone: break;
    }
}

- (void)setMicrophoneLevel:(float)value {
    if (!_currentInputID) return;
    if (_isMicrophoneMuted) [self setMicrophoneMuted:NO];
    if (![_audio setInputVolume:_currentInputID value:value]) return;
    _microphoneLevel = value;
    [self changed];
}

- (void)setOutputMuted:(BOOL)muted {
    if (!_currentOutputID || ![_audio setMute:_currentOutputID role:APBDeviceRoleOutput muted:muted]) return;
    [self refreshMute];
}

- (void)selectManually:(APBAudioDevice *)device {
    [self setManualMode:YES];
    [self select:device];
}

- (void)selectWithPairedDevice:(APBAudioDevice *)device {
    APBAudioDevice *pair = [self pairedDeviceFor:device];
    if (!pair) return;
    APBAudioDevice *output = device.role == APBDeviceRoleOutput ? device : pair;
    APBAudioDevice *input = device.role == APBDeviceRoleInput ? device : pair;
    [self setManualMode:YES];
    if (![self select:output]) return;
    [self select:input];
}

- (void)selectOnly:(APBAudioDevice *)device {
    [self setManualMode:YES];
    _selectedOnlyOutputUID = device.role == APBDeviceRoleOutput ? device.uid : nil;
    if (![self select:device automatically:NO includesPairedDevice:NO]) _selectedOnlyOutputUID = nil;
}

- (void)setVolume:(float)value {
    if (![_audio setOutputVolume:value]) return;
    _volume = value;
    [self changed];
    if (_isActiveOutputMuted && value > 0) [self setOutputMuted:NO];
}

- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device {
    [self preservingVisibilityMovingTo:category device:device];
    [self refreshDevices];
    if (!_isManualMode) [self applyHighestPriorityOutput];
}

/// Moves a device to a category without changing whether it is hidden: a
/// hidden device stays hidden in its new list, and a visible one stays visible
/// rather than inheriting a stale hide flag left over from before hiding
/// became a single, both-categories command.
- (void)preservingVisibilityMovingTo:(APBOutputCategory)category device:(APBAudioDevice *)device {
    BOOL wasHidden = [_store isHidden:device];
    [_store setCategory:category forDevice:device];
    if (wasHidden) {
        [_store hide:device inCategory:category];
    } else {
        [_store unhide:device fromCategory:category];
    }
}

- (void)hide:(APBAudioDevice *)device {
    if (device.role == APBDeviceRoleInput) {
        [_store hide:device];
    } else {
        [_store hide:device inCategory:APBOutputCategorySpeaker];
        [_store hide:device inCategory:APBOutputCategoryHeadphone];
    }
    [self refreshDevices];
    [self reselect:device.role];
}

- (void)unhide:(APBAudioDevice *)device {
    if (device.role == APBDeviceRoleInput) {
        [_store unhide:device];
    } else {
        [_store unhide:device fromCategory:APBOutputCategorySpeaker];
        [_store unhide:device fromCategory:APBOutputCategoryHeadphone];
    }
    [self refreshDevices];
}

- (BOOL)isHidden:(APBAudioDevice *)device {
    return [_store isHidden:device];
}

- (BOOL)isNeverUse:(APBAudioDevice *)device {
    return [_store isNeverUse:device];
}

- (void)setNeverUse:(APBAudioDevice *)device enabled:(BOOL)enabled {
    [_store setNeverUse:device value:enabled];
    [self refreshDevices];
    [self reselect:device.role];
}

- (void)forget:(APBAudioDevice *)device {
    [_store forgetUID:device.uid role:device.role];
    [self refreshDevices];
}

/// Moves one element the way `move(fromOffsets:toOffset:)` does: the
/// destination is a gap in the list before the move.
static NSArray *Moved(NSArray *list, NSInteger source, NSInteger destination) {
    NSMutableArray *result = [list mutableCopy];
    id item = result[(NSUInteger)source];
    [result removeObjectAtIndex:(NSUInteger)source];
    [result insertObject:item atIndex:(NSUInteger)(destination > source ? destination - 1 : destination)];
    return result;
}

- (void)moveInputFrom:(NSInteger)source to:(NSInteger)destination {
    NSInteger count = (NSInteger)_inputDevices.count;
    if (source < 0 || source >= count || destination < 0 || destination > count) return;
    self.inputDevices = Moved(_inputDevices, source, destination);
    [_store savePriorities:_inputDevices role:APBDeviceRoleInput];
    [self changed];
    if (!_isManualMode) [self applyHighestPriorityInput];
}

- (void)moveOutputInCategory:(APBOutputCategory)category from:(NSInteger)source to:(NSInteger)destination {
    BOOL isSpeaker = category == APBOutputCategorySpeaker;
    NSArray *devices = isSpeaker ? _speakerDevices : _headphoneDevices;
    NSInteger count = (NSInteger)devices.count;
    if (source < 0 || source >= count || destination < 0 || destination > count) return;
    NSArray *moved = Moved(devices, source, destination);
    if (isSpeaker) {
        self.speakerDevices = moved;
    } else {
        self.headphoneDevices = moved;
    }
    [_store savePriorities:moved category:isSpeaker ? APBOutputCategorySpeaker : APBOutputCategoryHeadphone];
    [self changed];
    if (!_isManualMode) [self applyHighestPriorityOutput];
}

static NSInteger IndexOfIdentifier(NSArray<APBAudioDevice *> *devices, NSString *identifier) {
    for (NSUInteger index = 0; index < devices.count; index++) {
        if ([devices[index].identifier isEqualToString:identifier]) return (NSInteger)index;
    }
    return NSNotFound;
}

- (BOOL)dropDevice:(NSString *)identifier intoCategory:(APBOutputCategory)category at:(NSInteger)destination {
    if (category == APBOutputCategoryNone) {
        NSInteger source = IndexOfIdentifier(_inputDevices, identifier);
        if (source == NSNotFound) return NO;
        [self moveInputFrom:source to:MAX(0, MIN(destination, (NSInteger)_inputDevices.count))];
        return YES;
    }

    NSArray *outputs = [_speakerDevices arrayByAddingObjectsFromArray:_headphoneDevices];
    NSInteger found = IndexOfIdentifier(outputs, identifier);
    if (found == NSNotFound) return NO;
    APBAudioDevice *device = outputs[(NSUInteger)found];
    if ([_store categoryForDevice:device] == category) {
        NSArray *devices = category == APBOutputCategorySpeaker ? _speakerDevices : _headphoneDevices;
        NSInteger source = (NSInteger)[devices indexOfObject:device];
        if (source == NSNotFound) return NO;
        [self moveOutputInCategory:category from:source to:MAX(0, MIN(destination, (NSInteger)devices.count))];
        return YES;
    }

    [self preservingVisibilityMovingTo:category device:device];
    [self refreshDevices];
    NSMutableArray *devices = [(category == APBOutputCategorySpeaker ? _speakerDevices : _headphoneDevices) mutableCopy];
    NSInteger source = IndexOfIdentifier(devices, identifier);
    if (source == NSNotFound) return NO;
    APBAudioDevice *moved = devices[(NSUInteger)source];
    [devices removeObjectAtIndex:(NSUInteger)source];
    [devices insertObject:moved atIndex:(NSUInteger)MAX(0, MIN(destination, (NSInteger)devices.count))];
    if (category == APBOutputCategorySpeaker) {
        self.speakerDevices = devices;
    } else {
        self.headphoneDevices = devices;
    }
    [_store savePriorities:devices category:category];
    [self changed];
    if (!_isManualMode) [self applyHighestPriorityOutput];
    return YES;
}

- (void)reselect:(APBDeviceRole)role {
    if (_isManualMode) return;
    if (role == APBDeviceRoleInput) {
        [self applyHighestPriorityInput];
    } else {
        [self applyHighestPriorityOutput];
    }
}

@end
