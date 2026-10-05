#import <XCTest/XCTest.h>
#import "APBJabra.h"

@interface APBJabraLinkTests : XCTestCase
@end

/// Two report bytes, built in a function so the commas stay protected inside
/// XCTest macro arguments.
static NSData *APBReport(uint8_t id, uint8_t value) {
    const uint8_t bytes[2] = { id, value };
    return [NSData dataWithBytes:bytes length:2];
}

@implementation APBJabraLinkTests

- (void)testLink380ElementDecodingHonorsColdReadTimestamp {
    XCTAssertTrue([APBJabraLink decodeElementValue:0 linkedValue:0]);
    XCTAssertFalse([APBJabraLink decodeElementValue:1 linkedValue:0]);
    XCTAssertEqual([APBJabraLink snapshotValue:0 timestamp:0 linkedValue:0], APBTriStateUnknown);
    XCTAssertEqual([APBJabraLink snapshotValue:0 timestamp:1 linkedValue:0], APBTriStateYes);
    XCTAssertEqual([APBJabraLink snapshotValue:1 timestamp:1 linkedValue:0], APBTriStateNo);
}

- (void)testLink390ReportDecodingIgnoresUnrelatedOrShortReports {
    XCTAssertEqual([APBJabraLink decodeReportID:4
                                    expectedID:4
                                         bytes:APBReport(4, 0x08)
                                     byteIndex:1
                                       bitMask:0x08], APBTriStateYes);
    XCTAssertEqual([APBJabraLink decodeReportID:4
                                    expectedID:4
                                         bytes:APBReport(4, 0x00)
                                     byteIndex:1
                                       bitMask:0x08], APBTriStateNo);
    XCTAssertEqual([APBJabraLink decodeReportID:3
                                    expectedID:4
                                         bytes:APBReport(3, 0x08)
                                     byteIndex:1
                                       bitMask:0x08], APBTriStateUnknown);
    XCTAssertEqual([APBJabraLink decodeReportID:4
                                    expectedID:4
                                         bytes:[NSData dataWithBytes:(const uint8_t[]){ 4 } length:1]
                                     byteIndex:1
                                       bitMask:0x08], APBTriStateUnknown);
}

- (void)testAutomaticSelectionFailsOpenUnlessLinkIsConfirmedDown {
    XCTAssertTrue([APBJabraLink allowsSelectionWhenSupported:NO state:APBLinkStateUnknown]);
    XCTAssertTrue([APBJabraLink allowsSelectionWhenSupported:YES state:APBLinkStateMonitoringUnavailable]);
    XCTAssertTrue([APBJabraLink allowsSelectionWhenSupported:YES state:APBLinkStateUnknown]);
    XCTAssertFalse([APBJabraLink allowsSelectionWhenSupported:YES state:APBLinkStateDown]);
    XCTAssertTrue([APBJabraLink allowsSelectionWhenSupported:YES state:APBLinkStateUp]);
    // A pending authoritative answer is not permission to route audio.
    XCTAssertFalse([APBJabraLink allowsSelectionWhenSupported:YES state:APBLinkStateChecking]);
    XCTAssertTrue([APBJabraLink allowsSelectionWhenSupported:NO state:APBLinkStateChecking]);
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
    XCTAssertEqual([APBJabraLink profileMatching:@"USB JABRA LINK 380"].profileID,
                   APBJabraProfileIDLink380);
    XCTAssertEqual([APBJabraLink profileMatching:@"Jabra Link 390"].profileID,
                   APBJabraProfileIDLink390);
    XCTAssertNil([APBJabraLink profileMatching:@"Other headset"]);
}

- (void)testDownTransitionWaitsAndCanBeCancelledByUp {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    APBLinkTransition initial = [state observe:YES];
    XCTAssertEqual(initial, APBLinkTransitionChanged);
    XCTAssertEqual(state.effective, APBTriStateYes);
    APBLinkTransition down = [state observe:NO];
    XCTAssertEqual(down, APBLinkTransitionScheduleDown);
    XCTAssertEqual(state.effective, APBTriStateYes);
    APBLinkTransition recovered = [state observe:YES];
    XCTAssertEqual(recovered, APBLinkTransitionCancelDown);
    XCTAssertEqual(state.effective, APBTriStateYes);
    XCTAssertFalse([state commitDown]);
}

- (void)testDownTransitionCommitsOnlyWhileStillObservedDown {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    XCTAssertTrue([state seed:YES]);
    APBLinkTransition down = [state observe:NO];
    XCTAssertEqual(down, APBLinkTransitionScheduleDown);
    XCTAssertEqual(state.effective, APBTriStateYes);
    XCTAssertTrue([state commitDown]);
    XCTAssertEqual(state.effective, APBTriStateNo);
    XCTAssertFalse([state commitDown]);
}

- (void)testReportedColdReadSeedsEffectiveStateWithoutDebounce {
    APBDebouncedLinkState *state = [[APBDebouncedLinkState alloc] init];
    XCTAssertTrue([state seed:NO]);
    XCTAssertEqual(state.effective, APBTriStateNo);
}

@end
