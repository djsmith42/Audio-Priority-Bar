#import "PriorityStore.h"
#import "HeadphoneDetection.h"

static NSString *const KeyInputPriorities = @"inputPriorities";
static NSString *const KeySpeakerPriorities = @"speakerPriorities";
static NSString *const KeyHeadphonePriorities = @"headphonePriorities";
static NSString *const KeyCategories = @"deviceCategories";
static NSString *const KeyManualMode = @"customMode";
static NSString *const KeyLinksMicrophone = @"linksMicrophone";
static NSString *const KeySelectsPairedDevice = @"selectsPairedDevice";
static NSString *const KeyHideNewDisplayOutputs = @"hideNewDisplayOutputs";
static NSString *const KeyDisplayDefaultsApplied = @"displayDefaultsApplied";
static NSString *const KeyKnownDevices = @"knownDevices";
static NSString *const KeyLegacyNeverUse = @"neverUseDevices";
static NSString *const KeyNeverUseInputs = @"neverUseInputs";
static NSString *const KeyNeverUseOutputs = @"neverUseOutputs";
static NSString *const KeyNeverUseMigration = @"roleSpecificNeverUseMigration_v1";
static NSString *const KeyBundleMigration = @"legacyBundleMigration_v1";
static NSString *const KeyVirtualDefaults = @"virtualNeverUseDefaults_v1";
static NSString *const KeyHiddenInputs = @"hiddenMics";
static NSString *const KeyHiddenSpeakers = @"hiddenSpeakers";
static NSString *const KeyHiddenHeadphones = @"hiddenHeadphones";
static NSString *const KeyAppliedMicrophoneMutes = @"appliedMicrophoneMutes";
static NSString *const KeyShowsSwitchNotice = @"showsSwitchNotice";
static NSString *const KeyRemindsWhenMuted = @"remindsWhenMuted";
static NSString *const KeyMutesSpeakersWhenHeadphonesDisconnect = @"mutesSpeakersWhenHeadphonesDisconnect";
static NSString *const KeyOutlinesMenuBarIcon = @"outlinesMenuBarIcon";
static NSString *const KeyMenuBarDevices = @"menuBarDevices";
static NSString *const KeyShowsMenuBarVolume = @"showsMenuBarVolume";

static NSString *const LegacyBundleID = @"com.example.AudioPriorityBar";

/// Keeps the first of each repeated value, in order.
static NSArray *Uniqued(NSArray *values) {
    return [NSOrderedSet orderedSetWithArray:values].array;
}

@implementation APBPriorityStore {
    NSUserDefaults *_defaults;
    NSDate *(^_now)(void);
}

+ (double)mutedByProperty {
    return -1;
}

+ (NSArray<NSString *> *)legacyBundleKeys {
    return @[
        KeyInputPriorities,
        KeySpeakerPriorities,
        KeyHeadphonePriorities,
        KeyCategories,
        KeyManualMode,
        KeyKnownDevices,
        KeyLegacyNeverUse,
        KeyHiddenInputs,
        KeyHiddenSpeakers,
        KeyHiddenHeadphones,
    ];
}

- (instancetype)init {
    return [self initWithDefaults:NSUserDefaults.standardUserDefaults];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    return [self initWithDefaults:defaults now:nil legacyDomain:nil];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                             now:(NSDate *(^)(void))now
                    legacyDomain:(NSDictionary<NSString *, id> *)legacyDomain {
    if ((self = [super init])) {
        _defaults = defaults;
        _now = now ?: ^{ return [NSDate date]; };
        // One-time migration from the pre-rename key: the new key's presence
        // makes this idempotent, so no marker key is needed.
        id legacyValue = [defaults objectForKey:KeyLinksMicrophone];
        if ([defaults objectForKey:KeySelectsPairedDevice] == nil
            && [legacyValue isKindOfClass:NSNumber.class]) {
            [defaults setBool:[legacyValue boolValue] forKey:KeySelectsPairedDevice];
        }
        if (legacyDomain != nil || defaults == NSUserDefaults.standardUserDefaults) {
            [self migrateLegacyBundleIfNeededFrom:legacyDomain
                ?: [defaults persistentDomainForName:LegacyBundleID]];
            [self migrateLegacyNeverUseIfNeeded];
        }
    }
    return self;
}

#pragma mark - Known devices

- (NSArray<APBStoredDevice *> *)knownDevices {
    NSData *data = [_defaults dataForKey:KeyKnownDevices];
    if (!data) return @[];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *devices = [NSMutableArray array];
    for (id object in root) {
        APBStoredDevice *device = [APBStoredDevice deviceWithJSONObject:object];
        // Like a Swift decode, one bad entry fails the whole list.
        if (!device) return @[];
        [devices addObject:device];
    }
    return devices;
}

- (void)remember:(NSArray<APBAudioDevice *> *)devices {
    NSMutableArray<APBStoredDevice *> *known = [self.knownDevices mutableCopy];
    // Devices present before this shipped never passed through the
    // first-sight branch, so seed them once too.
    BOOL seedsExisting = ![_defaults boolForKey:KeyVirtualDefaults];
    for (APBAudioDevice *device in devices) {
        NSUInteger existing = [known indexOfObjectPassingTest:^BOOL(APBStoredDevice *stored, NSUInteger index, BOOL *stop) {
            return [stored.uid isEqualToString:device.uid] && stored.role == device.role;
        }];
        APBStoredDevice *stored = [[APBStoredDevice alloc] initWithDevice:device lastSeen:_now()];
        if (existing != NSNotFound) {
            known[existing] = stored;
        } else {
            [known addObject:stored];
        }
        // A routing helper is a poor automatic choice, but stays selectable
        // by hand, and the user can opt it back in permanently.
        if (device.isVirtual && (existing == NSNotFound || seedsExisting)) {
            [self setNeverUse:device value:YES];
        }
        [self applyDisplayDefaultIfNeeded:device];
    }
    if (seedsExisting && devices.count > 0) {
        [_defaults setBool:YES forKey:KeyVirtualDefaults];
    }
    [self saveKnownDevices:known];
}

- (APBStoredDevice *)storedDeviceWithUID:(NSString *)uid role:(NSNumber *)role {
    for (APBStoredDevice *stored in self.knownDevices) {
        if ([stored.uid isEqualToString:uid]
            && (role == nil || stored.role == role.integerValue)) {
            return stored;
        }
    }
    return nil;
}

- (void)forgetUID:(NSString *)uid role:(APBDeviceRole)role {
    [self migrateLegacyNeverUseIfNeeded];
    NSPredicate *others = [NSPredicate predicateWithBlock:^BOOL(APBStoredDevice *stored, id bindings) {
        return !([stored.uid isEqualToString:uid] && stored.role == role);
    }];
    [self saveKnownDevices:[self.knownDevices filteredArrayUsingPredicate:others]];

    NSArray *priorityKeys = role == APBDeviceRoleInput
        ? @[KeyInputPriorities]
        : @[KeySpeakerPriorities, KeyHeadphonePriorities];
    NSArray *hiddenKeys = role == APBDeviceRoleInput
        ? @[KeyHiddenInputs]
        : @[KeyHiddenSpeakers, KeyHiddenHeadphones];
    NSArray *keys = [[priorityKeys arrayByAddingObjectsFromArray:hiddenKeys]
                     arrayByAddingObject:[self neverUseKeyForRole:role]];
    for (NSString *key in keys) {
        [self removeValue:uid fromKey:key];
    }

    if (role == APBDeviceRoleOutput) {
        NSMutableDictionary *categories = [[_defaults dictionaryForKey:KeyCategories] mutableCopy]
            ?: [NSMutableDictionary dictionary];
        [categories removeObjectForKey:uid];
        [_defaults setObject:categories forKey:KeyCategories];
        // Forgetting clears every saved choice, so a display seen again
        // afterwards is genuinely new and gets the default once more.
        [self removeValue:uid fromKey:KeyDisplayDefaultsApplied];
    }
}

#pragma mark - Preferences

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [_defaults objectForKey:key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultValue;
}

- (BOOL)isManualMode { return [_defaults boolForKey:KeyManualMode]; }
- (void)setIsManualMode:(BOOL)value { [_defaults setBool:value forKey:KeyManualMode]; }

- (BOOL)selectsPairedDevice { return [self boolForKey:KeySelectsPairedDevice defaultValue:YES]; }
- (void)setSelectsPairedDevice:(BOOL)value { [_defaults setBool:value forKey:KeySelectsPairedDevice]; }

- (BOOL)hideNewDisplayOutputs { return [self boolForKey:KeyHideNewDisplayOutputs defaultValue:YES]; }
- (void)setHideNewDisplayOutputs:(BOOL)value { [_defaults setBool:value forKey:KeyHideNewDisplayOutputs]; }

- (BOOL)showsSwitchNotice { return [self boolForKey:KeyShowsSwitchNotice defaultValue:YES]; }
- (void)setShowsSwitchNotice:(BOOL)value { [_defaults setBool:value forKey:KeyShowsSwitchNotice]; }

- (BOOL)remindsWhenMuted { return [self boolForKey:KeyRemindsWhenMuted defaultValue:YES]; }
- (void)setRemindsWhenMuted:(BOOL)value { [_defaults setBool:value forKey:KeyRemindsWhenMuted]; }

- (BOOL)mutesSpeakersWhenHeadphonesDisconnect {
    return [_defaults boolForKey:KeyMutesSpeakersWhenHeadphonesDisconnect];
}
- (void)setMutesSpeakersWhenHeadphonesDisconnect:(BOOL)value {
    [_defaults setBool:value forKey:KeyMutesSpeakersWhenHeadphonesDisconnect];
}

- (BOOL)outlinesMenuBarIcon { return [_defaults boolForKey:KeyOutlinesMenuBarIcon]; }
- (void)setOutlinesMenuBarIcon:(BOOL)value { [_defaults setBool:value forKey:KeyOutlinesMenuBarIcon]; }

- (APBMenuBarDevices)menuBarDevices {
    APBMenuBarDevices devices = APBMenuBarDevicesOutputOnly;
    APBMenuBarDevicesFromName([_defaults stringForKey:KeyMenuBarDevices], &devices);
    return devices;
}
- (void)setMenuBarDevices:(APBMenuBarDevices)value {
    [_defaults setObject:APBMenuBarDevicesName(value) forKey:KeyMenuBarDevices];
}

- (BOOL)showsMenuBarVolume { return [_defaults boolForKey:KeyShowsMenuBarVolume]; }
- (void)setShowsMenuBarVolume:(BOOL)value { [_defaults setBool:value forKey:KeyShowsMenuBarVolume]; }

- (NSDictionary<NSString *, NSNumber *> *)appliedMicrophoneMutes {
    NSDictionary *stored = [_defaults dictionaryForKey:KeyAppliedMicrophoneMutes];
    for (id value in stored.allValues) {
        if (![value isKindOfClass:NSNumber.class]) return @{};
    }
    return stored ?: @{};
}

- (void)setAppliedMicrophoneMutes:(NSDictionary<NSString *, NSNumber *> *)value {
    [_defaults setObject:value forKey:KeyAppliedMicrophoneMutes];
}

- (void)setAppliedMicrophoneMute:(NSNumber *)level forUID:(NSString *)uid {
    NSMutableDictionary *mutes = [self.appliedMicrophoneMutes mutableCopy];
    mutes[uid] = level;
    self.appliedMicrophoneMutes = mutes;
}

#pragma mark - Categories

/// The saved categories, or none when any entry is not a string, as Swift's
/// `as? [String: String]` cast would.
- (NSDictionary<NSString *, NSString *> *)categories {
    NSDictionary *stored = [_defaults dictionaryForKey:KeyCategories];
    for (id value in stored.allValues) {
        if (![value isKindOfClass:NSString.class]) return @{};
    }
    return stored ?: @{};
}

- (APBOutputCategory)categoryForDevice:(APBAudioDevice *)device {
    APBOutputCategory saved = APBOutputCategoryFromName(self.categories[device.uid]);
    if (saved != APBOutputCategoryNone) return saved;
    // Ahead of the device's own claim, because a speakerphone has no
    // terminal type of its own and may describe itself as headphones.
    if ([APBHeadphoneDetection isKnownSpeaker:device.name]) {
        return APBOutputCategorySpeaker;
    }
    if (device.declaredCategory != APBOutputCategoryNone) {
        return device.declaredCategory;
    }
    return [APBHeadphoneDetection isHeadphone:device.name]
        ? APBOutputCategoryHeadphone
        : APBOutputCategorySpeaker;
}

- (void)setCategory:(APBOutputCategory)category forDevice:(APBAudioDevice *)device {
    NSMutableDictionary *categories = [self.categories mutableCopy];
    categories[device.uid] = APBOutputCategoryName(category);
    [_defaults setObject:categories forKey:KeyCategories];
}

#pragma mark - Never use

- (BOOL)isNeverUse:(APBAudioDevice *)device {
    [self migrateLegacyNeverUseIfNeeded];
    return [[_defaults stringArrayForKey:[self neverUseKeyForRole:device.role]]
            containsObject:device.uid];
}

- (void)setNeverUse:(APBAudioDevice *)device value:(BOOL)value {
    [self migrateLegacyNeverUseIfNeeded];
    NSString *key = [self neverUseKeyForRole:device.role];
    NSMutableArray *uids = [[_defaults stringArrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    if (value) {
        if (![uids containsObject:device.uid]) [uids addObject:device.uid];
    } else {
        [uids removeObject:device.uid];
    }
    [_defaults setObject:uids forKey:key];
}

#pragma mark - Hidden

- (BOOL)isHidden:(APBAudioDevice *)device {
    return [[_defaults stringArrayForKey:[self hiddenKeyForDevice:device]] containsObject:device.uid];
}

- (BOOL)isHidden:(APBAudioDevice *)device inCategory:(APBOutputCategory)category {
    return [[_defaults stringArrayForKey:[self hiddenKeyForCategory:category]] containsObject:device.uid];
}

- (void)hide:(APBAudioDevice *)device {
    [self addValue:device.uid toKey:[self hiddenKeyForDevice:device]];
}

- (void)hide:(APBAudioDevice *)device inCategory:(APBOutputCategory)category {
    [self addValue:device.uid toKey:[self hiddenKeyForCategory:category]];
}

- (void)unhide:(APBAudioDevice *)device {
    [self removeValue:device.uid fromKey:[self hiddenKeyForDevice:device]];
}

- (void)unhide:(APBAudioDevice *)device fromCategory:(APBOutputCategory)category {
    [self removeValue:device.uid fromKey:[self hiddenKeyForCategory:category]];
}

#pragma mark - Priorities

- (NSArray<APBAudioDevice *> *)sorted:(NSArray<APBAudioDevice *> *)devices role:(APBDeviceRole)role {
    return [self sorted:devices key:[self priorityKeyForRole:role category:APBOutputCategoryNone]];
}

- (NSArray<APBAudioDevice *> *)sorted:(NSArray<APBAudioDevice *> *)devices category:(APBOutputCategory)category {
    return [self sorted:devices key:[self priorityKeyForRole:APBDeviceRoleOutput category:category]];
}

- (void)savePriorities:(NSArray<APBAudioDevice *> *)devices role:(APBDeviceRole)role {
    [self savePriorities:devices key:[self priorityKeyForRole:role category:APBOutputCategoryNone]];
}

- (void)savePriorities:(NSArray<APBAudioDevice *> *)devices category:(APBOutputCategory)category {
    [self savePriorities:devices key:[self priorityKeyForRole:APBDeviceRoleOutput category:category]];
}

- (APBAudioDevice *)firstSelectableIn:(NSArray<APBAudioDevice *> *)devices
                             isUsable:(BOOL (^)(APBAudioDevice *))isUsable {
    for (APBAudioDevice *device in devices) {
        if (device.isConnected
            && ![self isHidden:device]
            && ![self isNeverUse:device]
            && isUsable(device)) {
            return device;
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)mergeVisibleOrder:(NSArray<NSString *> *)visible
                                      into:(NSArray<NSString *> *)stored {
    NSArray<NSString *> *uniqueVisible = Uniqued(visible);
    NSSet<NSString *> *visibleSet = [NSSet setWithArray:uniqueVisible];
    NSUInteger next = 0;
    NSMutableArray<NSString *> *merged = [NSMutableArray array];
    for (NSString *uid in stored) {
        if ([visibleSet containsObject:uid]) {
            // Each visible slot takes the next visible uid in its new order.
            if (next < uniqueVisible.count) [merged addObject:uniqueVisible[next++]];
        } else {
            [merged addObject:uid];
        }
    }
    for (; next < uniqueVisible.count; next++) {
        [merged addObject:uniqueVisible[next]];
    }
    return Uniqued(merged);
}

#pragma mark - Private

/// Hides a monitor or TV the first time it is seen, and records that it
/// has been dealt with. Deciding once is what makes showing one by hand
/// permanent: a later sighting must never hide it again. The record is kept
/// even when the preference is off, so turning the preference on applies to
/// genuinely new devices rather than retroactively.
///
/// Hidden in both output categories, matching the app's single Hide
/// command: a later category move must not surface a device the user
/// never asked to see.
- (void)applyDisplayDefaultIfNeeded:(APBAudioDevice *)device {
    if (!device.isDisplayOutput) return;
    NSMutableArray *applied = [[_defaults stringArrayForKey:KeyDisplayDefaultsApplied] mutableCopy]
        ?: [NSMutableArray array];
    if ([applied containsObject:device.uid]) return;
    [applied addObject:device.uid];
    [_defaults setObject:applied forKey:KeyDisplayDefaultsApplied];
    if (self.hideNewDisplayOutputs) {
        [self hide:device inCategory:APBOutputCategorySpeaker];
        [self hide:device inCategory:APBOutputCategoryHeadphone];
    }
}

- (void)saveKnownDevices:(NSArray<APBStoredDevice *> *)devices {
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:devices.count];
    for (APBStoredDevice *device in devices) [objects addObject:device.JSONObject];
    NSData *data = [NSJSONSerialization dataWithJSONObject:objects options:0 error:NULL];
    if (data) [_defaults setObject:data forKey:KeyKnownDevices];
}

- (void)migrateLegacyBundleIfNeededFrom:(NSDictionary<NSString *, id> *)legacy {
    if (!legacy || [_defaults boolForKey:KeyBundleMigration]) return;
    for (NSString *key in self.class.legacyBundleKeys) {
        if ([_defaults objectForKey:key] != nil) continue;
        id value = legacy[key];
        if (value) [_defaults setObject:value forKey:key];
    }
    [_defaults setBool:YES forKey:KeyBundleMigration];
}

- (void)migrateLegacyNeverUseIfNeeded {
    BOOL hasLegacyValues = [_defaults objectForKey:KeyLegacyNeverUse] != nil;
    if (!hasLegacyValues && [_defaults boolForKey:KeyNeverUseMigration]) return;
    NSArray *legacy = [_defaults stringArrayForKey:KeyLegacyNeverUse] ?: @[];
    for (NSString *key in @[KeyNeverUseInputs, KeyNeverUseOutputs]) {
        NSArray *existing = [_defaults stringArrayForKey:key] ?: @[];
        [_defaults setObject:Uniqued([existing arrayByAddingObjectsFromArray:legacy]) forKey:key];
    }
    [_defaults removeObjectForKey:KeyLegacyNeverUse];
    [_defaults setBool:YES forKey:KeyNeverUseMigration];
}

- (NSString *)neverUseKeyForRole:(APBDeviceRole)role {
    return role == APBDeviceRoleInput ? KeyNeverUseInputs : KeyNeverUseOutputs;
}

- (NSString *)hiddenKeyForDevice:(APBAudioDevice *)device {
    if (device.role == APBDeviceRoleInput) return KeyHiddenInputs;
    return [self hiddenKeyForCategory:[self categoryForDevice:device]];
}

- (NSString *)hiddenKeyForCategory:(APBOutputCategory)category {
    return category == APBOutputCategorySpeaker ? KeyHiddenSpeakers : KeyHiddenHeadphones;
}

- (NSString *)priorityKeyForRole:(APBDeviceRole)role category:(APBOutputCategory)category {
    if (role == APBDeviceRoleInput) return KeyInputPriorities;
    return category == APBOutputCategoryHeadphone ? KeyHeadphonePriorities : KeySpeakerPriorities;
}

- (NSArray<APBAudioDevice *> *)sorted:(NSArray<APBAudioDevice *> *)devices key:(NSString *)key {
    NSArray<NSString *> *priorities = [_defaults stringArrayForKey:key] ?: @[];
    // ponytail: device lists are tiny; index scans keep ordering obvious.
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:devices.count];
    for (NSUInteger index = 0; index < devices.count; index++) [order addObject:@(index)];
    [order sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
        NSUInteger lhs = [priorities indexOfObject:devices[left.unsignedIntegerValue].uid];
        NSUInteger rhs = [priorities indexOfObject:devices[right.unsignedIntegerValue].uid];
        if (lhs == rhs) return NSOrderedSame;
        return lhs < rhs ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<APBAudioDevice *> *sorted = [NSMutableArray arrayWithCapacity:devices.count];
    for (NSNumber *index in order) [sorted addObject:devices[index.unsignedIntegerValue]];
    return sorted;
}

- (void)savePriorities:(NSArray<APBAudioDevice *> *)devices key:(NSString *)key {
    NSArray<NSString *> *visible = [devices valueForKey:@"uid"];
    NSArray<NSString *> *stored = [_defaults stringArrayForKey:key] ?: @[];
    [_defaults setObject:[self.class mergeVisibleOrder:visible into:stored] forKey:key];
}

- (void)addValue:(NSString *)uid toKey:(NSString *)key {
    NSMutableArray *values = [[_defaults stringArrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    if (![values containsObject:uid]) {
        [values addObject:uid];
        [_defaults setObject:values forKey:key];
    }
}

- (void)removeValue:(NSString *)uid fromKey:(NSString *)key {
    NSMutableArray *values = [[_defaults stringArrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    [values removeObject:uid];
    [_defaults setObject:values forKey:key];
}

@end
