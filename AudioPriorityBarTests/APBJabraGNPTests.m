#import <XCTest/XCTest.h>
#import "APBJabra.h"

// Byte sequences below were captured from a Jabra Link 380 (PID 0x24ca)
// paired with an Evolve2 85. Frames are shown as canonical bodies, meaning the
// physical HID report ID has already been stripped.

/// Data from byte literals.
#define APBBytes(...) ({ const uint8_t _b[] = { __VA_ARGS__ }; [NSData dataWithBytes:_b length:sizeof _b]; })
/// Concatenation of two data blobs.
static NSData *APBJoin(NSData *head, NSData *tail) {
    NSMutableData *joined = [head mutableCopy];
    [joined appendData:tail];
    return joined;
}

@interface APBJabraGNPTests : XCTestCase
@end

@implementation APBJabraGNPTests

// Link 380 management collection: report 5 in both directions, 63 body bytes.
- (APBGNPElement *)link380Elements:(NSUInteger *)count {
    static APBGNPElement elements[2];
    elements[0] = (APBGNPElement){ .isOutput = NO, .reportID = 5, .bits = 504 };
    elements[1] = (APBGNPElement){ .isOutput = YES, .reportID = 5, .bits = 504 };
    if (count) *count = 2;
    return elements;
}

// Record reply for the connected Evolve2 85: cursor 00 01, state 03.
static NSData *APBConnectedRecord(void) {
    return APBBytes(0x00, 0x01, 0x03, 0x00, 0x04, 0x11,
                    0x70, 0xbf, 0x92, 0xf4, 0x2f, 0xb8,
                    0x04, 0x01, 0x67, 0x00);
}

// Record reply for a remembered but disconnected device: state 01.
static NSData *APBDisconnectedRecord(void) {
    return APBBytes(0x00, 0x02, 0x01, 0x00, 0x00, 0x11,
                    0x20, 0x64, 0xde, 0xca, 0x65, 0x75,
                    0xff, 0xfc, 0xff, 0x00);
}

// Final record in a database: the cursor terminates the walk.
static NSData *APBLastRecord(void) {
    return APBBytes(0xff, 0xff, 0x01, 0x00, 0x00, 0x11,
                    0x7b, 0x86, 0x95, 0xd3, 0x10, 0x3a,
                    0xff, 0xfc, 0xff, 0x00);
}

// Canonical reply body for the connected record: six header bytes plus sixteen
// argument bytes, so the declared length is 22 (0xc0 | 0x16 == 0xd6).
static NSData *APBConnectedReplyBody(void) {
    return APBJoin(APBBytes(0x00, 0x01, 0x12, 0xd6, 0x0d, 0x28), APBConnectedRecord());
}

- (void)testLayoutComesFromTheDescriptorRatherThanAHardCodedReportID {
    NSUInteger count = 0;
    APBGNPLayout layout;
    XCTAssertTrue([APBJabraGNP selectLayoutFromElements:[self link380Elements:&count] count:count layout:&layout]);
    XCTAssertEqual(layout.inputReportID, 5);
    XCTAssertEqual(layout.outputReportID, 5);
    XCTAssertEqual(layout.outputFrameLength, 63);

    // A dongle numbering its management reports differently is still usable.
    APBGNPElement relocatedElements[2] = {
        { .isOutput = NO, .reportID = 9, .bits = 256 },
        { .isOutput = YES, .reportID = 8, .bits = 256 },
    };
    APBGNPLayout relocated;
    XCTAssertTrue([APBJabraGNP selectLayoutFromElements:relocatedElements count:2 layout:&relocated]);
    XCTAssertEqual(relocated.inputReportID, 9);
    XCTAssertEqual(relocated.outputReportID, 8);
    XCTAssertEqual(relocated.outputFrameLength, 32);
}

- (void)testLayoutRejectsUnusableOrAmbiguousCollections {
    APBGNPLayout layout;

    // Only one direction present.
    APBGNPElement one[] = { { .isOutput = NO, .reportID = 5, .bits = 504 } };
    XCTAssertFalse([APBJabraGNP selectLayoutFromElements:one count:1 layout:&layout]);
    // Report ID 0 is not a numbered report.
    APBGNPElement zeroID[] = { { .isOutput = NO, .reportID = 0, .bits = 504 },
                              { .isOutput = YES, .reportID = 0, .bits = 504 } };
    XCTAssertFalse([APBJabraGNP selectLayoutFromElements:zeroID count:2 layout:&layout]);
    // Too small to carry a header.
    APBGNPElement tiny[] = { { .isOutput = NO, .reportID = 5, .bits = 8 },
                             { .isOutput = YES, .reportID = 5, .bits = 8 } };
    XCTAssertFalse([APBJabraGNP selectLayoutFromElements:tiny count:2 layout:&layout]);
    // Not byte aligned.
    APBGNPElement unaligned[] = { { .isOutput = NO, .reportID = 5, .bits = 12 },
                                 { .isOutput = YES, .reportID = 5, .bits = 12 } };
    XCTAssertFalse([APBJabraGNP selectLayoutFromElements:unaligned count:2 layout:&layout]);
    // Two different input reports is ambiguous, so fall back instead.
    APBGNPElement ambiguous[3] = { { .isOutput = NO, .reportID = 5, .bits = 504 },
                                   { .isOutput = YES, .reportID = 5, .bits = 504 },
                                   { .isOutput = NO, .reportID = 7, .bits = 504 } };
    XCTAssertFalse([APBJabraGNP selectLayoutFromElements:ambiguous count:3 layout:&layout]);
}

- (void)testEncodedQueryMatchesTheBytesTheVendorStackSends {
    NSData *arguments = [APBJabraGNP recordArgumentsWithCursor:APBBytes(0x00, 0x00) bluetoothType:0];
    NSData *body = [APBJabraGNP encodeQueryWithSequence:0x12
                                                   group:APBGNPPairingGroup
                                                     op:APBGNPRecordOp
                                              arguments:arguments
                                            frameLength:63];
    // destination 01, host 00, sequence 12, query|length 49, class 0d, op 28.
    XCTAssertNotNil(body);
    XCTAssertEqualObjects([body subdataWithRange:NSMakeRange(0, 9)],
                           APBBytes(0x01, 0x00, 0x12, 0x49, 0x0d, 0x28, 0x00, 0x00, 0x00));
    XCTAssertEqual(body.length, 63);
    const uint8_t *bytes = body.bytes;
    BOOL allZero = YES;
    for (NSUInteger index = 9; index < body.length; index++) {
        if (bytes[index] != 0) allZero = NO;
    }
    XCTAssertTrue(allZero);
}

- (void)testEncodedQueryRefusesArgumentsThatWouldNotFitOneFrame {
    XCTAssertNil([APBJabraGNP encodeQueryWithSequence:1
                                                 group:APBGNPPairingGroup
                                                   op:APBGNPRecordOp
                                            arguments:[NSMutableData dataWithLength:4]
                                          frameLength:8]);
    XCTAssertNil([APBJabraGNP encodeQueryWithSequence:1
                                                 group:APBGNPPairingGroup
                                                   op:APBGNPRecordOp
                                            arguments:[NSMutableData dataWithLength:64]
                                          frameLength:63]);
}

- (void)testDecodeReadsTheDeclaredLengthAndIgnoresTrailingPadding {
    NSMutableData *body = [APBConnectedReplyBody() mutableCopy];
    [body increaseLengthBy:63 - body.length];
    APBGNPMessage *message = [APBJabraGNP decode:body];
    XCTAssertNotNil(message);
    XCTAssertEqual(message.destination, APBGNPHostAddress);
    XCTAssertEqual(message.source, APBGNPDongleAddress);
    XCTAssertEqual(message.sequence, 0x12);
    XCTAssertEqual(message.kind, APBGNPReplyKind);
    XCTAssertEqual(message.group, APBGNPPairingGroup);
    XCTAssertEqual(message.op, APBGNPRecordOp);
    XCTAssertEqualObjects(message.arguments, APBConnectedRecord());
}

- (void)testDecodeRejectsShortAndInconsistentBodies {
    XCTAssertNil([APBJabraGNP decode:APBBytes(0x00, 0x01, 0x12)]);
    // Declared length below the header size.
    XCTAssertNil([APBJabraGNP decode:APBBytes(0x00, 0x01, 0x12, 0xc3, 0x0d, 0x28)]);
    // Declares more bytes than were received.
    XCTAssertNil([APBJabraGNP decode:APBBytes(0x00, 0x01, 0x12, 0xd6, 0x0d, 0x28)]);
}

- (void)testReplyMatchingRejectsStaleRepliesAndUnsolicitedEvents {
    APBGNPMessage *reply = [[APBGNPMessage alloc] initWithDestination:APBGNPHostAddress
                                                                source:APBGNPDongleAddress
                                                              sequence:0x12
                                                                  kind:APBGNPReplyKind
                                                                 group:APBGNPPairingGroup
                                                                    op:APBGNPRecordOp
                                                             arguments:APBConnectedRecord()];
    XCTAssertTrue([APBJabraGNP isReply:reply sequence:0x12 group:APBGNPPairingGroup op:APBGNPRecordOp]);
    // A different sequence is a stale reply from an earlier attempt.
    XCTAssertFalse([APBJabraGNP isReply:reply sequence:0x13 group:APBGNPPairingGroup op:APBGNPRecordOp]);
    // Wrong opcode.
    XCTAssertFalse([APBJabraGNP isReply:reply sequence:0x12 group:APBGNPPairingGroup op:0x32]);

    // The connection-state notification uses the same class and opcode space
    // but is an event, not an answer to our query.
    APBGNPMessage *event = [[APBGNPMessage alloc] initWithDestination:APBGNPHostAddress
                                                                source:APBGNPDongleAddress
                                                              sequence:0x12
                                                                  kind:APBGNPEventKind
                                                                 group:APBGNPPairingGroup
                                                                    op:APBGNPRecordOp
                                                             arguments:APBConnectedRecord()];
    XCTAssertFalse([APBJabraGNP isReply:event sequence:0x12 group:APBGNPPairingGroup op:APBGNPRecordOp]);
}

- (void)testConnectionAnnouncementsAreRecognisedButNeverTreatedAsAnswers {
    // Captured from a Link 380 about 100ms after an Evolve2 85 was powered
    // off, while a walk for sequence 0x0d was outstanding.
    NSData *announcement = APBBytes(
        0x00, 0x01, 0xae, 0x11, 0x0d, 0x26,
        0x01, 0x70, 0xbf, 0x92, 0xf4, 0x2f, 0xb8, 0x01, 0x00, 0x04, 0xff);
    APBGNPMessage *message = [APBJabraGNP decode:announcement];
    XCTAssertNotNil(message);
    XCTAssertEqual(message.kind, APBGNPEventKind);
    XCTAssertTrue([APBJabraGNP isConnectionEvent:message]);
    // It must not be mistaken for a record, whatever we are waiting for.
    XCTAssertFalse([APBJabraGNP isReply:message sequence:0xae group:APBGNPPairingGroup op:APBGNPRecordOp]);

    // A record reply is not an announcement, so a walk cannot retrigger itself.
    APBGNPMessage *reply = [APBJabraGNP decode:APBConnectedReplyBody()];
    XCTAssertNotNil(reply);
    XCTAssertFalse([APBJabraGNP isConnectionEvent:reply]);
}

- (void)testReassemblerJoinsFragmentedRepliesAndDropsGarbage {
    APBGNPReassembler *reassembler = [[APBGNPReassembler alloc] init];
    NSData *body = APBConnectedReplyBody();
    // Split across two physical frames.
    XCTAssertNil([reassembler feed:[body subdataWithRange:NSMakeRange(0, 5)]]);
    XCTAssertEqualObjects([reassembler feed:[body subdataWithRange:NSMakeRange(5, body.length - 5)]], body);

    // A single frame carrying padding yields only the declared bytes.
    NSMutableData *padded = [body mutableCopy];
    [padded increaseLengthBy:63 - padded.length];
    XCTAssertEqualObjects([reassembler feed:padded], body);

    // An implausible declared length is discarded rather than buffered.
    XCTAssertNil([reassembler feed:APBBytes(0x00, 0x01, 0x12, 0xc0)]);
    XCTAssertEqualObjects([reassembler feed:padded], body);
}

- (void)testWalkProvesConnectedFromTheFirstConnectedRecord {
    APBGNPPairingWalk *walk = [[APBGNPPairingWalk alloc] init];
    APBGNPStep *started = [walk start];
    XCTAssertFalse(started.isFinished);
    XCTAssertEqualObjects(started.cursor, APBBytes(0x00, 0x00));
    XCTAssertEqual(started.bluetoothType, 0x00);
    APBGNPStep *accepted = [walk acceptRecord:APBConnectedRecord()];
    XCTAssertTrue(accepted.isFinished);
    XCTAssertEqual(accepted.evidence, APBGNPEvidenceConnected);
}

- (void)testWalkProvesDisconnectedOnlyAfterEveryDatabaseTerminates {
    APBGNPPairingWalk *walk = [[APBGNPPairingWalk alloc] init];
    APBGNPStep *started = [walk start];
    XCTAssertFalse(started.isFinished);
    XCTAssertEqualObjects(started.cursor, APBBytes(0x00, 0x00));
    XCTAssertEqual(started.bluetoothType, 0x00);
    // Cursor advances using the bytes the dongle returned, opaquely.
    APBGNPStep *advanced = [walk acceptRecord:APBDisconnectedRecord()];
    XCTAssertFalse(advanced.isFinished);
    XCTAssertEqualObjects(advanced.cursor, APBBytes(0x00, 0x02));
    XCTAssertEqual(advanced.bluetoothType, 0x00);
    // Terminating the first database moves to the second, not to a verdict.
    APBGNPStep *second = [walk acceptRecord:APBLastRecord()];
    XCTAssertFalse(second.isFinished);
    XCTAssertEqualObjects(second.cursor, APBBytes(0x00, 0x00));
    XCTAssertEqual(second.bluetoothType, 0x01);
    APBGNPStep *finished = [walk acceptRecord:APBLastRecord()];
    XCTAssertTrue(finished.isFinished);
    XCTAssertEqual(finished.evidence, APBGNPEvidenceDisconnected);
}

- (void)testWalkStaysInconclusiveOnPartialEvidence {
    // A timeout mid-walk must never be read as "headset off".
    APBGNPPairingWalk *timedOut = [[APBGNPPairingWalk alloc] init];
    (void)[timedOut start];
    APBGNPStep *failed = [timedOut fail];
    XCTAssertTrue(failed.isFinished);
    XCTAssertEqual(failed.evidence, APBGNPEvidenceInconclusive);

    // A truncated record is not evidence either.
    APBGNPPairingWalk *malformed = [[APBGNPPairingWalk alloc] init];
    (void)[malformed start];
    APBGNPStep *rejected = [malformed acceptRecord:APBBytes(0x00, 0x01, 0x01)];
    XCTAssertTrue(rejected.isFinished);
    XCTAssertEqual(rejected.evidence, APBGNPEvidenceInconclusive);

    // A repeated cursor ends that database rather than looping forever.
    APBGNPPairingWalk *cyclic = [[APBGNPPairingWalk alloc] init];
    (void)[cyclic start];
    NSData *selfReferential = APBBytes(0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    APBGNPStep *cycled = [cyclic acceptRecord:selfReferential];
    XCTAssertFalse(cycled.isFinished);
    XCTAssertEqualObjects(cycled.cursor, APBBytes(0x00, 0x00));
    XCTAssertEqual(cycled.bluetoothType, 0x01);

    // Exhausting the record cap is suspicious, so it proves nothing.
    APBGNPPairingWalk *runaway =
        [[APBGNPPairingWalk alloc] initWithBluetoothTypes:APBBytes(0x00) cap:2];
    (void)[runaway start];
    APBGNPStep *visited = [runaway acceptRecord:APBDisconnectedRecord()];
    XCTAssertFalse(visited.isFinished);
    XCTAssertEqualObjects(visited.cursor, APBBytes(0x00, 0x02));
    XCTAssertEqual(visited.bluetoothType, 0x00);
    APBGNPStep *exhausted = [runaway acceptRecord:APBBytes(0x00, 0x03, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0)];
    XCTAssertTrue(exhausted.isFinished);
    XCTAssertEqual(exhausted.evidence, APBGNPEvidenceInconclusive);
}

- (void)testCompleteVendorEvidenceOverridesTheUntrustworthyLegacyBit {
    // This is the reported bug: after a replug the legacy bit claims linked
    // while no headset is connected. Vendor evidence must win.
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceDisconnected legacy:APBTriStateYes],
                   APBTriStateNo);
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceConnected legacy:APBTriStateNo],
                   APBTriStateYes);
    // Without usable vendor evidence the legacy bit is the fallback.
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceInconclusive legacy:APBTriStateYes],
                   APBTriStateYes);
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceNone legacy:APBTriStateNo],
                   APBTriStateNo);
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceInconclusive legacy:APBTriStateUnknown],
                   APBTriStateUnknown);
    XCTAssertEqual([APBJabraGNP resolveVendor:APBGNPEvidenceNone legacy:APBTriStateUnknown],
                   APBTriStateUnknown);
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
