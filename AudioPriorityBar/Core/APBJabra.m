#import "APBJabra.h"

@implementation APBGNPMessage

- (instancetype)initWithDestination:(uint8_t)destination
                             source:(uint8_t)source
                           sequence:(uint8_t)sequence
                               kind:(uint8_t)kind
                              group:(uint8_t)group
                                 op:(uint8_t)op
                          arguments:(NSData *)arguments {
    self = [super init];
    if (self) {
        _destination = destination;
        _source = source;
        _sequence = sequence;
        _kind = kind;
        _group = group;
        _op = op;
        _arguments = [arguments copy];
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBGNPMessage.class]) return NO;
    APBGNPMessage *other = object;
    return _destination == other->_destination && _source == other->_source
        && _sequence == other->_sequence && _kind == other->_kind
        && _group == other->_group && _op == other->_op
        && [_arguments isEqualToData:other->_arguments];
}

- (NSUInteger)hash {
    return (NSUInteger)_sequence ^ ((NSUInteger)_op << 8) ^ _arguments.hash;
}

@end

@implementation APBJabraGNP

+ (NSData *)endCursor {
    static const uint8_t bytes[] = { 0xff, 0xff };
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}

+ (NSData *)bluetoothTypes {
    static const uint8_t bytes[] = { 0x00, 0x01 };
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}

+ (NSData *)recordArgumentsWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType {
    NSMutableData *arguments = [cursor mutableCopy];
    [arguments appendBytes:&bluetoothType length:1];
    return arguments;
}

+ (BOOL)selectLayoutFromElements:(const APBGNPElement *)elements
                           count:(NSUInteger)count
                          layout:(APBGNPLayout *)layout {
    BOOL hasInput = NO, hasOutput = NO;
    uint8_t inputID = 0, outputID = 0;
    NSInteger inputLength = 0, outputLength = 0;
    for (NSUInteger index = 0; index < count; index++) {
        APBGNPElement element = elements[index];
        if (element.reportID == 0 || element.bits <= 0 || element.bits % 8 != 0) continue;
        NSInteger length = element.bits / 8;
        if (length < APBGNPHeaderLength || length + 1 > APBGNPMaximumFrameLength) continue;
        if (element.isOutput) {
            if (hasOutput && (outputID != element.reportID || outputLength != length)) return NO;
            hasOutput = YES;
            outputID = element.reportID;
            outputLength = length;
        } else {
            if (hasInput && (inputID != element.reportID || inputLength != length)) return NO;
            hasInput = YES;
            inputID = element.reportID;
            inputLength = length;
        }
    }
    if (!hasInput || !hasOutput) return NO;
    if (layout) {
        *layout = (APBGNPLayout){
            .inputReportID = inputID,
            .outputReportID = outputID,
            .inputFrameLength = inputLength,
            .outputFrameLength = outputLength,
        };
    }
    return YES;
}

+ (NSData *)encodeQueryToDestination:(uint8_t)destination
                            sequence:(uint8_t)sequence
                               group:(uint8_t)group
                                  op:(uint8_t)op
                           arguments:(NSData *)arguments
                         frameLength:(NSInteger)frameLength {
    NSInteger declared = APBGNPHeaderLength + (NSInteger)arguments.length;
    if (declared > APBGNPLengthMask || declared > frameLength) return nil;
    uint8_t header[] = {
        destination,
        APBGNPHostAddress,
        sequence,
        (uint8_t)(APBGNPQueryKind | (uint8_t)declared),
        group,
        op,
    };
    NSMutableData *body = [NSMutableData dataWithBytes:header length:sizeof header];
    [body appendData:arguments];
    [body increaseLengthBy:(NSUInteger)frameLength - body.length];
    return body;
}

+ (NSData *)encodeQueryWithSequence:(uint8_t)sequence
                              group:(uint8_t)group
                                 op:(uint8_t)op
                          arguments:(NSData *)arguments
                        frameLength:(NSInteger)frameLength {
    return [self encodeQueryToDestination:APBGNPDongleAddress
                                 sequence:sequence
                                    group:group
                                       op:op
                                arguments:arguments
                              frameLength:frameLength];
}

+ (APBGNPMessage *)decode:(NSData *)body {
    if ((NSInteger)body.length < APBGNPHeaderLength) return nil;
    const uint8_t *bytes = body.bytes;
    NSInteger declared = bytes[3] & APBGNPLengthMask;
    if (declared < APBGNPHeaderLength || declared > (NSInteger)body.length) return nil;
    return [[APBGNPMessage alloc]
        initWithDestination:bytes[0]
                     source:bytes[1]
                   sequence:bytes[2]
                       kind:bytes[3] & APBGNPKindMask
                      group:bytes[4]
                         op:bytes[5]
                  arguments:[body subdataWithRange:NSMakeRange(APBGNPHeaderLength, (NSUInteger)(declared - APBGNPHeaderLength))]];
}

+ (BOOL)isReply:(APBGNPMessage *)message
       sequence:(uint8_t)sequence
          group:(uint8_t)group
             op:(uint8_t)op
         source:(uint8_t)source {
    return message.destination == APBGNPHostAddress
        && message.source == source
        && message.sequence == sequence
        && message.kind == APBGNPReplyKind
        && message.group == group
        && message.op == op;
}

+ (BOOL)isReply:(APBGNPMessage *)message sequence:(uint8_t)sequence group:(uint8_t)group op:(uint8_t)op {
    return [self isReply:message sequence:sequence group:group op:op source:APBGNPDongleAddress];
}

+ (BOOL)isConnectionEvent:(APBGNPMessage *)message {
    return message.destination == APBGNPHostAddress
        && message.source == APBGNPDongleAddress
        && message.kind == APBGNPEventKind
        && message.group == APBGNPPairingGroup
        && message.op == APBGNPConnectionEventOp;
}

+ (APBTriState)resolveVendor:(APBGNPEvidence)vendor legacy:(APBTriState)legacy {
    switch (vendor) {
        case APBGNPEvidenceConnected: return APBTriStateYes;
        case APBGNPEvidenceDisconnected: return APBTriStateNo;
        case APBGNPEvidenceInconclusive:
        case APBGNPEvidenceNone: return legacy;
    }
    return legacy;
}

@end

@implementation APBGNPReassembler {
    NSMutableData *_body;
}

- (instancetype)init {
    self = [super init];
    if (self) _body = [NSMutableData data];
    return self;
}

- (NSData *)feed:(NSData *)chunk {
    [_body appendData:chunk];
    // The declared length lives in the fourth header byte.
    if (_body.length <= 3) return nil;
    NSInteger declared = ((const uint8_t *)_body.bytes)[3] & APBGNPLengthMask;
    if (declared < APBGNPHeaderLength) {
        _body.length = 0;
        return nil;
    }
    if ((NSInteger)_body.length < declared) return nil;
    NSData *complete = [_body subdataWithRange:NSMakeRange(0, (NSUInteger)declared)];
    _body.length = 0;
    return complete;
}

- (void)reset {
    _body.length = 0;
}

@end

@implementation APBGNPStep

+ (instancetype)queryWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType {
    APBGNPStep *step = [[self alloc] init];
    step->_cursor = [cursor copy];
    step->_bluetoothType = bluetoothType;
    return step;
}

+ (instancetype)finished:(APBGNPEvidence)evidence {
    APBGNPStep *step = [[self alloc] init];
    step->_isFinished = YES;
    step->_evidence = evidence;
    return step;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBGNPStep.class]) return NO;
    APBGNPStep *other = object;
    if (_isFinished != other->_isFinished) return NO;
    if (_isFinished) return _evidence == other->_evidence;
    return [_cursor isEqualToData:other->_cursor] && _bluetoothType == other->_bluetoothType;
}

- (NSUInteger)hash {
    return _isFinished ? (NSUInteger)_evidence : _cursor.hash ^ _bluetoothType;
}

- (NSString *)description {
    if (_isFinished) return [NSString stringWithFormat:@"<finished %ld>", (long)_evidence];
    return [NSString stringWithFormat:@"<query %@ type %u>", _cursor, _bluetoothType];
}

@end

@implementation APBGNPPairingWalk {
    NSData *_bluetoothTypes;
    NSInteger _cap;
    NSUInteger _typeIndex;
    NSData *_cursor;
    NSMutableSet<NSData *> *_seen;
    NSInteger _visited;
}

- (instancetype)init {
    return [self initWithBluetoothTypes:APBJabraGNP.bluetoothTypes cap:APBGNPRecordCap];
}

- (instancetype)initWithBluetoothTypes:(NSData *)bluetoothTypes cap:(NSInteger)cap {
    self = [super init];
    if (self) {
        _bluetoothTypes = [bluetoothTypes copy];
        _cap = cap;
        _cursor = [NSMutableData dataWithLength:APBGNPCursorLength];
        _seen = [NSMutableSet set];
    }
    return self;
}

- (uint8_t)currentType {
    return ((const uint8_t *)_bluetoothTypes.bytes)[_typeIndex];
}

- (APBGNPStep *)start {
    if (_typeIndex >= _bluetoothTypes.length) return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    return [APBGNPStep queryWithCursor:_cursor bluetoothType:self.currentType];
}

- (APBGNPStep *)acceptRecord:(NSData *)arguments {
    if (_typeIndex >= _bluetoothTypes.length || (NSInteger)arguments.length < APBGNPRecordMinimumLength) {
        return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    }
    if (((const uint8_t *)arguments.bytes)[APBGNPRecordStateIndex] == APBGNPConnectedState) {
        return [APBGNPStep finished:APBGNPEvidenceConnected];
    }
    _visited += 1;
    if (_visited >= _cap) return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    NSData *next = [arguments subdataWithRange:NSMakeRange(0, APBGNPCursorLength)];
    if ([next isEqualToData:APBJabraGNP.endCursor] || [next isEqualToData:_cursor] || [_seen containsObject:next]) {
        return [self advanceDatabase];
    }
    [_seen addObject:_cursor];
    _cursor = next;
    return [APBGNPStep queryWithCursor:_cursor bluetoothType:self.currentType];
}

- (APBGNPStep *)fail {
    return [APBGNPStep finished:APBGNPEvidenceInconclusive];
}

- (APBGNPStep *)advanceDatabase {
    _typeIndex += 1;
    if (_typeIndex >= _bluetoothTypes.length) return [APBGNPStep finished:APBGNPEvidenceDisconnected];
    _cursor = [NSMutableData dataWithLength:APBGNPCursorLength];
    [_seen removeAllObjects];
    _visited = 0;
    return [APBGNPStep queryWithCursor:_cursor bluetoothType:self.currentType];
}

@end

@interface APBJabraProfile ()
@property (nonatomic, readwrite) APBJabraProfileID profileID;
@property (nonatomic, readwrite, copy) NSString *product;
@property (nonatomic, readwrite) APBJabraSignalKind signalKind;
@property (nonatomic, readwrite) NSInteger page;
@property (nonatomic, readwrite) NSInteger usage;
@property (nonatomic, readwrite) NSInteger linkedValue;
@property (nonatomic, readwrite) NSInteger reportID;
@property (nonatomic, readwrite) NSInteger byteIndex;
@property (nonatomic, readwrite) uint8_t bitMask;
@end

@implementation APBJabraProfile
@end

static NSString *const DongleFamily = @"Jabra Link";

@implementation APBJabraLink

+ (NSInteger)vendorID {
    return 0x0b0e;
}

+ (NSArray<APBJabraProfile *> *)profiles {
    static NSArray *profiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        APBJabraProfile *link380 = [[APBJabraProfile alloc] init];
        link380.profileID = APBJabraProfileIDLink380;
        link380.product = @"Jabra Link 380";
        link380.signalKind = APBJabraSignalKindElement;
        link380.page = 0xff30;
        link380.usage = 0xfffc;
        link380.linkedValue = 0;

        // Report 0x04 byte 1 bit 3 comes from hardware research in
        // tobi/AudioPriorityBar#32. Local Link 390 verification is still
        // pending; unreadable monitoring must remain fail-open.
        APBJabraProfile *link390 = [[APBJabraProfile alloc] init];
        link390.profileID = APBJabraProfileIDLink390;
        link390.product = @"Jabra Link 390";
        link390.signalKind = APBJabraSignalKindReport;
        link390.reportID = 0x04;
        link390.byteIndex = 1;
        link390.bitMask = 0x08;

        profiles = @[ link380, link390 ];
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
    return serial.length == 0 ? nil : serial;
}

+ (BOOL)serial:(NSString *)left matches:(NSString *)right {
    return [left caseInsensitiveCompare:right] == NSOrderedSame;
}

+ (BOOL)decodeElementValue:(NSInteger)value linkedValue:(NSInteger)linkedValue {
    return value == linkedValue;
}

+ (APBTriState)snapshotValue:(NSInteger)value timestamp:(uint64_t)timestamp linkedValue:(NSInteger)linkedValue {
    if (timestamp == 0) return APBTriStateUnknown;
    return APBTriStateFromBool([self decodeElementValue:value linkedValue:linkedValue]);
}

+ (APBTriState)decodeReportID:(NSInteger)reportID
                   expectedID:(NSInteger)expectedID
                        bytes:(NSData *)bytes
                    byteIndex:(NSInteger)byteIndex
                      bitMask:(uint8_t)bitMask {
    if (reportID != expectedID || byteIndex < 0 || byteIndex >= (NSInteger)bytes.length) {
        return APBTriStateUnknown;
    }
    return APBTriStateFromBool((((const uint8_t *)bytes.bytes)[byteIndex] & bitMask) != 0);
}

+ (BOOL)allowsSelectionWhenSupported:(BOOL)isSupported state:(APBLinkState)state {
    if (!isSupported) return YES;
    // Unknown still fails open, because monitoring may be unavailable for
    // perfectly good devices. `Checking` is different: an authoritative answer
    // is milliseconds away, so acting now risks routing audio to a headset
    // that is switched off.
    return state != APBLinkStateDown && state != APBLinkStateChecking;
}

@end

@implementation APBDebouncedLinkState

- (instancetype)init {
    return [self initWithObserved:APBTriStateUnknown effective:APBTriStateUnknown];
}

- (instancetype)initWithObserved:(APBTriState)observed effective:(APBTriState)effective {
    self = [super init];
    if (self) {
        _observed = observed;
        _effective = effective;
    }
    return self;
}

- (BOOL)seed:(BOOL)linked {
    APBTriState value = APBTriStateFromBool(linked);
    _observed = value;
    if (_effective == value) return NO;
    _effective = value;
    return YES;
}

- (APBLinkTransition)observe:(BOOL)linked {
    APBTriState value = APBTriStateFromBool(linked);
    if (_observed == value) return APBLinkTransitionUnchanged;
    BOOL cancellingDown = _observed == APBTriStateNo;
    _observed = value;

    if (linked) {
        if (_effective != APBTriStateYes) {
            _effective = APBTriStateYes;
            return APBLinkTransitionChanged;
        }
        return cancellingDown ? APBLinkTransitionCancelDown : APBLinkTransitionUnchanged;
    }
    return _effective == APBTriStateNo ? APBLinkTransitionUnchanged : APBLinkTransitionScheduleDown;
}

- (BOOL)commitDown {
    if (_observed != APBTriStateNo || _effective == APBTriStateNo) return NO;
    _effective = APBTriStateNo;
    return YES;
}

@end
