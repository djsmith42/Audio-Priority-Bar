#import <XCTest/XCTest.h>
#import "AudioPriorityCore.h"

static NSData *Bytes(NSArray<NSNumber *> *values) {
    NSMutableData *data = [NSMutableData dataWithCapacity:values.count];
    for (NSNumber *value in values) {
        uint8_t byte = value.unsignedCharValue;
        [data appendBytes:&byte length:1];
    }
    return data;
}

@interface JabraLinkTests : XCTestCase
@end

@implementation JabraLinkTests

- (void)testLink380ElementDecodingHonorsColdReadTimestamp {
    XCTAssertTrue([APBJabraLink decodeElementValue:0 linkedValue:0]);
    XCTAssertFalse([APBJabraLink decodeElementValue:1 linkedValue:0]);
    XCTAssertNil([APBJabraLink snapshotValue:0 timestamp:0 linkedValue:0]);
    XCTAssertEqualObjects([APBJabraLink snapshotValue:0 timestamp:1 linkedValue:0], @YES);
    XCTAssertEqualObjects([APBJabraLink snapshotValue:1 timestamp:1 linkedValue:0], @NO);
}

- (void)testLink390ReportDecodingIgnoresUnrelatedOrShortReports {
    XCTAssertEqualObjects([APBJabraLink decodeReportID:4
                                            expectedID:4
                                                 bytes:Bytes(@[@4, @0x08])
                                             byteIndex:1
                                               bitMask:0x08], @YES);
    XCTAssertEqualObjects([APBJabraLink decodeReportID:4
                                            expectedID:4
                                                 bytes:Bytes(@[@4, @0x00])
                                             byteIndex:1
                                               bitMask:0x08], @NO);
    XCTAssertNil([APBJabraLink decodeReportID:3
                                   expectedID:4
                                        bytes:Bytes(@[@3, @0x08])
                                    byteIndex:1
                                      bitMask:0x08]);
    XCTAssertNil([APBJabraLink decodeReportID:4
                                   expectedID:4
                                        bytes:Bytes(@[@4])
                                    byteIndex:1
                                      bitMask:0x08]);
}

- (void)testAutomaticSelectionFailsOpenUnlessLinkIsConfirmedDown {
    XCTAssertTrue([APBJabraLink allowsSelectionIsSupported:NO state:APBLinkStateUnknown]);
    XCTAssertTrue([APBJabraLink allowsSelectionIsSupported:YES
                                                     state:APBLinkStateMonitoringUnavailable]);
    XCTAssertTrue([APBJabraLink allowsSelectionIsSupported:YES state:APBLinkStateUnknown]);
    XCTAssertFalse([APBJabraLink allowsSelectionIsSupported:YES state:APBLinkStateDown]);
    XCTAssertTrue([APBJabraLink allowsSelectionIsSupported:YES state:APBLinkStateUp]);
    // A pending authoritative answer is not permission to route audio.
    XCTAssertFalse([APBJabraLink allowsSelectionIsSupported:YES state:APBLinkStateChecking]);
    XCTAssertTrue([APBJabraLink allowsSelectionIsSupported:NO state:APBLinkStateChecking]);
}

- (void)testOnlyLinkDonglesAreLinkMonitored {
    // A dongle publishes its audio device whether or not a headset is on, so
    // it needs monitoring.
    XCTAssertTrue([APBJabraLink isDongleProduct:@"Jabra Link 380"]);
    XCTAssertTrue([APBJabraLink isDongleProduct:@"JABRA LINK 390"]);
    XCTAssertTrue([APBJabraLink isDongleProduct:@"Jabra Link 370"]);
    XCTAssertTrue([APBJabraLink isDongleProduct:@"USB Jabra Link 400"]);

    // These are present whenever macOS lists them. Monitoring them would let
    // an empty pairing list mark a working device as off, which is the
    // regression risk for the speakerphone in tobi/AudioPriorityBar#39.
    XCTAssertFalse([APBJabraLink isDongleProduct:@"Jabra Speak2 75"]);
    XCTAssertFalse([APBJabraLink isDongleProduct:@"Jabra Speak 750"]);
    XCTAssertFalse([APBJabraLink isDongleProduct:@"Jabra Evolve2 85"]);
    XCTAssertFalse([APBJabraLink isDongleProduct:@"Jabra Elite 8 Active"]);
    XCTAssertFalse([APBJabraLink isDongleProduct:@"MacBook Pro Speakers"]);
}

- (void)testProductProfilesMatchCaseInsensitiveSubstrings {
    XCTAssertEqual([APBJabraLink profileMatching:@"USB JABRA LINK 380"].identifier, APBJabraProfileIDLink380);
    XCTAssertEqual([APBJabraLink profileMatching:@"Jabra Link 390"].identifier, APBJabraProfileIDLink390);
    XCTAssertNil([APBJabraLink profileMatching:@"Other headset"]);
}

- (void)testDownTransitionWaitsAndCanBeCancelledByUp {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    APBLinkTransition initial = [state observe:YES];
    XCTAssertEqual(initial, APBLinkTransitionChanged);
    XCTAssertEqualObjects(state.effective, @YES);
    APBLinkTransition down = [state observe:NO];
    XCTAssertEqual(down, APBLinkTransitionScheduleDown);
    XCTAssertEqualObjects(state.effective, @YES);
    APBLinkTransition recovered = [state observe:YES];
    XCTAssertEqual(recovered, APBLinkTransitionCancelDown);
    XCTAssertEqualObjects(state.effective, @YES);
    BOOL committed = [state commitDown];
    XCTAssertFalse(committed);
}

- (void)testDownTransitionCommitsOnlyWhileStillObservedDown {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    BOOL seeded = [state seed:YES];
    XCTAssertTrue(seeded);
    APBLinkTransition down = [state observe:NO];
    XCTAssertEqual(down, APBLinkTransitionScheduleDown);
    XCTAssertEqualObjects(state.effective, @YES);
    BOOL committed = [state commitDown];
    XCTAssertTrue(committed);
    XCTAssertEqualObjects(state.effective, @NO);
    BOOL duplicate = [state commitDown];
    XCTAssertFalse(duplicate);
}

- (void)testReportedColdReadSeedsEffectiveStateWithoutDebounce {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    BOOL seeded = [state seed:NO];
    XCTAssertTrue(seeded);
    XCTAssertEqualObjects(state.effective, @NO);
}

@end
