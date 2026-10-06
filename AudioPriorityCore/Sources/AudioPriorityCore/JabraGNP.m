#import "JabraGNP.h"

const NSInteger APBGNPUsagePage = 0xff00;
const NSInteger APBGNPUsage = 0x01;
const uint8_t APBGNPCanonicalReportID = 0x05;
const NSInteger APBGNPMaximumFrameLength = 65;

const uint8_t APBGNPHostAddress = 0x00;
const uint8_t APBGNPDongleAddress = 0x01;
const uint8_t APBGNPKindMask = 0xc0;
const uint8_t APBGNPLengthMask = 0x3f;
const uint8_t APBGNPQueryKind = 0x40;
const uint8_t APBGNPReplyKind = 0xc0;
const uint8_t APBGNPEventKind = 0x00;
const NSInteger APBGNPHeaderLength = 6;

const uint8_t APBGNPPairingGroup = 0x0d;
const uint8_t APBGNPRecordOp = 0x28;
const uint8_t APBGNPConnectionEventOp = 0x26;
const uint8_t APBGNPConnectedState = 0x03;
const NSInteger APBGNPCursorLength = 2;
const NSInteger APBGNPRecordCap = 256;
const NSInteger APBGNPRecordMinimumLength = 12;
const NSInteger APBGNPRecordStateIndex = 2;

const uint8_t APBGNPHeadsetAddress = 0x04;
const uint8_t APBGNPStatusGroup = 0x12;
const uint8_t APBGNPBatteryOp = 0x02;

NSData *APBGNPEndCursor(void) {
    static const uint8_t bytes[] = {0xff, 0xff};
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}

NSData *APBGNPBluetoothTypes(void) {
    static const uint8_t bytes[] = {0x00, 0x01};
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}

static NSData *ZeroCursor(void) {
    return [NSMutableData dataWithLength:(NSUInteger)APBGNPCursorLength];
}

@implementation APBGNPElement

+ (instancetype)elementWithDirection:(APBGNPDirection)direction reportID:(uint8_t)reportID bits:(NSInteger)bits {
    APBGNPElement *element = [[self alloc] init];
    element->_direction = direction;
    element->_reportID = reportID;
    element->_bits = bits;
    return element;
}

@end

@implementation APBGNPLayout

- (instancetype)initWithInputReportID:(uint8_t)inputReportID
                       outputReportID:(uint8_t)outputReportID
                     inputFrameLength:(NSInteger)inputFrameLength
                    outputFrameLength:(NSInteger)outputFrameLength {
    if ((self = [super init])) {
        _inputReportID = inputReportID;
        _outputReportID = outputReportID;
        _inputFrameLength = inputFrameLength;
        _outputFrameLength = outputFrameLength;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:APBGNPLayout.class]) return NO;
    APBGNPLayout *other = object;
    return _inputReportID == other.inputReportID
        && _outputReportID == other.outputReportID
        && _inputFrameLength == other.inputFrameLength
        && _outputFrameLength == other.outputFrameLength;
}

- (NSUInteger)hash {
    return (NSUInteger)(_inputReportID << 8 | _outputReportID) ^ (NSUInteger)_inputFrameLength;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<APBGNPLayout in %u/%ld out %u/%ld>",
            _inputReportID, (long)_inputFrameLength, _outputReportID, (long)_outputFrameLength];
}

@end

@implementation APBGNPMessage

- (instancetype)initWithDestination:(uint8_t)destination
                             source:(uint8_t)source
                           sequence:(uint8_t)sequence
                               kind:(uint8_t)kind
                              group:(uint8_t)group
                                 op:(uint8_t)op
                          arguments:(NSData *)arguments {
    if ((self = [super init])) {
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
    return _destination == other.destination && _source == other.source
        && _sequence == other.sequence && _kind == other.kind
        && _group == other.group && _op == other.op
        && [_arguments isEqualToData:other.arguments];
}

- (NSUInteger)hash {
    return (NSUInteger)(_sequence << 16 | _group << 8 | _op) ^ _arguments.hash;
}

@end

@implementation APBGNPReassembler {
    NSMutableData *_body;
}

- (instancetype)init {
    if ((self = [super init])) _body = [NSMutableData data];
    return self;
}

- (NSData *)feed:(NSData *)chunk {
    [_body appendData:chunk];
    // The declared length lives in the fourth header byte.
    if (_body.length <= 3) return nil;
    const uint8_t *bytes = _body.bytes;
    NSInteger declared = bytes[3] & APBGNPLengthMask;
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
    if (_isFinished != other.isFinished) return NO;
    if (_isFinished) return _evidence == other.evidence;
    return [_cursor isEqualToData:other.cursor] && _bluetoothType == other.bluetoothType;
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
    return [self initWithBluetoothTypes:APBGNPBluetoothTypes() cap:APBGNPRecordCap];
}

- (instancetype)initWithBluetoothTypes:(NSData *)bluetoothTypes cap:(NSInteger)cap {
    if ((self = [super init])) {
        _bluetoothTypes = [bluetoothTypes copy];
        _cap = cap;
        _cursor = ZeroCursor();
        _seen = [NSMutableSet set];
    }
    return self;
}

- (uint8_t)currentType {
    return ((const uint8_t *)_bluetoothTypes.bytes)[_typeIndex];
}

- (APBGNPStep *)start {
    if (_typeIndex >= _bluetoothTypes.length) {
        return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    }
    return [APBGNPStep queryWithCursor:_cursor bluetoothType:self.currentType];
}

- (APBGNPStep *)acceptRecord:(NSData *)arguments {
    if (_typeIndex >= _bluetoothTypes.length
        || (NSInteger)arguments.length < APBGNPRecordMinimumLength) {
        return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    }
    const uint8_t *bytes = arguments.bytes;
    if (bytes[APBGNPRecordStateIndex] == APBGNPConnectedState) {
        return [APBGNPStep finished:APBGNPEvidenceConnected];
    }
    _visited += 1;
    if (_visited >= _cap) return [APBGNPStep finished:APBGNPEvidenceInconclusive];
    NSData *next = [arguments subdataWithRange:NSMakeRange(0, (NSUInteger)APBGNPCursorLength)];
    if ([next isEqualToData:APBGNPEndCursor()]
        || [next isEqualToData:_cursor]
        || [_seen containsObject:next]) {
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
    if (_typeIndex >= _bluetoothTypes.length) {
        return [APBGNPStep finished:APBGNPEvidenceDisconnected];
    }
    _cursor = ZeroCursor();
    [_seen removeAllObjects];
    _visited = 0;
    return [APBGNPStep queryWithCursor:_cursor bluetoothType:self.currentType];
}

@end

@implementation APBJabraGNP

+ (NSData *)recordArgumentsWithCursor:(NSData *)cursor bluetoothType:(uint8_t)bluetoothType {
    NSMutableData *arguments = [cursor mutableCopy];
    [arguments appendBytes:&bluetoothType length:1];
    return arguments;
}

+ (APBGNPLayout *)selectLayout:(NSArray<APBGNPElement *> *)elements {
    BOOL hasInput = NO, hasOutput = NO;
    uint8_t inputID = 0, outputID = 0;
    NSInteger inputLength = 0, outputLength = 0;
    for (APBGNPElement *element in elements) {
        if (element.reportID == 0 || element.bits <= 0 || element.bits % 8 != 0) continue;
        NSInteger length = element.bits / 8;
        if (length < APBGNPHeaderLength || length + 1 > APBGNPMaximumFrameLength) continue;
        if (element.direction == APBGNPDirectionInput) {
            if (hasInput && (inputID != element.reportID || inputLength != length)) return nil;
            hasInput = YES;
            inputID = element.reportID;
            inputLength = length;
        } else {
            if (hasOutput && (outputID != element.reportID || outputLength != length)) return nil;
            hasOutput = YES;
            outputID = element.reportID;
            outputLength = length;
        }
    }
    if (!hasInput || !hasOutput) return nil;
    return [[APBGNPLayout alloc] initWithInputReportID:inputID
                                        outputReportID:outputID
                                      inputFrameLength:inputLength
                                     outputFrameLength:outputLength];
}

+ (NSData *)encodeQueryWithDestination:(uint8_t)destination
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
    [body increaseLengthBy:(NSUInteger)(frameLength - (NSInteger)body.length)];
    return body;
}

+ (NSData *)encodeQueryWithSequence:(uint8_t)sequence
                              group:(uint8_t)group
                                 op:(uint8_t)op
                          arguments:(NSData *)arguments
                        frameLength:(NSInteger)frameLength {
    return [self encodeQueryWithDestination:APBGNPDongleAddress
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
    NSRange arguments = NSMakeRange((NSUInteger)APBGNPHeaderLength,
                                    (NSUInteger)(declared - APBGNPHeaderLength));
    return [[APBGNPMessage alloc] initWithDestination:bytes[0]
                                               source:bytes[1]
                                             sequence:bytes[2]
                                                 kind:bytes[3] & APBGNPKindMask
                                                group:bytes[4]
                                                   op:bytes[5]
                                            arguments:[body subdataWithRange:arguments]];
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

+ (NSNumber *)batteryLevel:(APBGNPMessage *)message {
    const uint8_t *arguments = message.arguments.bytes;
    if (message.destination != APBGNPHostAddress
        || message.source != APBGNPHeadsetAddress
        || (message.kind != APBGNPReplyKind && message.kind != APBGNPEventKind)
        || message.group != APBGNPStatusGroup
        || message.op != APBGNPBatteryOp
        || message.arguments.length < 2
        || arguments[1] > 100) {
        return nil;
    }
    return @(arguments[1]);
}

+ (NSNumber *)resolveVendor:(APBGNPEvidence)vendor legacy:(NSNumber *)legacy {
    switch (vendor) {
        case APBGNPEvidenceConnected: return @YES;
        case APBGNPEvidenceDisconnected: return @NO;
        case APBGNPEvidenceInconclusive:
        case APBGNPEvidenceNone: return legacy;
    }
    return legacy;
}

@end
