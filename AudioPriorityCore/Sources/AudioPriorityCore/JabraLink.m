#import "JabraLink.h"

@implementation APBJabraSignal

+ (instancetype)elementWithPage:(NSInteger)page usage:(NSInteger)usage linkedValue:(NSInteger)linkedValue {
    APBJabraSignal *signal = [[self alloc] init];
    signal->_kind = APBJabraSignalKindElement;
    signal->_page = page;
    signal->_usage = usage;
    signal->_linkedValue = linkedValue;
    return signal;
}

+ (instancetype)reportWithID:(NSInteger)reportID byteIndex:(NSInteger)byteIndex bitMask:(uint8_t)bitMask {
    APBJabraSignal *signal = [[self alloc] init];
    signal->_kind = APBJabraSignalKindReport;
    signal->_reportID = reportID;
    signal->_byteIndex = byteIndex;
    signal->_bitMask = bitMask;
    return signal;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBJabraSignal.class]) return NO;
    APBJabraSignal *other = object;
    return _kind == other.kind && _page == other.page && _usage == other.usage
        && _linkedValue == other.linkedValue && _reportID == other.reportID
        && _byteIndex == other.byteIndex && _bitMask == other.bitMask;
}

- (NSUInteger)hash {
    return (NSUInteger)(_kind ^ _page ^ _usage ^ _reportID);
}

@end

@implementation APBJabraProfile

- (instancetype)initWithIdentifier:(APBJabraProfileID)identifier
                           product:(NSString *)product
                            signal:(APBJabraSignal *)signal {
    if ((self = [super init])) {
        _identifier = identifier;
        _product = [product copy];
        _signal = signal;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBJabraProfile.class]) return NO;
    APBJabraProfile *other = object;
    return _identifier == other.identifier
        && [_product isEqualToString:other.product]
        && [_signal isEqual:other.signal];
}

- (NSUInteger)hash {
    return _product.hash;
}

@end

static NSString *const DongleFamily = @"Jabra Link";

@implementation APBJabraLink

+ (NSInteger)vendorID {
    return 0x0b0e;
}

+ (NSArray<APBJabraProfile *> *)profiles {
    static NSArray<APBJabraProfile *> *profiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        profiles = @[
            [[APBJabraProfile alloc] initWithIdentifier:APBJabraProfileIDLink380
                                                product:@"Jabra Link 380"
                                                 signal:[APBJabraSignal elementWithPage:0xff30
                                                                                  usage:0xfffc
                                                                            linkedValue:0]],
            // Report 0x04 byte 1 bit 3 comes from hardware research in
            // tobi/AudioPriorityBar#32. Local Link 390 verification is still
            // pending; unreadable monitoring must remain fail-open.
            [[APBJabraProfile alloc] initWithIdentifier:APBJabraProfileIDLink390
                                                product:@"Jabra Link 390"
                                                 signal:[APBJabraSignal reportWithID:0x04
                                                                           byteIndex:1
                                                                             bitMask:0x08]],
        ];
    });
    return profiles;
}

+ (APBJabraProfile *)profileMatching:(NSString *)name {
    for (APBJabraProfile *profile in self.profiles) {
        if ([name rangeOfString:profile.product options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return profile;
        }
    }
    return nil;
}

+ (BOOL)isDongleProduct:(NSString *)name {
    return [name rangeOfString:DongleFamily options:NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (NSString *)serialFromAudioUID:(NSString *)uid {
    if (![uid hasPrefix:@"AppleUSBAudioEngine:"]) return nil;
    NSArray<NSString *> *parts = [uid componentsSeparatedByString:@":"];
    if (parts.count < 5) return nil;
    NSString *serial = parts[parts.count - 2];
    return serial.length > 0 ? serial : nil;
}

+ (BOOL)serial:(NSString *)left matches:(NSString *)right {
    return [left caseInsensitiveCompare:right] == NSOrderedSame;
}

+ (BOOL)decodeElementValue:(NSInteger)value linkedValue:(NSInteger)linkedValue {
    return value == linkedValue;
}

+ (NSNumber *)snapshotValue:(NSInteger)value
                  timestamp:(uint64_t)timestamp
                linkedValue:(NSInteger)linkedValue {
    if (timestamp == 0) return nil;
    return @([self decodeElementValue:value linkedValue:linkedValue]);
}

+ (NSNumber *)decodeReportID:(NSInteger)reportID
                  expectedID:(NSInteger)expectedID
                       bytes:(NSData *)bytes
                   byteIndex:(NSInteger)byteIndex
                     bitMask:(uint8_t)bitMask {
    if (reportID != expectedID || byteIndex < 0 || (NSUInteger)byteIndex >= bytes.length) {
        return nil;
    }
    const uint8_t *raw = bytes.bytes;
    return @((raw[byteIndex] & bitMask) != 0);
}

+ (BOOL)allowsSelectionIsSupported:(BOOL)isSupported state:(APBLinkState)state {
    if (!isSupported) return YES;
    // Unknown still fails open, because monitoring may be unavailable for
    // perfectly good devices. `checking` is different: an authoritative
    // answer is milliseconds away, so acting now risks routing audio to a
    // headset that is switched off.
    return state != APBLinkStateDown && state != APBLinkStateChecking;
}

@end

@implementation APBDebouncedLinkState

- (instancetype)init {
    return [self initWithObserved:nil effective:nil];
}

- (instancetype)initWithObserved:(NSNumber *)observed effective:(NSNumber *)effective {
    if ((self = [super init])) {
        _observed = observed;
        _effective = effective;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[APBDebouncedLinkState allocWithZone:zone] initWithObserved:_observed effective:_effective];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBDebouncedLinkState.class]) return NO;
    APBDebouncedLinkState *other = object;
    return (_observed == other.observed || [_observed isEqual:other.observed])
        && (_effective == other.effective || [_effective isEqual:other.effective]);
}

- (NSUInteger)hash {
    return _observed.hash ^ (_effective.hash << 1);
}

static BOOL Matches(NSNumber *value, BOOL flag) {
    return value != nil && value.boolValue == flag;
}

- (BOOL)seed:(BOOL)linked {
    _observed = @(linked);
    if (Matches(_effective, linked)) return NO;
    _effective = @(linked);
    return YES;
}

- (APBLinkTransition)observe:(BOOL)linked {
    if (Matches(_observed, linked)) return APBLinkTransitionUnchanged;
    BOOL cancellingDown = Matches(_observed, NO);
    _observed = @(linked);

    if (linked) {
        if (!Matches(_effective, YES)) {
            _effective = @YES;
            return APBLinkTransitionChanged;
        }
        return cancellingDown ? APBLinkTransitionCancelDown : APBLinkTransitionUnchanged;
    }
    return Matches(_effective, NO) ? APBLinkTransitionUnchanged : APBLinkTransitionScheduleDown;
}

- (BOOL)commitDown {
    if (!Matches(_observed, NO) || Matches(_effective, NO)) return NO;
    _effective = @NO;
    return YES;
}

@end
