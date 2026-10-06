#import <XCTest/XCTest.h>
#import "TestSupport.h"

/// The UIDs of each automatic switch notice, in order.
static NSMutableArray<NSArray<NSString *> *> *APBRecordNotices(APBAppModel *model) {
    NSMutableArray<NSArray<NSString *> *> *notices = [NSMutableArray array];
    model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) {
        [notices addObject:[devices valueForKey:@"uid"]];
    };
    return notices;
}

static NSNumber *APBLastSelectedID(APBFakeAudio *audio) {
    return audio.selectedIDs.lastObject;
}

@interface AppModelTests : XCTestCase
@end

@implementation AppModelTests

- (void)testStartupSelectsHighestPriorityInputAndOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(audio.selectedRoles, (@[@(APBDeviceRoleOutput), @(APBDeviceRoleInput)]));
    XCTAssertEqualObjects(model.currentInputID, @1);
    XCTAssertEqualObjects(model.currentOutputID, @2);
}

- (void)testStartupScansMuteStateOnceAfterSelectingDefaults {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqual(audio.muteReadCount, 4);
}

- (void)testMuteAndVolumeCallbacksAreCoalesced {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBOutput(1, @"speaker", nil)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    audio.volumeReadCount = 0;

    [model handleMuteOrVolumeChanged];
    [model handleMuteOrVolumeChanged];
    for (int i = 0; i < 100 && audio.volumeReadCount == 0; i++) {
        APBDrainMainQueue();
    }

    XCTAssertEqual(audio.volumeReadCount, 1);
}

- (void)testFailedSelectionDoesNotClaimDeviceIsCurrent {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBOutput(1, @"speaker", nil)];
    audio.selectionSucceeds = NO;
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertNil(model.currentOutputID);
    XCTAssertEqual(audio.selections.count, 0);
}

- (void)testStartupPrefersHeadphonesOverSpeakers {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testStartupFallsBackWhenHeadphonesAreUnusable {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *unavailable = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[speaker, unavailable];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:@"jabra"];
    }, nil, nil);

    [model start];

    XCTAssertEqualObjects(APBLastSelectedID(audio), @(speaker.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategorySpeaker);
}

- (void)testNeverAutoSelectDeviceRemainsVisible {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    [store setNeverUse:speaker value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.speakerDevices, @[speaker]);
    XCTAssertEqual(audio.selections.count, 0);
}

- (void)testShowAllRevealsHiddenDevicesInTheirOwnList {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *kept = APBOutput(1, @"speaker", nil);
    APBAudioDevice *hidden = APBOutput(2, @"hdmi", @"HDMI");
    [store hide:hidden inCategory:APBOutputCategorySpeaker];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[kept, hidden];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.speakerDevices, @[kept]);
    XCTAssertEqualObjects(model.hiddenSpeakerDevices, @[hidden]);

    model.showAll = YES;
    [model refreshDevices];

    XCTAssertEqualObjects(model.speakerDevices, (@[kept, hidden]));
    XCTAssertEqual(model.hiddenSpeakerDevices.count, 0);
}

- (void)testAnOutsideChangeIsSwitchedBackAndAutomaticStaysOn {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];
    NSMutableArray *notices = APBRecordNotices(model);

    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
    XCTAssertEqualObjects(audio.selectedIDs, @[@(headphones.platformID)]);
    XCTAssertEqualObjects(notices, @[@[@"headphones"]]);
}

- (void)testSpeakersTakingOverFromDisconnectedHeadphonesStartMuted {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].mutesSpeakersWhenHeadphonesDisconnect = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));

    audio.catalog = @[speaker];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertTrue(model.isActiveOutputMuted);
}

- (void)testSpeakersTakingOverFromAPoweredOffJabraHeadsetStartMuted {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.mutesSpeakersWhenHeadphonesDisconnect = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    [store setCategory:APBOutputCategoryHeadphone forDevice:jabra];
    audio.catalog = @[speaker, jabra];
    __block BOOL isHeadsetOn = YES;
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:@"jabra"] || isHeadsetOn;
    }, nil, nil);
    [model start];
    XCTAssertEqualObjects(model.currentOutputID, @(jabra.platformID));

    // The dongle stays plugged in, so only the link verdict changes.
    isHeadsetOn = NO;
    [model handleLinkChanged];

    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertTrue(model.isActiveOutputMuted);
}

- (void)testSpeakersStartMutedWhenMacOSMovesTheOutputAfterTheHeadphonesLeave {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    store.mutesSpeakersWhenHeadphonesDisconnect = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    audio.defaults[@(APBDeviceRoleOutput)] = @(headphones.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // The device list can change while the default still names the
    // headphones that are already gone.
    audio.catalog = @[speaker];
    [model handleDevicesChanged];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertTrue(model.isActiveOutputMuted);
}

- (void)testSpeakersStayUnmutedUnlessThePlayingHeadphonesLeaveWithTheOptionOn {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    audio.defaults[@(APBDeviceRoleOutput)] = @(headphones.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDevicesChanged];
    XCTAssertFalse(model.isActiveOutputMuted);

    [model setMutesSpeakersWhenHeadphonesDisconnectEnabled:YES];
    audio.catalog = @[speaker, headphones];
    [model handleDevicesChanged];
    audio.catalog = @[speaker];
    [model handleDevicesChanged];
    XCTAssertFalse(model.isActiveOutputMuted);
}

- (void)testAPickInControlCenterStaysUntilADeviceConnectsOrDisconnects {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];
    [audio.selections removeAllObjects];

    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    // A Jabra verdict refreshes the lists without connecting anything.
    [model handleLinkChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(audio.selections.count, 0);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));

    audio.catalog = [audio.catalog arrayByAddingObject:APBInput(3, @"usb-mic", @"USB Mic")];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
}

- (void)testAirPodsTakingTheMicrophoneOnEarDetectionIsSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *airPods = APBOutput(1, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(2, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(3, @"scarlett", @"Scarlett Solo USB");
    [store savePriorities:@[scarlett, airPodsMic] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[airPods, airPodsMic, scarlett];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    XCTAssertEqualObjects(model.currentInputID, @(scarlett.platformID));

    // Long after they connected, putting them in makes macOS move the mic.
    audio.defaults[@(APBDeviceRoleInput)] = @(airPodsMic.platformID);
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentInputID, @(scarlett.platformID));
    XCTAssertEqualObjects(model.currentOutputID, @(airPods.platformID));
}

- (void)testAirPodsTakingTheOutputBackInManualModeIsSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", @"MacBook Air Speakers");
    APBAudioDevice *airPods = APBOutput(2, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(3, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(4, @"scarlett", @"Scarlett Solo USB");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, airPods, airPodsMic, scarlett];
    audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(scarlett.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model selectManually:speaker];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [audio.selections removeAllObjects];

    // Seen in a real trace: seconds after the pick, with nothing connecting,
    // macOS moves the output and microphone to the AirPods in the user's ears.
    audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    audio.defaults[@(APBDeviceRoleInput)] = @(airPodsMic.platformID);
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(scarlett.platformID));
    XCTAssertEqualObjects(audio.selectedIDs, (@[@(speaker.platformID), @(scarlett.platformID)]));
}

- (void)testAirPodsTakingBothDevicesAtOnceInManualModeAreBothSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", @"MacBook Air Speakers");
    APBAudioDevice *airPods = APBOutput(2, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(3, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(4, @"scarlett", @"Scarlett Solo USB");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, airPods, airPodsMic, scarlett];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(scarlett.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // Seen in a real trace: macOS moves both 3 ms apart, so the input has
    // already moved when the output's event is handled.
    audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(airPodsMic.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(scarlett.platformID));
    XCTAssertEqualObjects(audio.defaults[@(APBDeviceRoleOutput)], @(speaker.platformID));
    XCTAssertEqualObjects(audio.defaults[@(APBDeviceRoleInput)], @(scarlett.platformID));
}

- (void)testAPickInControlCenterStaysInManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, airPods];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];

    audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(airPods.platformID));
    XCTAssertEqual(audio.selections.count, 0);
}

- (void)testANewlyConnectedOutputStaysInManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:airPods];
    audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(model.currentOutputID, @(airPods.platformID));
    XCTAssertEqual(audio.selections.count, 0);
}

- (void)testMacOSTakingTheOutputAgainAfterASwitchBackIsLeftAndNamed {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, airPods];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // Smart Routing retries about 4 seconds after each switch back.
    for (int i = 0; i < 3; i++) {
        audio.defaults[@(APBDeviceRoleOutput)] = @(airPods.platformID);
        [model handleDefaultChanged:APBDeviceRoleOutput];
    }

    XCTAssertEqualObjects(audio.selectedIDs, @[@(speaker.platformID)]);
    XCTAssertEqualObjects(model.takeoverDevice.uid, airPods.uid);

    [model selectManually:speaker];

    XCTAssertNil(model.takeoverDevice);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testAutomaticModeKeepsAMicrophoneMacOSTakesAgainAfterASwitchBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *airPods = APBOutput(1, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(2, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(3, @"scarlett", @"Scarlett Solo USB");
    [store savePriorities:@[scarlett, airPodsMic] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[airPods, airPodsMic, scarlett];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    for (int i = 0; i < 3; i++) {
        audio.defaults[@(APBDeviceRoleInput)] = @(airPodsMic.platformID);
        [model handleDefaultChanged:APBDeviceRoleInput];
    }

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentInputID, @(airPodsMic.platformID));
    XCTAssertEqualObjects(model.takeoverDevice.uid, airPodsMic.uid);
}

- (void)testOutputMovingBeforeTheDisconnectArrivesKeepsAutomaticOn {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // Seen in a real trace: the default moves to the speakers 40 ms before
    // the AirPods leave the device list.
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    audio.catalog = @[speaker];
    [model handleDevicesChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testNewHeadphoneBecomesAutomaticOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = [audio.catalog arrayByAddingObject:headphones];
    [model handleDevicesChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(APBLastSelectedID(audio), @(headphones.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testLosingAndReturningHeadphonesSwitchesAutomaticOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = @[speaker];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(APBLastSelectedID(audio), @(speaker.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategorySpeaker);

    audio.catalog = [audio.catalog arrayByAddingObject:headphones];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(APBLastSelectedID(audio), @(headphones.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testManualModeNeverChangesDevicesAutomatically {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBOutput(1, @"speaker", nil)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:APBOutput(2, @"headphones", @"AirPods Pro")];
    [model handleDevicesChanged];

    XCTAssertEqual(audio.selections.count, 0);
    XCTAssertTrue(model.isManualMode);
}

- (void)testExplicitChoiceTurnsAutomaticOffUntilReenabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:speaker];
    [audio.selections removeAllObjects];
    [model handleDevicesChanged];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertEqual(audio.selections.count, 0);

    [model setManualMode:NO];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
    XCTAssertEqualObjects(APBLastSelectedID(audio), @(headphones.platformID));
}

- (void)testAppDefaultChangeEchoKeepsAutomaticOn {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headphones = APBOutput(1, @"headphones", @"AirPods Pro");
    audio.catalog = @[headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
}

- (void)testSystemFallbackAfterDisconnectKeepsAutomaticOn {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testSystemChoiceDuringConnectionStillAppliesPriority {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *preferred = APBOutput(2, @"preferred", @"AirPods Pro");
    APBAudioDevice *newcomer = APBOutput(3, @"newcomer", @"USB Headphones");
    audio.catalog = @[speaker, preferred];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = [audio.catalog arrayByAddingObject:newcomer];
    audio.defaults[@(APBDeviceRoleOutput)] = @(newcomer.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(preferred.platformID));
    XCTAssertEqualObjects(APBLastSelectedID(audio), @(preferred.platformID));
}

- (void)testUnlinkedHeadsetIsSkippedDuringAutomaticSelection {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *unlinked = APBOutput(1, @"jabra", @"Jabra Link 380");
    APBAudioDevice *fallback = APBOutput(2, @"airpods", @"AirPods Pro");
    audio.catalog = @[unlinked, fallback];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:@"jabra"];
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:@"jabra"] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);

    [model start];

    XCTAssertEqualObjects(APBLastSelectedID(audio), @(fallback.platformID));
    XCTAssertEqual([model linkStateForDevice:unlinked], APBLinkStateDown);
    // The menu bar warning follows the active output only, so a powered-off
    // device we already switched away from must not raise it.
    XCTAssertFalse(model.isActiveOutputLinkDown);
}

- (void)testMenuBarWarningTracksOnlyTheActiveOutputBeingUnplayable {
    NSUserDefaults *defaults = APBIsolatedDefaults();

    // Manual mode parks the user on a headset that is powered off, which is
    // the case automatic switching cannot rescue them from.
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *jabra = APBOutput(1, @"jabra", @"Jabra Link 380");
    audio.catalog = @[jabra];
    APBAppModel *stranded = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return YES;
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:@"jabra"] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);
    [stranded start];
    XCTAssertEqualObjects(stranded.currentOutputID, @(jabra.platformID));
    XCTAssertTrue(stranded.isActiveOutputLinkDown);

    // Every other link state leaves the warning off, including the transient
    // checking window and the two states that mean "not known".
    for (NSNumber *value in @[@(APBLinkStateUp), @(APBLinkStateChecking), @(APBLinkStateUnknown),
                              @(APBLinkStateMonitoringUnavailable)]) {
        APBLinkState state = (APBLinkState)value.integerValue;
        APBFakeAudio *audio = [[APBFakeAudio alloc] init];
        audio.catalog = @[jabra];
        APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
            return YES;
        }, ^APBLinkState(APBAudioDevice *device) {
            return state;
        }, nil);
        [model start];
        XCTAssertFalse(model.isActiveOutputLinkDown);
    }

    // No selected output at all.
    APBFakeAudio *empty = [[APBFakeAudio alloc] init];
    APBAppModel *idle = APBTestModel(empty, defaults, nil, nil, nil);
    [idle start];
    XCTAssertNil(idle.currentOutputDevice);
    XCTAssertFalse(idle.isActiveOutputLinkDown);
}

- (void)testFullDuplexMuteStateIsRoleScoped {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(7, @"shared", nil), APBOutput(7, @"shared", nil)];
    [audio.muted setSet:[NSSet setWithObject:@"input:7"]];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertTrue([model isMuted:APBInput(7, @"shared", nil)]);
    XCTAssertFalse([model isMuted:APBOutput(7, @"shared", nil)]);
}

- (void)testReduceMotionKeepsMutedMicrophoneIndicatorSteady {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *microphone = APBInput(1, @"microphone", nil);
    audio.catalog = @[microphone];
    audio.defaults[@(APBDeviceRoleInput)] = @(microphone.platformID);
    [audio.muted setSet:[NSSet setWithObject:@"input:1"]];
    APBLinkOperations *link = [[APBLinkOperations alloc]
        initWithIsUsable:^BOOL(APBAudioDevice *device) { return YES; }
                   state:^APBLinkState(APBAudioDevice *device) { return APBLinkStateNone; }];
    APBAppModel *model = [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] initWithDefaults:defaults]
                                                      audio:audio.operations
                                                       link:link
                                                    battery:nil
                                               reduceMotion:^BOOL { return YES; }
                                              isUserPicking:nil];

    [model start];

    XCTAssertTrue(model.isActiveInputMuted);
    XCTAssertTrue(model.micFlashState);
    [model stop];
    XCTAssertFalse(model.micFlashState);
}

// Jabra Link 380 and the MacBook Pro microphone both expose a settable input
// mute on the main element (macOS 26, probed 2026-09-26), which FakeAudio
// models by default. ZoomAudioDevice has none and rests at zero volume.

- (void)testMicrophoneMuteMovesToTheNewMicrophone {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headset = APBInput(1, @"headset", @"Jabra Link 380");
    APBAudioDevice *builtIn = APBInput(2, @"builtin", @"MacBook Pro Microphone");
    audio.catalog = @[headset, builtIn];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);

    audio.catalog = @[builtIn];
    [model handleDevicesChanged];
    XCTAssertEqualObjects(model.currentInputID, @2);
    XCTAssertTrue(model.isMicrophoneMuted);
    XCTAssertTrue([audio.muted containsObject:@"input:2"]);

    audio.catalog = @[headset, builtIn];
    [model handleDevicesChanged];
    XCTAssertEqualObjects(model.currentInputID, @1);
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);

    [model selectManually:builtIn];
    [model handleDefaultChanged:APBDeviceRoleInput];
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:2"]);
    XCTAssertTrue(model.isActiveInputMuted);
}

- (void)testMuteFallsBackToZeroVolumeAndRestoresTheLevel {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"zoom", @"ZoomAudioDevice")];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @(0.627f);
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];
    XCTAssertEqual(audio.inputVolumes[@1].floatValue, 0.0f);
    XCTAssertTrue(model.isActiveInputMuted);
    XCTAssertNotNil([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes[@"zoom"]);

    [model setMicrophoneMuted:NO];
    XCTAssertEqual(audio.inputVolumes[@1].floatValue, 0.627f);
    XCTAssertFalse(model.isActiveInputMuted);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0);
}

- (void)testAVirtualMicrophoneRestingAtZeroVolumeIsNotShownMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"zoom", @"ZoomAudioDevice")];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @(0.0f);
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertFalse(model.isActiveInputMuted);
}

- (void)testUnmutingElsewhereClearsTheMute {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil)];
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [audio.muted removeObject:@"input:1"];
    [model refreshMute];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0);
}

- (void)testAHeadsetMuteButtonIsFollowed {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"headset", nil)];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [audio.muted addObject:@"input:1"];
    [model refreshMute];

    XCTAssertTrue(model.isMicrophoneMuted);
}

- (void)testAMicrophoneMutedWhileUnpluggedComesBackUnmuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headset = APBInput(1, @"headset", nil);
    APBAudioDevice *builtIn = APBInput(2, @"builtin", nil);
    audio.catalog = @[headset, builtIn];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    audio.catalog = @[builtIn];
    [model handleDevicesChanged];
    [model setMicrophoneMuted:NO];
    audio.catalog = @[headset, builtIn];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(model.currentInputID, @1);
    XCTAssertEqual(audio.muted.count, 0);
    XCTAssertFalse(model.isMicrophoneMuted);
}

- (void)testQuittingRestoresAppliedMutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil)];
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [model stop];

    XCTAssertEqual(audio.muted.count, 0);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0);
}

- (void)testRecordingIsReportedForTheCurrentMicrophoneOnly {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil), APBInput(2, @"other", nil)];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [audio.running setSet:[NSSet setWithObject:@2]];
    [model refreshMute];
    XCTAssertFalse(model.isInputRecording);

    [audio.running setSet:[NSSet setWithObject:@1]];
    [model refreshMute];
    XCTAssertTrue(model.isInputRecording);
}

- (void)testAConnectedHeadsetTriggersOneSwitchNotice {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    NSMutableArray *notices = APBRecordNotices(model);

    audio.catalog = @[speaker, headphones];
    [model handleDevicesChanged];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(notices, @[@[@"headphones"]]);
}

- (void)testManualSelectionShowsNoSwitchNotice {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    audio.catalog = @[speaker, APBOutput(2, @"headphones", @"AirPods Pro")];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    NSMutableArray *notices = APBRecordNotices(model);

    [model selectManually:speaker];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(notices.count, 0);
}

- (void)testStartupShowsNoSwitchNotice {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil)];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    NSMutableArray *notices = APBRecordNotices(model);

    [model start];

    XCTAssertEqual(notices.count, 0);
}

- (void)testMovingTheMicrophoneLevelWhileMutedUnmutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"mic", nil)];
    audio.inputVolumes[@1] = @(0.627f);
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [model changeMicrophoneLevel:0.4f];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual(audio.muted.count, 0);
    XCTAssertEqual(audio.inputVolumes[@1].floatValue, 0.4f);
    XCTAssertEqual(model.microphoneLevel, 0.4f);
}

- (void)testAZeroVolumeMuteShowsTheLevelItWillRestore {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"zoom", @"ZoomAudioDevice")];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @(0.627f);
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];

    XCTAssertEqual(audio.inputVolumes[@1].floatValue, 0.0f);
    XCTAssertEqual(model.microphoneLevel, 0.627f);
}

- (void)testOutputMuteTogglesAndRaisingTheVolumeUnmutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBOutput(1, @"speaker", nil)];
    audio.defaults[@(APBDeviceRoleOutput)] = @1;
    audio.volume = @(0.43f);
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    XCTAssertTrue(model.isOutputMutable);

    [model setOutputMuted:YES];
    XCTAssertTrue(model.isActiveOutputMuted);

    [model changeVolume:0.5f];
    XCTAssertFalse(model.isActiveOutputMuted);
    XCTAssertEqual(audio.muted.count, 0);
}

- (void)testAMicrophoneWithNeitherMuteNorLevelCannotBeMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"scarlett", @"Scarlett Solo USB")];
    audio.defaults[@(APBDeviceRoleInput)] = @1;
    [audio.noMuteProperty addObject:@1];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    XCTAssertFalse(model.isMicrophoneLevelControllable);
    XCTAssertFalse(model.isMicrophoneMutable);
}

- (void)testAnOutputWithNeitherVolumeNorMuteCannotBeControlled {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBOutput(1, @"scarlett", @"Scarlett Solo USB")];
    audio.defaults[@(APBDeviceRoleOutput)] = @1;
    [audio.noMuteProperty addObject:@1];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    XCTAssertFalse(model.isVolumeControllable);
    XCTAssertFalse(model.isOutputMutable);
}

- (void)testUrlCommandsMuteOnlyAMicrophoneThatCanBeMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[APBInput(1, @"headset", @"USB Headset")];
    audio.defaults[@(APBDeviceRoleInput)] = @1;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model perform:APBURLCommandToggleMicMute];
    XCTAssertTrue(model.isMicrophoneMuted);
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);
    [model perform:APBURLCommandMuteMic];
    XCTAssertTrue(model.isMicrophoneMuted);
    [model perform:APBURLCommandToggleMicMute];
    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual(audio.muted.count, 0);
    [model perform:APBURLCommandUnmuteMic];
    XCTAssertFalse(model.isMicrophoneMuted);

    [audio.noMuteProperty setSet:[NSSet setWithObject:@1]];
    [model refreshVolume];
    [model perform:APBURLCommandMuteMic];
    XCTAssertFalse(model.isMicrophoneMuted);
    [model perform:APBURLCommandToggleMicMute];
    XCTAssertFalse(model.isMicrophoneMuted);
}

@end
