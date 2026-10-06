#import "AppModel.h"
#import "AppModel+Private.h"

/// `Array.move(fromOffsets:toOffset:)`: the items at `source` move, in order,
/// to land before the item that was at `destination`.
static NSArray *Move(NSArray *array, NSIndexSet *source, NSInteger destination) {
    NSArray *moved = [array objectsAtIndexes:source];
    NSUInteger below = [source countOfIndexesInRange:NSMakeRange(0, (NSUInteger)destination)];
    NSMutableArray *result = [array mutableCopy];
    [result removeObjectsAtIndexes:source];
    NSRange range = NSMakeRange((NSUInteger)destination - below, moved.count);
    [result insertObjects:moved atIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
    return result;
}

static BOOL AllIndexesBelow(NSIndexSet *indexes, NSUInteger count) {
    return indexes.count == 0 || indexes.lastIndex < count;
}

@implementation APBAppModel (Actions)

- (void)setManualMode:(BOOL)enabled {
    self.isManualMode = enabled;
    self.store.isManualMode = enabled;
    [self.keptPicks removeAllObjects];
    [self.switchedBackAt removeAllObjects];
    [self.takeoverUIDs removeAllObjects];
    if (!enabled) [self applyHighestPriorityDevices];
    [self didChange];
}

- (void)setSelectsPairedDeviceEnabled:(BOOL)enabled {
    self.selectsPairedDevice = enabled;
    self.store.selectsPairedDevice = enabled;
    APBAudioDevice *output = self.currentOutputDevice;
    if (enabled && output) {
        [self selectPairedDeviceOf:output automatically:!self.isManualMode];
    } else if (!self.isManualMode) {
        [self applyHighestPriorityInput];
    }
    [self didChange];
}

- (void)setHideNewDisplayOutputsEnabled:(BOOL)enabled {
    self.hideNewDisplayOutputs = enabled;
    self.store.hideNewDisplayOutputs = enabled;
    [self didChange];
}

- (void)setShowsSwitchNoticeEnabled:(BOOL)enabled {
    self.showsSwitchNotice = enabled;
    self.store.showsSwitchNotice = enabled;
    [self didChange];
}

- (void)setRemindsWhenMutedEnabled:(BOOL)enabled {
    self.remindsWhenMuted = enabled;
    self.store.remindsWhenMuted = enabled;
    [self didChange];
}

- (void)setMutesSpeakersWhenHeadphonesDisconnectEnabled:(BOOL)enabled {
    self.mutesSpeakersWhenHeadphonesDisconnect = enabled;
    self.store.mutesSpeakersWhenHeadphonesDisconnect = enabled;
    [self didChange];
}

- (void)setOutlinesMenuBarIconEnabled:(BOOL)enabled {
    self.outlinesMenuBarIcon = enabled;
    self.store.outlinesMenuBarIcon = enabled;
    [self didChange];
}

- (void)setMenuBarDevicesChoice:(APBMenuBarDevices)devices {
    self.menuBarDevices = devices;
    self.store.menuBarDevices = devices;
    [self didChange];
}

- (void)setShowsMenuBarVolumeEnabled:(BOOL)enabled {
    self.showsMenuBarVolume = enabled;
    self.store.showsMenuBarVolume = enabled;
    [self didChange];
}

- (void)setMicrophoneMuted:(BOOL)muted {
    self.isMicrophoneMuted = muted;
    [self refreshMute];
    [self refreshVolume];
}

- (void)perform:(APBURLCommand)command {
    switch (command) {
        case APBURLCommandToggleMicMute: [self setMicrophoneMuted:!self.isMicrophoneMuted]; break;
        case APBURLCommandMuteMic: [self setMicrophoneMuted:YES]; break;
        case APBURLCommandUnmuteMic: [self setMicrophoneMuted:NO]; break;
        case APBURLCommandNone: break;
    }
}

- (void)changeMicrophoneLevel:(float)value {
    NSNumber *deviceID = self.currentInputID;
    if (!deviceID) return;
    if (self.isMicrophoneMuted) [self setMicrophoneMuted:NO];
    if (!self.audio.setInputVolume(deviceID.unsignedIntValue, value)) return;
    self.microphoneLevel = value;
    [self didChange];
}

- (void)setOutputMuted:(BOOL)muted {
    NSNumber *deviceID = self.currentOutputID;
    if (!deviceID || !self.audio.setMute(APBDeviceRoleOutput, deviceID.unsignedIntValue, muted)) return;
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
    self.selectedOnlyOutputUID = device.role == APBDeviceRoleOutput ? device.uid : nil;
    if (![self select:device automatically:NO includesPairedDevice:NO]) {
        self.selectedOnlyOutputUID = nil;
    }
}

- (void)changeVolume:(float)value {
    if (!self.audio.setOutputVolume(value)) return;
    self.volume = value;
    if (self.isActiveOutputMuted && value > 0) [self setOutputMuted:NO];
    [self didChange];
}

- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device {
    [self preservingVisibilityMovingTo:category device:device];
    [self refreshDevices];
    if (!self.isManualMode) [self applyHighestPriorityOutput];
}

/// Moves a device to a category without changing whether it is hidden: a
/// hidden device stays hidden in its new list, and a visible one stays
/// visible rather than inheriting a stale hide flag left over from before
/// hiding became a single, both-categories command.
- (void)preservingVisibilityMovingTo:(APBOutputCategory)category device:(APBAudioDevice *)device {
    BOOL wasHidden = [self.store isHidden:device];
    [self.store setCategory:category forDevice:device];
    if (wasHidden) {
        [self.store hide:device inCategory:category];
    } else {
        [self.store unhide:device fromCategory:category];
    }
}

- (void)hide:(APBAudioDevice *)device {
    if (device.role == APBDeviceRoleInput) {
        [self.store hide:device];
    } else {
        [self.store hide:device inCategory:APBOutputCategorySpeaker];
        [self.store hide:device inCategory:APBOutputCategoryHeadphone];
    }
    [self refreshDevices];
    [self reselect:device.role];
}

- (void)unhide:(APBAudioDevice *)device {
    if (device.role == APBDeviceRoleInput) {
        [self.store unhide:device];
    } else {
        [self.store unhide:device fromCategory:APBOutputCategorySpeaker];
        [self.store unhide:device fromCategory:APBOutputCategoryHeadphone];
    }
    [self refreshDevices];
}

- (BOOL)isHidden:(APBAudioDevice *)device {
    return [self.store isHidden:device];
}

- (BOOL)isNeverUse:(APBAudioDevice *)device {
    return [self.store isNeverUse:device];
}

- (void)setNeverUse:(APBAudioDevice *)device enabled:(BOOL)enabled {
    [self.store setNeverUse:device value:enabled];
    [self refreshDevices];
    [self reselect:device.role];
}

- (void)forget:(APBAudioDevice *)device {
    [self.store forgetUID:device.uid role:device.role];
    [self refreshDevices];
}

- (void)moveInputFrom:(NSIndexSet *)source to:(NSInteger)destination {
    NSUInteger count = self.inputDevices.count;
    if (!AllIndexesBelow(source, count) || destination < 0 || (NSUInteger)destination > count) return;
    self.inputDevices = Move(self.inputDevices, source, destination);
    [self.store savePriorities:self.inputDevices role:APBDeviceRoleInput];
    if (!self.isManualMode) [self applyHighestPriorityInput];
    [self didChange];
}

- (void)moveOutputIn:(APBOutputCategory)category from:(NSIndexSet *)source to:(NSInteger)destination {
    BOOL isSpeaker = category == APBOutputCategorySpeaker;
    NSUInteger count = isSpeaker ? self.speakerDevices.count : self.headphoneDevices.count;
    if (!AllIndexesBelow(source, count) || destination < 0 || (NSUInteger)destination > count) return;
    if (isSpeaker) {
        self.speakerDevices = Move(self.speakerDevices, source, destination);
        [self.store savePriorities:self.speakerDevices category:APBOutputCategorySpeaker];
    } else {
        self.headphoneDevices = Move(self.headphoneDevices, source, destination);
        [self.store savePriorities:self.headphoneDevices category:APBOutputCategoryHeadphone];
    }
    if (!self.isManualMode) [self applyHighestPriorityOutput];
    [self didChange];
}

static NSUInteger IndexOfIdentifier(NSArray<APBAudioDevice *> *devices, NSString *identifier) {
    return [devices indexOfObjectPassingTest:^BOOL(APBAudioDevice *device, NSUInteger index, BOOL *stop) {
        return [device.identifier isEqualToString:identifier];
    }];
}

static NSInteger Clamp(NSInteger value, NSInteger count) {
    return MAX(0, MIN(value, count));
}

- (BOOL)dropDevice:(NSString *)identifier into:(APBOutputCategory)category at:(NSInteger)destination {
    if (category == APBOutputCategoryNone) {
        NSUInteger source = IndexOfIdentifier(self.inputDevices, identifier);
        if (source == NSNotFound) return NO;
        [self moveInputFrom:[NSIndexSet indexSetWithIndex:source]
                         to:Clamp(destination, (NSInteger)self.inputDevices.count)];
        return YES;
    }

    NSArray<APBAudioDevice *> *outputs = [self.speakerDevices arrayByAddingObjectsFromArray:self.headphoneDevices];
    NSUInteger found = IndexOfIdentifier(outputs, identifier);
    if (found == NSNotFound) return NO;
    APBAudioDevice *device = outputs[found];
    APBOutputCategory sourceCategory = [self.store categoryForDevice:device];
    if (sourceCategory == category) {
        NSArray<APBAudioDevice *> *devices = category == APBOutputCategorySpeaker
            ? self.speakerDevices
            : self.headphoneDevices;
        NSUInteger source = [devices indexOfObject:device];
        if (source == NSNotFound) return NO;
        [self moveOutputIn:category
                      from:[NSIndexSet indexSetWithIndex:source]
                        to:Clamp(destination, (NSInteger)devices.count)];
        return YES;
    }

    [self preservingVisibilityMovingTo:category device:device];
    [self refreshDevices];
    NSMutableArray<APBAudioDevice *> *devices = [(category == APBOutputCategorySpeaker
        ? self.speakerDevices
        : self.headphoneDevices) mutableCopy];
    NSUInteger source = IndexOfIdentifier(devices, identifier);
    if (source == NSNotFound) return NO;
    APBAudioDevice *moved = devices[source];
    [devices removeObjectAtIndex:source];
    [devices insertObject:moved atIndex:(NSUInteger)Clamp(destination, (NSInteger)devices.count)];
    if (category == APBOutputCategorySpeaker) {
        self.speakerDevices = devices;
    } else {
        self.headphoneDevices = devices;
    }
    [self.store savePriorities:devices category:category];
    if (!self.isManualMode) [self applyHighestPriorityOutput];
    [self didChange];
    return YES;
}

- (void)reselect:(APBDeviceRole)role {
    if (self.isManualMode) return;
    if (role == APBDeviceRoleInput) {
        [self applyHighestPriorityInput];
    } else {
        [self applyHighestPriorityOutput];
    }
}

@end
