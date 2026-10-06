#import "AppModel.h"
#import "AppModel+Private.h"
#import <AppKit/AppKit.h>

NSNotificationName const APBAppModelDidChangeNotification = @"APBAppModelDidChangeNotification";

/// Whether an optional platform ID names `deviceID`.
BOOL APBIDIs(NSNumber *optionalID, UInt32 deviceID) {
    return optionalID != nil && optionalID.unsignedIntValue == deviceID;
}

static NSNumber *RoleKey(APBDeviceRole role) {
    return @(role);
}

static APBDeviceRole OtherRole(APBDeviceRole role) {
    return role == APBDeviceRoleInput ? APBDeviceRoleOutput : APBDeviceRoleInput;
}

@implementation APBAudioOperations
@end

@implementation APBLinkOperations

- (instancetype)init {
    if ((self = [super init])) {
        _isUsable = ^BOOL(APBAudioDevice *device) { return YES; };
        _state = ^APBLinkState(APBAudioDevice *device) { return APBLinkStateNone; };
        _battery = ^NSNumber *(APBAudioDevice *device) { return nil; };
    }
    return self;
}

- (instancetype)initWithIsUsable:(BOOL (^)(APBAudioDevice *))isUsable
                           state:(APBLinkState (^)(APBAudioDevice *))state {
    if ((self = [self init])) {
        _isUsable = [isUsable copy];
        _state = [state copy];
    }
    return self;
}

@end

@implementation APBSkippedOutput

- (instancetype)initWithDevice:(APBAudioDevice *)device reason:(APBOutputSkipReason)reason {
    if ((self = [super init])) {
        _device = device;
        _reason = reason;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBSkippedOutput.class]) return NO;
    APBSkippedOutput *other = object;
    return [_device isEqual:other.device] && _reason == other.reason;
}

- (NSUInteger)hash {
    return _device.hash ^ (NSUInteger)_reason;
}

@end

@implementation APBAutomaticOutputDecision

- (instancetype)initWithTarget:(APBAudioDevice *)target
                       skipped:(APBSkippedOutput *)skipped
                    isDeferred:(BOOL)isDeferred {
    if ((self = [super init])) {
        _target = target;
        _skipped = skipped;
        _isDeferred = isDeferred;
    }
    return self;
}

@end

@implementation APBAppModel {
    BOOL (^_reduceMotion)(void);
    BOOL (^_isUserPicking)(void);
    NSSet<NSString *> *_mutedRoles;
    /// The microphone currently carrying `isMicrophoneMuted`, by UID.
    NSString *_mutedInputUID;
    /// The headphones last seen as the current output, by UID.
    NSString *_playingHeadphonesUID;
    NSSet<NSString *> *_connectedInputUIDs;
    NSSet<NSString *> *_connectedOutputUIDs;
    /// Platform ID to UID, by role.
    NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSString *> *> *_connectedUIDsByID;
    NSMutableDictionary<NSNumber *, NSSet<NSString *> *> *_recentlyAddedUIDs;
    NSMutableDictionary<NSNumber *, NSNumber *> *_topologyChangedAt;
    NSTimer *_micFlashTimer;
    /// Bumped to cancel a scheduled mute and volume refresh.
    NSUInteger _muteVolumeRefreshGeneration;
    BOOL _isMuteVolumeRefreshPending;
    BOOL _hasStarted;
    BOOL _isChangePending;
}

- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(APBAudioOperations *)audio
                         link:(APBLinkOperations *)link {
    return [self initWithStore:store audio:audio link:link battery:nil reduceMotion:nil isUserPicking:nil];
}

- (instancetype)initWithStore:(APBPriorityStore *)store
                        audio:(APBAudioOperations *)audio
                         link:(APBLinkOperations *)link
                      battery:(APBBluetoothBatteryMonitor *)battery
                 reduceMotion:(BOOL (^)(void))reduceMotion
                isUserPicking:(BOOL (^)(void))isUserPicking {
    if ((self = [super init])) {
        _store = store;
        _audio = audio;
        _link = link;
        _battery = battery ?: [[APBBluetoothBatteryMonitor alloc] initWithRead:^(void (^completion)(NSData *)) {
            completion(nil);
        }];
        _reduceMotion = reduceMotion ?: ^BOOL {
            return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        };
        _isUserPicking = isUserPicking ?: ^BOOL { return NO; };
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
        _mutesSpeakersWhenHeadphonesDisconnect = store.mutesSpeakersWhenHeadphonesDisconnect;
        _outlinesMenuBarIcon = store.outlinesMenuBarIcon;
        _menuBarDevices = store.menuBarDevices;
        _showsMenuBarVolume = store.showsMenuBarVolume;
        __weak typeof(self) weakSelf = self;
        _battery.onChange = ^{ [weakSelf didChange]; };
    }
    return self;
}

- (void)dealloc {
    [_micFlashTimer invalidate];
}

- (void)didChange {
    if (_isChangePending) return;
    _isChangePending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        APBAppModel *model = weakSelf;
        if (!model) return;
        model->_isChangePending = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:APBAppModelDidChangeNotification object:model];
    });
}

- (void)setShowAll:(BOOL)showAll {
    _showAll = showAll;
    [self didChange];
}

#pragma mark - Lifecycle

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
    _micFlashState = NO;
    // The muted indicator leaves with the app, so the mute must too.
    for (NSString *uid in _store.appliedMicrophoneMutes.allKeys) {
        [self restoreMicrophone:uid];
    }
    _mutedInputUID = nil;
    _isMicrophoneMuted = NO;
    _hasStarted = NO;
    [self didChange];
}

#pragma mark - Events

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
    NSDictionary<NSNumber *, NSSet *> *additions = @{
        RoleKey(APBDeviceRoleInput): addedInputs,
        RoleKey(APBDeviceRoleOutput): addedOutputs,
    };
    for (NSNumber *role in additions) {
        if (additions[role].count == 0) continue;
        _recentlyAddedUIDs[role] = additions[role];
        _topologyChangedAt[role] = @(NSProcessInfo.processInfo.systemUptime);
    }
    if (_isManualMode || !_hasStarted) {
        [self refreshMute];
        return;
    }
    [self applyHighestPriorityDevices];
    [self announceAutomaticSwitchesSince:before];
}

- (void)handleLinkChanged {
    [self handleDevicesChanged];
    [self didChange];
}

- (NSSet<NSString *> *)connectedUIDsForRole:(APBDeviceRole)role {
    return role == APBDeviceRoleInput ? _connectedInputUIDs : _connectedOutputUIDs;
}

- (NSNumber *)currentIDForRole:(APBDeviceRole)role {
    return role == APBDeviceRoleInput ? _currentInputID : _currentOutputID;
}

- (void)handleDefaultChanged:(APBDeviceRole)role {
    NSDictionary<NSNumber *, NSString *> *before = self.currentUIDs;
    // Both roles, because the refresh below reads both defaults: macOS moves
    // the output and microphone to AirPods a few milliseconds apart, so by
    // the microphone's own event it no longer looks moved.
    NSDictionary<NSNumber *, NSString *> *previousUIDs = before;
    NSMutableDictionary<NSNumber *, APBAudioDevice *> *previousDevices = [NSMutableDictionary dictionary];
    previousDevices[RoleKey(APBDeviceRoleInput)] = self.currentInputDevice;
    previousDevices[RoleKey(APBDeviceRoleOutput)] = self.currentOutputDevice;
    NSDictionary<NSNumber *, NSSet<NSString *> *> *previousConnectedUIDs = @{
        RoleKey(APBDeviceRoleInput): _connectedInputUIDs,
        RoleKey(APBDeviceRoleOutput): _connectedOutputUIDs,
    };
    [self refreshDevices];
    [self refreshVolume];
    NSNumber *currentID = [self currentIDForRole:role];
    NSString *currentUID = currentID ? _connectedUIDsByID[RoleKey(role)][currentID] : nil;
    if (!_hasStarted) {
        [self refreshMute];
        return;
    }
    // CoreAudio does not report whether a default changed because of the
    // user or topology; disappearing and newly-current devices identify
    // topology.
    BOOL (^topologyExplainsChange)(APBDeviceRole) = ^BOOL(APBDeviceRole changed) {
        NSSet<NSString *> *connectedUIDs = [self connectedUIDsForRole:changed];
        NSString *previous = previousUIDs[RoleKey(changed)];
        NSString *current = self.currentUIDs[RoleKey(changed)];
        if (previous && ![connectedUIDs containsObject:previous]) return YES;
        if (current && ![previousConnectedUIDs[RoleKey(changed)] containsObject:current]) return YES;
        if (current && [self->_recentlyAddedUIDs[RoleKey(changed)] containsObject:current]
            && NSProcessInfo.processInfo.systemUptime
                - self->_topologyChangedAt[RoleKey(changed)].doubleValue < 2) {
            return YES;
        }
        return NO;
    };
    if (_isManualMode) {
        BOOL switchedBack = NO;
        for (NSNumber *moved in @[RoleKey(role), RoleKey(OtherRole(role))]) {
            APBDeviceRole movedRole = moved.integerValue;
            NSSet<NSString *> *connectedUIDs = [self connectedUIDsForRole:movedRole];
            if (topologyExplainsChange(movedRole)) continue;
            APBAudioDevice *previousDevice = previousDevices[moved];
            NSString *movedUID = self.currentUIDs[moved];
            if (!previousDevice || !movedUID
                || [previousDevice.uid isEqualToString:movedUID]
                || ![connectedUIDs containsObject:previousDevice.uid]
                || _isUserPicking()
                || ![self shouldSwitchBack:movedRole from:movedUID]) {
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
            if (![output.uid isEqualToString:_selectedOnlyOutputUID]
                && !(output == nil && _selectedOnlyOutputUID == nil)) {
                _selectedOnlyOutputUID = nil;
                if (output) [self selectPairedDeviceOf:output automatically:NO];
            }
        }
        [self refreshMute];
        return;
    }
    if (topologyExplainsChange(role)) {
        [self applyHighestPriorityDevices];
        [self announceAutomaticSwitchesSince:before];
        return;
    }
    APBAudioDevice *target = [self automaticTargetFor:role];
    if (target && !APBIDIs(currentID, target.platformID) && currentUID) {
        if (!(_isUserPicking() || ![self shouldSwitchBack:role from:currentUID])) {
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
    if (role == APBDeviceRoleOutput) {
        APBAudioDevice *output = self.currentOutputDevice;
        if (output) [self selectPairedDeviceOf:output automatically:!_isManualMode];
    }
    [self refreshMute];
}

/// Whether to switch `role` back from `uid`. AirPods Smart Routing ignores a
/// default set through CoreAudio and retries every few seconds, so once the
/// same role is taken again soon after a switch back, the app stops rather
/// than fight it.
- (BOOL)shouldSwitchBack:(APBDeviceRole)role from:(NSString *)uid {
    if ([_takeoverUIDs[RoleKey(role)] isEqualToString:uid]) return NO;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    // ponytail: a fixed 30 s window. A retry slower than that still loops,
    // at its own pace; counting retries per pick would close that.
    NSNumber *last = _switchedBackAt[RoleKey(role)];
    if (last && now - last.doubleValue < 30) {
        _takeoverUIDs[RoleKey(role)] = uid;
        return NO;
    }
    _switchedBackAt[RoleKey(role)] = @(now);
    return YES;
}

- (APBAudioDevice *)takeoverDevice {
    APBAudioDevice *output = self.currentOutputDevice;
    if (output && [_takeoverUIDs[RoleKey(APBDeviceRoleOutput)] isEqualToString:output.uid]) {
        return output;
    }
    APBAudioDevice *input = self.currentInputDevice;
    if (input && [_takeoverUIDs[RoleKey(APBDeviceRoleInput)] isEqualToString:input.uid]) {
        return input;
    }
    return nil;
}

- (void)handleMuteOrVolumeChanged {
    if (_isMuteVolumeRefreshPending) return;
    _isMuteVolumeRefreshPending = YES;
    NSUInteger generation = _muteVolumeRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        APBAppModel *model = weakSelf;
        if (!model || model->_muteVolumeRefreshGeneration != generation) return;
        model->_isMuteVolumeRefreshPending = NO;
        [model refreshMute];
        [model refreshVolume];
    });
}

- (void)handleBatteryChanged {
    [self didChange];
}

#pragma mark - Refresh

- (void)refreshDevices {
    NSArray<APBAudioDevice *> *connected = _audio.devices();
    NSMutableSet *inputUIDs = [NSMutableSet set], *outputUIDs = [NSMutableSet set];
    NSMutableDictionary *inputIDs = [NSMutableDictionary dictionary];
    NSMutableDictionary *outputIDs = [NSMutableDictionary dictionary];
    for (APBAudioDevice *device in connected) {
        BOOL isInput = device.role == APBDeviceRoleInput;
        [(isInput ? inputUIDs : outputUIDs) addObject:device.uid];
        NSMutableDictionary *ids = isInput ? inputIDs : outputIDs;
        // The first device with an ID wins, as it did in Swift.
        if (!ids[@(device.platformID)]) ids[@(device.platformID)] = device.uid;
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
    [_store remember:connected];
    // Read before the lists are split, because splitting keeps whatever is
    // playing visible even when it is hidden.
    _currentInputID = _audio.defaultDevice(APBDeviceRoleInput);
    _currentOutputID = _audio.defaultDevice(APBDeviceRoleOutput);

    NSMutableArray<APBAudioDevice *> *inputs = [NSMutableArray array];
    NSMutableArray<APBAudioDevice *> *outputs = [NSMutableArray array];
    for (APBAudioDevice *device in connected) {
        [(device.role == APBDeviceRoleInput ? inputs : outputs) addObject:device];
    }
    if (_showAll) {
        for (APBStoredDevice *stored in _store.knownDevices) {
            if ([[self connectedUIDsForRole:stored.role] containsObject:stored.uid]) continue;
            [(stored.role == APBDeviceRoleInput ? inputs : outputs) addObject:stored.disconnectedDevice];
        }
    }
    // Hiding the active microphone would leave no way to see which one is in
    // use, so it stays listed and shows as hidden, matching outputs.
    NSMutableArray<APBAudioDevice *> *visibleInputs = [NSMutableArray array];
    for (APBAudioDevice *device in inputs) {
        if (_showAll || ![_store isHidden:device]
            || (device.isConnected && APBIDIs(_currentInputID, device.platformID))) {
            [visibleInputs addObject:device];
        }
    }
    _inputDevices = [_store sorted:visibleInputs role:APBDeviceRoleInput];
    NSArray *hidden = nil;
    _speakerDevices = [self split:outputs category:APBOutputCategorySpeaker hidden:&hidden];
    _hiddenSpeakerDevices = hidden;
    _headphoneDevices = [self split:outputs category:APBOutputCategoryHeadphone hidden:&hidden];
    _hiddenHeadphoneDevices = hidden;
    [self didChange];
}

/// Splits one output category into the list the panel shows, returned, and
/// the list it hides. `showAll` collapses the two by leaving the hidden list
/// empty.
- (NSArray<APBAudioDevice *> *)split:(NSArray<APBAudioDevice *> *)outputs
                            category:(APBOutputCategory)category
                              hidden:(NSArray<APBAudioDevice *> **)hidden {
    NSMutableArray *visible = [NSMutableArray array], *hiddenMembers = [NSMutableArray array];
    for (APBAudioDevice *device in outputs) {
        if ([_store categoryForDevice:device] != category) continue;
        // Hiding whatever is currently playing would leave no way to see
        // where the sound is going, so it stays listed and shows as hidden.
        BOOL isVisible = _showAll
            || ![_store isHidden:device inCategory:category]
            || (device.isConnected && APBIDIs(_currentOutputID, device.platformID));
        [(isVisible ? visible : hiddenMembers) addObject:device];
    }
    *hidden = hiddenMembers;
    return [_store sorted:visible category:category];
}

- (void)refreshVolume {
    NSNumber *current = _audio.outputVolume();
    if (current) {
        _volume = current.floatValue;
        _isVolumeControllable = YES;
    } else {
        _volume = 0;
        _isVolumeControllable = NO;
    }
    _isOutputMutable = _currentOutputID
        ? _audio.canSetMute(APBDeviceRoleOutput, _currentOutputID.unsignedIntValue)
        : NO;
    NSNumber *level = _currentInputID ? _audio.inputVolume(_currentInputID.unsignedIntValue) : nil;
    if (level) {
        NSString *uid = _connectedUIDsByID[RoleKey(APBDeviceRoleInput)][_currentInputID];
        NSNumber *saved = uid ? _store.appliedMicrophoneMutes[uid] : nil;
        if (saved.doubleValue == APBPriorityStore.mutedByProperty) saved = nil;
        _microphoneLevel = saved ? saved.floatValue : level.floatValue;
        _isMicrophoneLevelControllable = YES;
    } else {
        _microphoneLevel = 0;
        _isMicrophoneLevelControllable = NO;
    }
    _isMicrophoneMutable = _isMicrophoneLevelControllable
        || (_currentInputID && _audio.canSetMute(APBDeviceRoleInput, _currentInputID.unsignedIntValue));
    [self didChange];
}

- (void)refreshMute {
    [self muteSpeakersIfHeadphonesLeft];
    [self reconcileMicrophoneMute];
    NSMutableSet *muted = [NSMutableSet set];
    NSArray *listed = [[_inputDevices arrayByAddingObjectsFromArray:_speakerDevices]
                       arrayByAddingObjectsFromArray:_headphoneDevices];
    for (APBAudioDevice *device in listed) {
        if (device.isConnected && [self isHardwareMuted:device]) [muted addObject:device.roleIdentifier];
    }
    _mutedRoles = muted;
    _isActiveOutputMuted = _currentOutputID
        ? _audio.isMuted(APBDeviceRoleOutput, _currentOutputID.unsignedIntValue)
        : NO;
    // The current microphone is always listed, even when hidden.
    APBAudioDevice *input = self.currentInputDevice;
    _isActiveInputMuted = input ? [_mutedRoles containsObject:input.roleIdentifier] : NO;
    _isInputRecording = _currentInputID ? _audio.isRunning(_currentInputID.unsignedIntValue) : NO;
    [self updateMicFlash];
    [self didChange];
}

/// Headphones that run out of battery or drop out leave the sound on the
/// speakers, so the speaker that takes over starts muted. A Jabra headset
/// behind a Link dongle never leaves the device list, it only stops being
/// usable. The tracked headphones survive a moment with no known output,
/// since the device list and the default can change in either order.
- (void)muteSpeakersIfHeadphonesLeft {
    APBAudioDevice *output = self.currentOutputDevice;
    if (!output) return;
    APBOutputCategory category = [_store categoryForDevice:output];
    if (_mutesSpeakersWhenHeadphonesDisconnect && _playingHeadphonesUID
        && category == APBOutputCategorySpeaker) {
        APBAudioDevice *headphones = nil;
        for (APBAudioDevice *device in self.allOutputs) {
            if ([device.uid isEqualToString:_playingHeadphonesUID] && device.isConnected) {
                headphones = device;
                break;
            }
        }
        if (!(headphones && _link.isUsable(headphones))) {
            _audio.setMute(APBDeviceRoleOutput, output.platformID, YES);
        }
    }
    _playingHeadphonesUID = category == APBOutputCategoryHeadphone ? output.uid : nil;
}

/// Keeps the microphone mute on whichever microphone is current, and follows
/// mutes and unmutes made outside the app, like System Settings or a
/// headset's mute button.
- (void)reconcileMicrophoneMute {
    APBAudioDevice *current = self.currentInputDevice;
    if (current) {
        BOOL muted = [self isHardwareMuted:current];
        if ([current.uid isEqualToString:_mutedInputUID] && !muted) {
            _isMicrophoneMuted = NO;
            _mutedInputUID = nil;
            [_store setAppliedMicrophoneMute:nil forUID:current.uid];
        } else if (!_mutedInputUID && muted && !_isMicrophoneMuted
                   && _store.appliedMicrophoneMutes[current.uid] == nil) {
            _isMicrophoneMuted = YES;
            _mutedInputUID = current.uid;
        }
    }
    if (_isMicrophoneMuted && current && ![current.uid isEqualToString:_mutedInputUID]) {
        if (_mutedInputUID) [self restoreMicrophone:_mutedInputUID];
        _mutedInputUID = [self applyMicrophoneMute:current] ? current.uid : nil;
        _isMicrophoneMuted = _mutedInputUID != nil;
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
    if (_audio.setMute(APBDeviceRoleInput, deviceID, YES)) return YES;
    NSNumber *level = _audio.inputVolume(deviceID);
    if (level) {
        [_store setAppliedMicrophoneMute:@(level.doubleValue) forUID:device.uid];
        if (_audio.setInputVolume(deviceID, 0)) return YES;
    }
    [_store setAppliedMicrophoneMute:nil forUID:device.uid];
    return NO;
}

/// Undoes a mute the same way it was applied. A disconnected microphone
/// stays recorded and is restored once it reconnects.
- (void)restoreMicrophone:(NSString *)uid {
    NSNumber *level = _store.appliedMicrophoneMutes[uid];
    NSDictionary<NSNumber *, NSString *> *inputs = _connectedUIDsByID[RoleKey(APBDeviceRoleInput)];
    NSNumber *deviceID = [inputs allKeysForObject:uid].firstObject;
    if (!deviceID) {
        if (!level) {
            [_store setAppliedMicrophoneMute:@(APBPriorityStore.mutedByProperty) forUID:uid];
        }
        return;
    }
    if (level && level.doubleValue != APBPriorityStore.mutedByProperty) {
        _audio.setInputVolume(deviceID.unsignedIntValue, level.floatValue);
    } else {
        _audio.setMute(APBDeviceRoleInput, deviceID.unsignedIntValue, NO);
    }
    [_store setAppliedMicrophoneMute:nil forUID:uid];
}

/// A zeroed input only counts as muted when this app zeroed it: some virtual
/// microphones, like ZoomAudioDevice, rest at zero volume.
- (BOOL)isHardwareMuted:(APBAudioDevice *)device {
    if (_audio.isMuted(device.role, device.platformID)) return YES;
    if (device.role != APBDeviceRoleInput) return NO;
    NSNumber *level = _store.appliedMicrophoneMutes[device.uid];
    if (!level || level.doubleValue == APBPriorityStore.mutedByProperty) return NO;
    NSNumber *current = _audio.inputVolume(device.platformID);
    return (current ? current.floatValue : 1) < 0.01;
}

#pragma mark - Derived state

- (APBAudioDevice *)currentInputDevice {
    for (APBAudioDevice *device in _inputDevices) {
        if (device.isConnected && APBIDIs(_currentInputID, device.platformID)) return device;
    }
    return nil;
}

- (NSDictionary<NSNumber *, NSString *> *)currentUIDs {
    NSMutableDictionary *uids = [NSMutableDictionary dictionary];
    if (_currentInputID) {
        uids[RoleKey(APBDeviceRoleInput)] = _connectedUIDsByID[RoleKey(APBDeviceRoleInput)][_currentInputID];
    }
    if (_currentOutputID) {
        uids[RoleKey(APBDeviceRoleOutput)] = _connectedUIDsByID[RoleKey(APBDeviceRoleOutput)][_currentOutputID];
    }
    return uids;
}

/// Our own selection updates the current IDs immediately, so CoreAudio's
/// echo of it finds nothing new and cannot announce the same switch twice.
- (void)announceAutomaticSwitchesSince:(NSDictionary<NSNumber *, NSString *> *)before {
    if (!_hasStarted || _isManualMode || !_onAutomaticSwitch) return;
    NSDictionary<NSNumber *, NSString *> *after = self.currentUIDs;
    NSMutableArray<APBAudioDevice *> *switched = [NSMutableArray array];
    NSNumber *output = RoleKey(APBDeviceRoleOutput), *input = RoleKey(APBDeviceRoleInput);
    if (![after[output] isEqual:before[output]] && after[output] != before[output]) {
        APBAudioDevice *device = self.currentOutputDevice;
        if (device) [switched addObject:device];
    }
    if (![after[input] isEqual:before[input]] && after[input] != before[input]) {
        APBAudioDevice *device = self.currentInputDevice;
        if (device) [switched addObject:device];
    }
    if (switched.count) _onAutomaticSwitch(switched);
}

- (BOOL)isMuted:(APBAudioDevice *)device {
    return [_mutedRoles containsObject:device.roleIdentifier];
}

- (APBBatteryLevels *)batteryLevelsForDevice:(APBAudioDevice *)device {
    APBBatteryLevels *levels = [_battery levelsForDevice:device];
    if (levels) return levels;
    if (!device.isConnected) return nil;
    NSNumber *headset = _link.battery(device);
    return headset ? [APBBatteryLevels levelsWithLeft:nil right:nil caseLevel:nil main:nil headset:headset] : nil;
}

- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device {
    return device.isConnected ? _link.state(device) : APBLinkStateNone;
}

- (APBOutputCategory)activeOutputCategory {
    APBAudioDevice *output = self.currentOutputDevice;
    return output ? [_store categoryForDevice:output] : APBOutputCategoryNone;
}

- (APBAudioDevice *)currentOutputDevice {
    if (!_currentOutputID) return nil;
    for (APBAudioDevice *device in self.allOutputs) {
        if (APBIDIs(_currentOutputID, device.platformID)) return device;
    }
    return nil;
}

- (BOOL)isActiveOutputLinkDown {
    APBAudioDevice *output = self.currentOutputDevice;
    return output && [self linkStateForDevice:output] == APBLinkStateDown;
}

- (APBAutomaticOutputDecision *)automaticOutputDecision {
    if (_isManualMode) {
        return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:nil isDeferred:NO];
    }
    NSString *keptUID = _keptPicks[RoleKey(APBDeviceRoleOutput)];
    if (keptUID) {
        for (APBAudioDevice *device in self.allOutputs) {
            if ([device.uid isEqualToString:keptUID] && device.isConnected) {
                return [[APBAutomaticOutputDecision alloc] initWithTarget:device skipped:nil isDeferred:NO];
            }
        }
    }
    APBSkippedOutput *skipped = nil;
    for (APBAudioDevice *device in [_headphoneDevices arrayByAddingObjectsFromArray:_speakerDevices]) {
        APBOutputCategory category = [_store categoryForDevice:device];
        if (!device.isConnected || [_store isHidden:device inCategory:category]) continue;
        if ([_store isNeverUse:device]) {
            if (!skipped) {
                skipped = [[APBSkippedOutput alloc] initWithDevice:device reason:APBOutputSkipReasonNeverAutoSelect];
            }
            continue;
        }
        // Waiting a moment beats routing audio to this device and then
        // immediately moving away from it once the answer arrives.
        if ([self linkStateForDevice:device] == APBLinkStateChecking) {
            return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:skipped isDeferred:YES];
        }
        if (!_link.isUsable(device)) {
            if (!skipped) {
                skipped = [[APBSkippedOutput alloc] initWithDevice:device reason:APBOutputSkipReasonOff];
            }
            continue;
        }
        return [[APBAutomaticOutputDecision alloc] initWithTarget:device skipped:skipped isDeferred:NO];
    }
    return [[APBAutomaticOutputDecision alloc] initWithTarget:nil skipped:skipped isDeferred:NO];
}

- (NSArray<APBAudioDevice *> *)allOutputs {
    NSMutableArray *outputs = [_speakerDevices mutableCopy];
    [outputs addObjectsFromArray:_headphoneDevices];
    [outputs addObjectsFromArray:_hiddenSpeakerDevices];
    [outputs addObjectsFromArray:_hiddenHeadphoneDevices];
    return outputs;
}

#pragma mark - Selection

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
    APBAudioDevice *first = [self automaticTargetFor:role];
    if (first) [self select:first automatically:YES includesPairedDevice:YES];
}

- (APBAudioDevice *)automaticTargetFor:(APBDeviceRole)role {
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
            if (paired && ![_store isNeverUse:paired] && _link.isUsable(paired)) return paired;
        }
        return [_store firstSelectableIn:_inputDevices isUsable:_link.isUsable];
    }
    return self.automaticOutputDecision.target;
}

- (BOOL)select:(APBAudioDevice *)device {
    return [self select:device automatically:NO includesPairedDevice:YES];
}

- (BOOL)select:(APBAudioDevice *)device
  automatically:(BOOL)automatically
includesPairedDevice:(BOOL)includesPairedDevice {
    NSNumber *currentID = [self currentIDForRole:device.role];
    if (!APBIDIs(currentID, device.platformID)) {
        if (!_audio.setDefault(device.role, device.platformID)) return NO;
        if (device.role == APBDeviceRoleInput) {
            _currentInputID = @(device.platformID);
        } else {
            _currentOutputID = @(device.platformID);
        }
        [self didChange];
    }
    if (includesPairedDevice) {
        [self selectPairedDeviceOf:device automatically:automatically];
    }
    return YES;
}

- (void)selectPairedDeviceOf:(APBAudioDevice *)device automatically:(BOOL)automatically {
    _selectedOnlyOutputUID = nil;
    if (!_selectsPairedDevice) return;
    APBAudioDevice *partner = [self pairedDeviceFor:device];
    if (!partner) return;
    if (!(device.role == APBDeviceRoleOutput || !automatically)) return;
    if (APBIDIs([self currentIDForRole:partner.role], partner.platformID)) return;
    if (automatically && ([_store isNeverUse:partner] || !_link.isUsable(partner))) return;
    [self select:partner];
}

- (APBAudioDevice *)pairedDeviceFor:(APBAudioDevice *)device {
    if (device.isVirtual) return nil;
    NSArray<APBAudioDevice *> *candidates = device.role == APBDeviceRoleOutput
        ? _inputDevices
        : [_speakerDevices arrayByAddingObjectsFromArray:_headphoneDevices];
    NSString *key = device.pairingKey;
    for (APBAudioDevice *candidate in candidates) {
        if ([candidate.pairingKey isEqualToString:key]
            && candidate.isConnected
            && !candidate.isVirtual
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
        _micFlashState = YES;
    } else if (_isActiveInputMuted && !_micFlashTimer) {
        __weak typeof(self) weakSelf = self;
        _micFlashTimer = [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *timer) {
            APBAppModel *model = weakSelf;
            if (!model) return;
            model->_micFlashState = !model->_micFlashState;
            [model didChange];
        }];
    } else if (!_isActiveInputMuted) {
        [_micFlashTimer invalidate];
        _micFlashTimer = nil;
        _micFlashState = NO;
    }
}

@end
