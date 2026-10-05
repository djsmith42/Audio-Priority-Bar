#import "APBModels.h"

NSString *APBDeviceRoleName(APBDeviceRole role) {
    return role == APBDeviceRoleInput ? @"input" : @"output";
}

APBDeviceRole APBDeviceRoleOther(APBDeviceRole role) {
    return role == APBDeviceRoleInput ? APBDeviceRoleOutput : APBDeviceRoleInput;
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

APBMenuBarDevices APBMenuBarDevicesFromName(NSString *name) {
    if ([name isEqualToString:@"both"]) return APBMenuBarDevicesBoth;
    if ([name isEqualToString:@"bothLabeled"]) return APBMenuBarDevicesBothLabeled;
    return APBMenuBarDevicesOutputOnly;
}

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
    self = [super init];
    if (self) {
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

- (APBAudioDevice *)deviceWithConnected:(BOOL)isConnected {
    return [[APBAudioDevice alloc] initWithPlatformID:_platformID
                                                  uid:_uid
                                                 name:_name
                                                 role:_role
                                          isConnected:isConnected
                                            isVirtual:_isVirtual
                                     declaredCategory:_declaredCategory
                                      isDisplayOutput:_isDisplayOutput
                                        transportType:_transportType];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)identifier {
    return [NSString stringWithFormat:@"%@:%@", APBDeviceRoleName(_role), _uid];
}

- (NSString *)pairingKey {
    if (![_uid hasPrefix:@"AppleUSBAudioEngine:"]
        || [_uid componentsSeparatedByString:@":"].count < 5) {
        return _uid;
    }
    NSRange separator = [_uid rangeOfString:@":" options:NSBackwardsSearch];
    NSString *suffix = [_uid substringFromIndex:NSMaxRange(separator)];
    if (suffix.length == 0) return _uid;
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if ([suffix rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return _uid;
    }
    return [_uid substringToIndex:separator.location];
}

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:APBAudioDevice.class]) return NO;
    APBAudioDevice *other = object;
    return _platformID == other->_platformID
        && [_uid isEqualToString:other->_uid]
        && [_name isEqualToString:other->_name]
        && _role == other->_role
        && _isConnected == other->_isConnected
        && _isVirtual == other->_isVirtual
        && _declaredCategory == other->_declaredCategory
        && _isDisplayOutput == other->_isDisplayOutput
        && _transportType == other->_transportType;
}

- (NSUInteger)hash {
    return _uid.hash ^ (NSUInteger)_role ^ ((NSUInteger)_platformID << 4);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<APBAudioDevice %u %@ \"%@\"%@>",
            _platformID, self.identifier, _name, _isConnected ? @"" : @" disconnected"];
}

@end

@implementation APBStoredDevice

- (instancetype)initWithUID:(NSString *)uid
                       name:(NSString *)name
                    isInput:(BOOL)isInput
                   lastSeen:(NSDate *)lastSeen
           declaredCategory:(APBOutputCategory)declaredCategory {
    self = [super init];
    if (self) {
        _uid = [uid copy];
        _name = [name copy];
        _isInput = isInput;
        _lastSeen = lastSeen;
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

- (NSString *)relativeLastSeen {
    return [self relativeLastSeenTo:[NSDate date]];
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
    id uid = dictionary[@"uid"];
    id name = dictionary[@"name"];
    id isInput = dictionary[@"isInput"];
    id lastSeen = dictionary[@"lastSeen"];
    id category = dictionary[@"declaredCategory"];
    if (![uid isKindOfClass:NSString.class]
        || ![name isKindOfClass:NSString.class]
        || ![isInput isKindOfClass:NSNumber.class]
        || ![lastSeen isKindOfClass:NSNumber.class]) {
        return nil;
    }
    APBOutputCategory declared = APBOutputCategoryNone;
    if (category && category != NSNull.null) {
        // An unknown category fails the whole record, as decoding did before.
        if (![category isKindOfClass:NSString.class]) return nil;
        declared = APBOutputCategoryFromName(category);
        if (declared == APBOutputCategoryNone) return nil;
    }
    return [[self alloc] initWithUID:uid
                                name:name
                             isInput:[isInput boolValue]
                            lastSeen:[NSDate dateWithTimeIntervalSinceReferenceDate:[lastSeen doubleValue]]
                    declaredCategory:declared];
}

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:APBStoredDevice.class]) return NO;
    APBStoredDevice *other = object;
    return [_uid isEqualToString:other->_uid]
        && [_name isEqualToString:other->_name]
        && _isInput == other->_isInput
        && [_lastSeen isEqualToDate:other->_lastSeen]
        && _declaredCategory == other->_declaredCategory;
}

- (NSUInteger)hash {
    return _uid.hash ^ (NSUInteger)_isInput;
}

@end
