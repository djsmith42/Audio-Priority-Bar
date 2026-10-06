#import <XCTest/XCTest.h>
#import "AudioPriorityCore.h"

// Byte sequences below were captured from a Jabra Link 380 (PID 0x24ca)
// paired with an Evolve2 85. Frames are shown as canonical bodies, meaning the
// physical HID report ID has already been stripped.

#define BYTES(...) ({ \
    const uint8_t bytes_[] = {__VA_ARGS__}; \
    [NSData dataWithBytes:bytes_ length:sizeof bytes_]; \
})

static NSData *Zeros(NSUInteger count) {
    return [NSMutableData dataWithLength:count];
}

static NSData *Join(NSData *first, NSData *second) {
    NSMutableData *joined = [first mutableCopy];
    [joined appendData:second];
    return joined;
}

/// Link 380 management collection: report 5 in both directions, 63 body bytes.
static NSArray<APBGNPElement *> *Link380Elements(void) {
    return @[
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:5 bits:504],
        [APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:5 bits:504],
    ];
}

/// Record reply for the connected Evolve2 85: cursor 00 01, state 03.
static NSData *ConnectedRecord(void) {
    return BYTES(0x00, 0x01, 0x03, 0x00, 0x04, 0x11,
                 0x70, 0xbf, 0x92, 0xf4, 0x2f, 0xb8,
                 0x04, 0x01, 0x67, 0x00);
}

/// Record reply for a remembered but disconnected device: state 01.
static NSData *DisconnectedRecord(void) {
    return BYTES(0x00, 0x02, 0x01, 0x00, 0x00, 0x11,
                 0x20, 0x64, 0xde, 0xca, 0x65, 0x75,
                 0xff, 0xfc, 0xff, 0x00);
}

/// Final record in a database: the cursor terminates the walk.
static NSData *LastRecord(void) {
    return BYTES(0xff, 0xff, 0x01, 0x00, 0x00, 0x11,
                 0x7b, 0x86, 0x95, 0xd3, 0x10, 0x3a,
                 0xff, 0xfc, 0xff, 0x00);
}

/// Canonical reply body for `ConnectedRecord`: six header bytes plus sixteen
/// argument bytes, so the declared length is 22 (0xc0 | 0x16 == 0xd6).
static NSData *ConnectedReplyBody(void) {
    return Join(BYTES(0x00, 0x01, 0x12, 0xd6, 0x0d, 0x28), ConnectedRecord());
}

static NSData *Padded(NSData *body, NSUInteger length) {
    return Join(body, Zeros(length - body.length));
}

@interface JabraGNPTests : XCTestCase
@end

@implementation JabraGNPTests

- (void)testLayoutComesFromTheDescriptorRatherThanAHardCodedReportID {
    APBGNPLayout *layout = [APBJabraGNP selectLayout:Link380Elements()];
    XCTAssertNotNil(layout);
    XCTAssertEqual(layout.inputReportID, 5);
    XCTAssertEqual(layout.outputReportID, 5);
    XCTAssertEqual(layout.outputFrameLength, 63);

    // A dongle numbering its management reports differently is still usable.
    APBGNPLayout *relocated = [APBJabraGNP selectLayout:@[
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:9 bits:256],
        [APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:8 bits:256],
    ]];
    XCTAssertNotNil(relocated);
    XCTAssertEqual(relocated.inputReportID, 9);
    XCTAssertEqual(relocated.outputReportID, 8);
    XCTAssertEqual(relocated.outputFrameLength, 32);
}

- (void)testLayoutRejectsUnusableOrAmbiguousCollections {
    // Only one direction present.
    XCTAssertNil([APBJabraGNP selectLayout:@[Link380Elements()[0]]]);
    // Report ID 0 is not a numbered report.
    XCTAssertNil(([APBJabraGNP selectLayout:@[
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:0 bits:504],
        [APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:0 bits:504],
    ]]));
    // Too small to carry a header.
    XCTAssertNil(([APBJabraGNP selectLayout:@[
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:5 bits:8],
        [APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:5 bits:8],
    ]]));
    // Not byte aligned.
    XCTAssertNil(([APBJabraGNP selectLayout:@[
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:5 bits:12],
        [APBGNPElement elementWithDirection:APBGNPDirectionOutput reportID:5 bits:12],
    ]]));
    // Two different input reports is ambiguous, so fall back instead.
    XCTAssertNil(([APBJabraGNP selectLayout:[Link380Elements() arrayByAddingObject:
        [APBGNPElement elementWithDirection:APBGNPDirectionInput reportID:7 bits:504]]]));
}

- (void)testEncodedQueryMatchesTheBytesTheVendorStackSends {
    NSData *arguments = [APBJabraGNP recordArgumentsWithCursor:BYTES(0x00, 0x00) bluetoothType:0];
    NSData *body = [APBJabraGNP encodeQueryWithSequence:0x12
                                                  group:APBGNPPairingGroup
                                                     op:APBGNPRecordOp
                                              arguments:arguments
                                            frameLength:63];
    XCTAssertNotNil(body);
    // destination 01, host 00, sequence 12, query|length 49, class 0d, op 28.
    XCTAssertEqualObjects([body subdataWithRange:NSMakeRange(0, MIN(body.length, 9))],
                          BYTES(0x01, 0x00, 0x12, 0x49, 0x0d, 0x28, 0x00, 0x00, 0x00));
    XCTAssertEqual(body.length, 63);
    XCTAssertEqualObjects([body subdataWithRange:NSMakeRange(9, body.length - 9)], Zeros(63 - 9));
}

- (void)testEncodedQueryRefusesArgumentsThatWouldNotFitOneFrame {
    XCTAssertNil([APBJabraGNP encodeQueryWithSequence:1
                                                group:APBGNPPairingGroup
                                                   op:APBGNPRecordOp
                                            arguments:Zeros(4)
                                          frameLength:8]);
    XCTAssertNil([APBJabraGNP encodeQueryWithSequence:1
                                                group:APBGNPPairingGroup
                                                   op:APBGNPRecordOp
                                            arguments:Zeros(64)
                                          frameLength:63]);
}

- (void)testDecodeReadsTheDeclaredLengthAndIgnoresTrailingPadding {
    NSData *body = Padded(ConnectedReplyBody(), 63);
    APBGNPMessage *message = [APBJabraGNP decode:body];
    XCTAssertNotNil(message);
    XCTAssertEqual(message.destination, APBGNPHostAddress);
    XCTAssertEqual(message.source, APBGNPDongleAddress);
    XCTAssertEqual(message.sequence, 0x12);
    XCTAssertEqual(message.kind, APBGNPReplyKind);
    XCTAssertEqual(message.group, APBGNPPairingGroup);
    XCTAssertEqual(message.op, APBGNPRecordOp);
    XCTAssertEqualObjects(message.arguments, ConnectedRecord());
}

- (void)testDecodeRejectsShortAndInconsistentBodies {
    XCTAssertNil([APBJabraGNP decode:BYTES(0x00, 0x01, 0x12)]);
    // Declared length below the header size.
    XCTAssertNil([APBJabraGNP decode:BYTES(0x00, 0x01, 0x12, 0xc3, 0x0d, 0x28)]);
    // Declares more bytes than were received.
    XCTAssertNil([APBJabraGNP decode:BYTES(0x00, 0x01, 0x12, 0xd6, 0x0d, 0x28)]);
}

- (void)testReplyMatchingRejectsStaleRepliesAndUnsolicitedEvents {
    APBGNPMessage *reply = [[APBGNPMessage alloc] initWithDestination:APBGNPHostAddress
                                                               source:APBGNPDongleAddress
                                                             sequence:0x12
                                                                 kind:APBGNPReplyKind
                                                                group:APBGNPPairingGroup
                                                                   op:APBGNPRecordOp
                                                            arguments:ConnectedRecord()];
    const uint8_t sequence = 0x12;
    const uint8_t group = APBGNPPairingGroup;
    const uint8_t op = APBGNPRecordOp;
    XCTAssertTrue([APBJabraGNP isReply:reply sequence:sequence group:group op:op]);
    // A different sequence is a stale reply from an earlier attempt.
    XCTAssertFalse([APBJabraGNP isReply:reply sequence:0x13 group:group op:op]);
    // Wrong opcode.
    XCTAssertFalse([APBJabraGNP isReply:reply sequence:sequence group:group op:0x32]);

    // The connection-state notification uses the same class and opcode space
    // but is an event, not an answer to our query.
    APBGNPMessage *event = [[APBGNPMessage alloc] initWithDestination:APBGNPHostAddress
                                                               source:APBGNPDongleAddress
                                                             sequence:0x12
                                                                 kind:APBGNPEventKind
                                                                group:APBGNPPairingGroup
                                                                   op:APBGNPRecordOp
                                                            arguments:ConnectedRecord()];
    XCTAssertFalse([APBJabraGNP isReply:event sequence:sequence group:group op:op]);
}

- (void)testConnectionAnnouncementsAreRecognisedButNeverTreatedAsAnswers {
    // Captured from a Link 380 about 100ms after an Evolve2 85 was powered
    // off, while a walk for sequence 0x0d was outstanding.
    NSData *announcement = BYTES(0x00, 0x01, 0xae, 0x11, 0x0d, 0x26,
                                 0x01, 0x70, 0xbf, 0x92, 0xf4, 0x2f, 0xb8, 0x01, 0x00, 0x04, 0xff);
    APBGNPMessage *message = [APBJabraGNP decode:announcement];
    XCTAssertNotNil(message);
    if (!message) return;
    XCTAssertEqual(message.kind, APBGNPEventKind);
    XCTAssertTrue([APBJabraGNP isConnectionEvent:message]);
    // It must not be mistaken for a record, whatever we are waiting for.
    XCTAssertFalse([APBJabraGNP isReply:message
                               sequence:0xae
                                  group:APBGNPPairingGroup
                                     op:APBGNPRecordOp]);

    // A record reply is not an announcement, so a walk cannot retrigger itself.
    APBGNPMessage *reply = [APBJabraGNP decode:ConnectedReplyBody()];
    XCTAssertNotNil(reply);
    if (!reply) return;
    XCTAssertFalse([APBJabraGNP isConnectionEvent:reply]);
}

- (void)testReassemblerJoinsFragmentedRepliesAndDropsGarbage {
    APBGNPReassembler *reassembler = [[APBGNPReassembler alloc] init];
    NSData *body = ConnectedReplyBody();
    // Split across two physical frames.
    XCTAssertNil([reassembler feed:[body subdataWithRange:NSMakeRange(0, 5)]]);
    XCTAssertEqualObjects([reassembler feed:[body subdataWithRange:NSMakeRange(5, body.length - 5)]], body);

    // A single frame carrying padding yields only the declared bytes.
    NSData *padded = Padded(body, 63);
    XCTAssertEqualObjects([reassembler feed:padded], body);

    // An implausible declared length is discarded rather than buffered.
    XCTAssertNil([reassembler feed:BYTES(0x00, 0x01, 0x12, 0xc0)]);
    XCTAssertEqualObjects([reassembler feed:padded], body);
}

- (void)testWalkProvesConnectedFromTheFirstConnectedRecord {
    APBGNPPairingWalk *walk = [[APBGNPPairingWalk alloc] init];
    XCTAssertEqualObjects([walk start], [APBGNPStep queryWithCursor:BYTES(0x00, 0x00) bluetoothType:0x00]);
    XCTAssertEqualObjects([walk acceptRecord:ConnectedRecord()], [APBGNPStep finished:APBGNPEvidenceConnected]);
}

- (void)testWalkProvesDisconnectedOnlyAfterEveryDatabaseTerminates {
    APBGNPPairingWalk *walk = [[APBGNPPairingWalk alloc] init];
    XCTAssertEqualObjects([walk start], [APBGNPStep queryWithCursor:BYTES(0x00, 0x00) bluetoothType:0x00]);
    // Cursor advances using the bytes the dongle returned, opaquely.
    XCTAssertEqualObjects([walk acceptRecord:DisconnectedRecord()],
                          [APBGNPStep queryWithCursor:BYTES(0x00, 0x02) bluetoothType:0x00]);
    // Terminating the first database moves to the second, not to a verdict.
    XCTAssertEqualObjects([walk acceptRecord:LastRecord()],
                          [APBGNPStep queryWithCursor:BYTES(0x00, 0x00) bluetoothType:0x01]);
    XCTAssertEqualObjects([walk acceptRecord:LastRecord()], [APBGNPStep finished:APBGNPEvidenceDisconnected]);
}

- (void)testWalkStaysInconclusiveOnPartialEvidence {
    // A timeout mid-walk must never be read as "headset off".
    APBGNPPairingWalk *timedOut = [[APBGNPPairingWalk alloc] init];
    [timedOut start];
    XCTAssertEqualObjects([timedOut fail], [APBGNPStep finished:APBGNPEvidenceInconclusive]);

    // A truncated record is not evidence either.
    APBGNPPairingWalk *malformed = [[APBGNPPairingWalk alloc] init];
    [malformed start];
    XCTAssertEqualObjects([malformed acceptRecord:BYTES(0x00, 0x01, 0x01)],
                          [APBGNPStep finished:APBGNPEvidenceInconclusive]);

    // A repeated cursor ends that database rather than looping forever.
    APBGNPPairingWalk *cyclic = [[APBGNPPairingWalk alloc] init];
    [cyclic start];
    NSData *selfReferential = BYTES(0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    XCTAssertEqualObjects([cyclic acceptRecord:selfReferential],
                          [APBGNPStep queryWithCursor:BYTES(0x00, 0x00) bluetoothType:0x01]);

    // Exhausting the record cap is suspicious, so it proves nothing.
    APBGNPPairingWalk *runaway = [[APBGNPPairingWalk alloc] initWithBluetoothTypes:BYTES(0x00) cap:2];
    [runaway start];
    XCTAssertEqualObjects([runaway acceptRecord:DisconnectedRecord()],
                          [APBGNPStep queryWithCursor:BYTES(0x00, 0x02) bluetoothType:0x00]);
    XCTAssertEqualObjects([runaway acceptRecord:BYTES(0x00, 0x03, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0)],
                          [APBGNPStep finished:APBGNPEvidenceInconclusive]);
}

- (void)testCompleteVendorEvidenceOverridesTheUntrustworthyLegacyBit {
    // This is the reported bug: after a replug the legacy bit claims linked
    // while no headset is connected. Vendor evidence must win.
    XCTAssertEqualObjects([APBJabraGNP resolveVendor:APBGNPEvidenceDisconnected legacy:@YES], @NO);
    XCTAssertEqualObjects([APBJabraGNP resolveVendor:APBGNPEvidenceConnected legacy:@NO], @YES);
    // Without usable vendor evidence the legacy bit is the fallback.
    XCTAssertEqualObjects([APBJabraGNP resolveVendor:APBGNPEvidenceInconclusive legacy:@YES], @YES);
    XCTAssertEqualObjects([APBJabraGNP resolveVendor:APBGNPEvidenceNone legacy:@NO], @NO);
    XCTAssertNil([APBJabraGNP resolveVendor:APBGNPEvidenceInconclusive legacy:nil]);
    XCTAssertNil([APBJabraGNP resolveVendor:APBGNPEvidenceNone legacy:nil]);
}

- (void)testHeadsetBatteryIsReadFromItsReplyOrUnaskedUpdate {
    // The Evolve2 85's reply to a battery query, captured at 95%: flags 24,
    // level 5f.
    APBGNPMessage *reply = [APBJabraGNP decode:BYTES(0x00, 0x04, 0x7a, 0xca, 0x12, 0x02, 0x24, 0x5f, 0x10, 0x23)];
    XCTAssertNotNil(reply);
    if (!reply) return;
    XCTAssertEqualObjects([APBJabraGNP batteryLevel:reply], @95);

    // The same message sent unasked carries an event kind.
    APBGNPMessage *update = [APBJabraGNP decode:BYTES(0x00, 0x04, 0x00, 0x0a, 0x12, 0x02, 0x24, 0x40, 0x10, 0x23)];
    XCTAssertNotNil(update);
    if (!update) return;
    XCTAssertEqualObjects([APBJabraGNP batteryLevel:update], @64);

    // From the dongle rather than the headset, or out of range.
    APBGNPMessage *fromDongle = [APBJabraGNP decode:BYTES(0x00, 0x01, 0x7a, 0xca, 0x12, 0x02, 0x24, 0x5f, 0x10, 0x23)];
    XCTAssertNotNil(fromDongle);
    if (!fromDongle) return;
    XCTAssertNil([APBJabraGNP batteryLevel:fromDongle]);
    APBGNPMessage *invalid = [APBJabraGNP decode:BYTES(0x00, 0x04, 0x7a, 0xca, 0x12, 0x02, 0x24, 0xe6, 0x10, 0x23)];
    XCTAssertNotNil(invalid);
    if (!invalid) return;
    XCTAssertNil([APBJabraGNP batteryLevel:invalid]);
}

- (void)testAudioDeviceSerialBindsStateToOnePhysicalDongle {
    XCTAssertEqualObjects([APBJabraLink serialFromAudioUID:
                              @"AppleUSBAudioEngine:Unknown Manufacturer:Jabra Link 380:50C275445423:1"],
                          @"50C275445423");
    XCTAssertEqualObjects([APBJabraLink serialFromAudioUID:
                              @"AppleUSBAudioEngine:Unknown Manufacturer:Jabra Link 380:50C275445423:2"],
                          @"50C275445423");
    XCTAssertNil([APBJabraLink serialFromAudioUID:@"BuiltInSpeakerDevice"]);
    XCTAssertNil([APBJabraLink serialFromAudioUID:@"AppleUSBAudioEngine:a:b:c"]);
    XCTAssertTrue([APBJabraLink serial:@"50c275445423" matches:@"50C275445423"]);
    XCTAssertFalse([APBJabraLink serial:@"50C275445423" matches:@"70BF92F42FB8"]);
}

@end
