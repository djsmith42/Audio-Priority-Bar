#import "Models.h"

NSString *APBDeviceRoleName(APBDeviceRole role) {
    return role == APBDeviceRoleInput ? @"input" : @"output";
}

NSString *APBOutputCategoryName(APBOutputCategory category) {
    switch (category) {
        case APBOutputCategorySpeaker: return @"speaker";
        case APBOutputCategoryHeadphone: return @"headphone";
        case APBOutputCategoryNone: return nil;
    }
    return nil;
}

APBOutputCategory APBOutputCategoryFromName(NSString *name) {
    if ([name isEqualToString:@"speaker"]) return APBOutputCategorySpeaker;
    if ([name isEqualToString:@"headphone"]) return APBOutputCategoryHeadphone;
    return APBOutputCategoryNone;
}

NSString *APBMenuBarDevicesName(APBMenuBarDevices devices) {
    switch (devices) {
        case APBMenuBarDevicesOutputOnly: return @"outputOnly";
        case APBMenuBarDevicesBoth: return @"both";
        case APBMenuBarDevicesBothLabeled: return @"bothLabeled";
    }
    return @"outputOnly";
}

BOOL APBMenuBarDevicesFromName(NSString *name, APBMenuBarDevices *result) {
    for (APBMenuBarDevices value = APBMenuBarDevicesOutputOnly;
         value <= APBMenuBarDevicesBothLabeled; value++) {
        if ([name isEqualToString:APBMenuBarDevicesName(value)]) {
            if (result) *result = value;
            return YES;
        }
    }
    return NO;
}

static NSString *const USBAudioPrefix = @"AppleUSBAudioEngine:";

@implementation APBAudioDevice

- (instancetype)initWithPlatformID:(UInt32)platformID
                               uid:(NSString *)uid
                              name:(NSString *)name
                              role:(APBDeviceRole)role
                       isConnected:(BOOL)isConnected
                         isVirtual:(BOOL)isVirtual
                  declaredCategory:(APBOutputCategory)declaredCategory
                   isDisplayOutput:(BOOL)isDisplayOutput
                     transportType:(UInt32)transportType {
    if ((self = [super init])) {
        _platformID = platformID;
        _uid = [uid copy];
        _name = [name copy];
        _role = role;
        _isConnected = isConnected;
        _isVirtual = isVirtual;
        _declaredCategory = declaredCategory;
        _isDisplayOutput = isDisplayOutput;
        _transportType = transportType;
    }
    return self;
}

- (instancetype)initWithPlatformID:(UInt32)platformID
                               uid:(NSString *)uid
                              name:(NSString *)name
                              role:(APBDeviceRole)role {
    return [self initWithPlatformID:platformID
                                uid:uid
                               name:name
                               role:role
                        isConnected:YES
                          isVirtual:NO
                   declaredCategory:APBOutputCategoryNone
                    isDisplayOutput:NO
                      transportType:0];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[APBAudioDevice allocWithZone:zone] initWithPlatformID:_platformID
                                                               uid:_uid
                                                              name:_name
                                                              role:_role
                                                       isConnected:_isConnected
                                                         isVirtual:_isVirtual
                                                  declaredCategory:_declaredCategory
                                                   isDisplayOutput:_isDisplayOutput
                                                     transportType:_transportType];
}

- (NSString *)identifier {
    return self.roleIdentifier;
}

- (NSString *)roleIdentifier {
    return [NSString stringWithFormat:@"%@:%@", APBDeviceRoleName(_role), _uid];
}

- (NSString *)pairingKey {
    NSString *uid = _uid;
    if (![uid hasPrefix:USBAudioPrefix]
        || [uid componentsSeparatedByString:@":"].count < 5) {
        return uid;
    }
    NSRange separator = [uid rangeOfString:@":" options:NSBackwardsSearch];
    if (separator.location == NSNotFound) return uid;
    NSString *suffix = [uid substringFromIndex:NSMaxRange(separator)];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    BOOL isNumeric = suffix.length > 0
        && [suffix rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
    return isNumeric ? [uid substringToIndex:separator.location] : uid;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:APBAudioDevice.class]) return NO;
    APBAudioDevice *other = object;
    return _platformID == other.platformID
        && [_uid isEqualToString:other.uid]
        && [_name isEqualToString:other.name]
        && _role == other.role
        && _isConnected == other.isConnected
        && _isVirtual == other.isVirtual
        && _declaredCategory == other.declaredCategory
        && _isDisplayOutput == other.isDisplayOutput
        && _transportType == other.transportType;
}

- (NSUInteger)hash {
    return _uid.hash ^ (NSUInteger)_platformID ^ ((NSUInteger)_role << 16);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<APBAudioDevice %u %@ \"%@\"%@>",
            _platformID, self.roleIdentifier, _name,
            _isConnected ? @"" : @" disconnected"];
}

@end

@implementation APBStoredDevice

- (instancetype)initWithUID:(NSString *)uid
                       name:(NSString *)name
                    isInput:(BOOL)isInput
                   lastSeen:(NSDate *)lastSeen
           declaredCategory:(APBOutputCategory)declaredCategory {
    if ((self = [super init])) {
        _uid = [uid copy];
        _name = [name copy];
        _isInput = isInput;
        _lastSeen = [lastSeen copy];
        _declaredCategory = declaredCategory;
    }
    return self;
}

- (instancetype)initWithDevice:(APBAudioDevice *)device lastSeen:(NSDate *)lastSeen {
    return [self initWithUID:device.uid
                        name:device.name
                     isInput:device.role == APBDeviceRoleInput
                    lastSeen:lastSeen
            declaredCategory:device.declaredCategory];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[APBStoredDevice allocWithZone:zone] initWithUID:_uid
                                                        name:_name
                                                     isInput:_isInput
                                                    lastSeen:_lastSeen
                                            declaredCategory:_declaredCategory];
}

- (APBDeviceRole)role {
    return _isInput ? APBDeviceRoleInput : APBDeviceRoleOutput;
}

- (APBAudioDevice *)disconnectedDevice {
    return [[APBAudioDevice alloc] initWithPlatformID:0
                                                  uid:_uid
                                                 name:_name
                                                 role:self.role
                                          isConnected:NO
                                            isVirtual:NO
                                     declaredCategory:_declaredCategory
                                      isDisplayOutput:NO
                                        transportType:0];
}

- (NSString *)relativeLastSeenTo:(NSDate *)now {
    NSTimeInterval seconds = [now timeIntervalSinceDate:_lastSeen];
    if (seconds < 60) return @"now";
    if (seconds < 3600) return [NSString stringWithFormat:@"%ldm ago", (long)(seconds / 60)];
    if (seconds < 86400) return [NSString stringWithFormat:@"%ldh ago", (long)(seconds / 3600)];
    if (seconds < 604800) return [NSString stringWithFormat:@"%ldd ago", (long)(seconds / 86400)];
    if (seconds < 2592000) return [NSString stringWithFormat:@"%ldw ago", (long)(seconds / 604800)];
    return [NSString stringWithFormat:@"%ldmo ago", (long)(seconds / 2592000)];
}

- (NSString *)relativeLastSeen {
    return [self relativeLastSeenTo:[NSDate date]];
}

// Swift's JSONEncoder writes a Date as seconds since the 2001 reference date
// and leaves out a nil optional, so this shape is what older builds wrote.
- (NSDictionary<NSString *, id> *)JSONObject {
    NSMutableDictionary *object = [@{
        @"uid": _uid,
        @"name": _name,
        @"isInput": @(_isInput),
        @"lastSeen": @(_lastSeen.timeIntervalSinceReferenceDate),
    } mutableCopy];
    NSString *category = APBOutputCategoryName(_declaredCategory);
    if (category) object[@"declaredCategory"] = category;
    return object;
}

+ (instancetype)deviceWithJSONObject:(id)object {
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *dictionary = object;
    id uid = dictionary[@"uid"], name = dictionary[@"name"];
    id isInput = dictionary[@"isInput"], lastSeen = dictionary[@"lastSeen"];
    if (![uid isKindOfClass:NSString.class]
        || ![name isKindOfClass:NSString.class]
        || ![isInput isKindOfClass:NSNumber.class]
        || ![lastSeen isKindOfClass:NSNumber.class]) {
        return nil;
    }
    APBOutputCategory category = APBOutputCategoryNone;
    id rawCategory = dictionary[@"declaredCategory"];
    if (rawCategory && rawCategory != NSNull.null) {
        // An unknown value fails decoding outright, as it did in Swift.
        if (![rawCategory isKindOfClass:NSString.class]) return nil;
        category = APBOutputCategoryFromName(rawCategory);
        if (category == APBOutputCategoryNone) return nil;
    }
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[lastSeen doubleValue]];
    return [[self alloc] initWithUID:uid
                                name:name
                             isInput:[isInput boolValue]
                            lastSeen:date
                    declaredCategory:category];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:APBStoredDevice.class]) return NO;
    APBStoredDevice *other = object;
    return [_uid isEqualToString:other.uid]
        && [_name isEqualToString:other.name]
        && _isInput == other.isInput
        && [_lastSeen isEqualToDate:other.lastSeen]
        && _declaredCategory == other.declaredCategory;
}

- (NSUInteger)hash {
    return _uid.hash ^ (NSUInteger)_isInput;
}

@end
