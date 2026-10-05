#import "APBTestSupport.h"

@interface APBAppModelTests : XCTestCase
@end

@implementation APBAppModelTests

- (void)testStartupSelectsHighestPriorityInputAndOutput {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil) ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(audio.selectedRoles, (@[ @(APBDeviceRoleOutput), @(APBDeviceRoleInput) ]));
    XCTAssertEqual(model.currentInputID, 1u);
    XCTAssertEqual(model.currentOutputID, 2u);
}

- (void)testStartupScansMuteStateOnceAfterSelectingDefaults {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil) ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertEqual(audio.muteReadCount, 4);
}

- (void)testMuteAndVolumeCallbacksAreCoalesced {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBOutput(1, @"speaker", nil) ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    audio.volumeReadCount = 0;

    [model handleMuteOrVolumeChanged];
    [model handleMuteOrVolumeChanged];
    APBWaitUntil(1, ^BOOL { return audio.volumeReadCount > 0; });
    // Gives a second, uncoalesced refresh the chance to show up.
    APBWaitUntil(0.1, ^BOOL { return NO; });

    XCTAssertEqual(audio.volumeReadCount, 1);
}

- (void)testFailedSelectionDoesNotClaimDeviceIsCurrent {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBOutput(1, @"speaker", nil) ];
    audio.selectionSucceeds = NO;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, 0u);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testStartupPrefersHeadphonesOverSpeakers {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ APBOutput(1, @"speaker", nil), headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, headphones.platformID);
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testStartupFallsBackWhenHeadphonesAreUnusable {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    audio.catalog = @[ speaker, APBOutput(2, @"jabra", @"Jabra Link 380") ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:@"jabra"];
    }, nil, nil);

    [model start];

    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(speaker.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategorySpeaker);
}

- (void)testNeverAutoSelectDeviceRemainsVisible {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    [[[APBPriorityStore alloc] initWithDefaults:defaults] setNeverUse:speaker value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.speakerDevices, @[ speaker ]);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testShowAllRevealsHiddenDevicesInTheirOwnList {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *kept = APBOutput(1, @"speaker", nil);
    APBAudioDevice *hidden = APBOutput(2, @"hdmi", @"HDMI");
    [[[APBPriorityStore alloc] initWithDefaults:defaults] hide:hidden inCategory:APBOutputCategorySpeaker];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ kept, hidden ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.speakerDevices, @[ kept ]);
    XCTAssertEqualObjects(model.hiddenSpeakerDevices, @[ hidden ]);

    model.showAll = YES;
    [model refreshDevices];

    XCTAssertEqualObjects(model.speakerDevices, (@[ kept, hidden ]));
    XCTAssertEqual(model.hiddenSpeakerDevices.count, 0u);
}

- (void)testAnOutsideChangeIsSwitchedBackAndAutomaticStaysOn {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];
    NSMutableArray *notices = [NSMutableArray array];
    model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) { [notices addObject:devices]; };

    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, headphones.platformID);
    XCTAssertEqualObjects(audio.selectedIDs, @[ @(headphones.platformID) ]);
    XCTAssertEqualObjects(APBUIDLists(notices), @[ @[ @"headphones" ] ]);
}

- (void)testAPickInControlCenterStaysUntilADeviceConnectsOrDisconnects {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, ^BOOL { return YES; });
    [model start];
    [audio.selections removeAllObjects];

    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    // A Jabra verdict refreshes the lists without connecting anything.
    [model handleLinkChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(audio.selections.count, 0u);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);

    audio.catalog = [audio.catalog arrayByAddingObject:APBInput(3, @"usb-mic", @"USB Mic")];
    [model handleDevicesChanged];

    XCTAssertEqual(model.currentOutputID, headphones.platformID);
}

- (void)testAirPodsTakingTheMicrophoneOnEarDetectionIsSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *airPods = APBOutput(1, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(2, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(3, @"scarlett", @"Scarlett Solo USB");
    [[[APBPriorityStore alloc] initWithDefaults:defaults] savePriorities:@[ scarlett, airPodsMic ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ airPods, airPodsMic, scarlett ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    XCTAssertEqual(model.currentInputID, scarlett.platformID);

    // Long after they connected, putting them in makes macOS move the mic.
    [audio setDefault:airPodsMic.platformID role:APBDeviceRoleInput];
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentInputID, scarlett.platformID);
    XCTAssertEqual(model.currentOutputID, airPods.platformID);
}

- (void)testAirPodsTakingTheOutputBackInManualModeIsSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", @"MacBook Air Speakers");
    APBAudioDevice *airPods = APBOutput(2, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(3, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(4, @"scarlett", @"Scarlett Solo USB");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, airPods, airPodsMic, scarlett ];
    [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
    [audio setDefault:scarlett.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model selectManually:speaker];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [audio.selections removeAllObjects];

    // Seen in a real trace: seconds after the pick, with nothing connecting,
    // macOS moves the output and microphone to the AirPods in the user's ears.
    [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [audio setDefault:airPodsMic.platformID role:APBDeviceRoleInput];
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
    XCTAssertEqual(model.currentInputID, scarlett.platformID);
    XCTAssertEqualObjects(audio.selectedIDs, (@[ @(speaker.platformID), @(scarlett.platformID) ]));
}

- (void)testAirPodsTakingBothDevicesAtOnceInManualModeAreBothSwitchedBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", @"MacBook Air Speakers");
    APBAudioDevice *airPods = APBOutput(2, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(3, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(4, @"scarlett", @"Scarlett Solo USB");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, airPods, airPodsMic, scarlett ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [audio setDefault:scarlett.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // Seen in a real trace: macOS moves both 3 ms apart, so the input has
    // already moved when the output's event is handled.
    [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
    [audio setDefault:airPodsMic.platformID role:APBDeviceRoleInput];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertEqual(model.currentOutputID, speaker.platformID);
    XCTAssertEqual(model.currentInputID, scarlett.platformID);
    XCTAssertEqual([audio defaultDeviceForRole:APBDeviceRoleOutput], speaker.platformID);
    XCTAssertEqual([audio defaultDeviceForRole:APBDeviceRoleInput], scarlett.platformID);
}

- (void)testAPickInControlCenterStaysInManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, airPods ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];

    [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, airPods.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testANewlyConnectedOutputStaysInManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[ speaker, airPods ];
    [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(model.currentOutputID, airPods.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testMacOSTakingTheOutputAgainAfterASwitchBackIsLeftAndNamed {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *airPods = APBOutput(2, @"airpods", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, airPods ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    // Smart Routing retries about 4 seconds after each switch back.
    for (int attempt = 0; attempt < 3; attempt++) {
        [audio setDefault:airPods.platformID role:APBDeviceRoleOutput];
        [model handleDefaultChanged:APBDeviceRoleOutput];
    }

    XCTAssertEqualObjects(audio.selectedIDs, @[ @(speaker.platformID) ]);
    XCTAssertEqualObjects(model.takeoverDevice.uid, airPods.uid);

    [model selectManually:speaker];

    XCTAssertNil(model.takeoverDevice);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

- (void)testAutomaticModeKeepsAMicrophoneMacOSTakesAgainAfterASwitchBack {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *airPods = APBOutput(1, @"airpods-out", @"AirPods Pro");
    APBAudioDevice *airPodsMic = APBInput(2, @"airpods-in", @"AirPods Pro");
    APBAudioDevice *scarlett = APBInput(3, @"scarlett", @"Scarlett Solo USB");
    [[[APBPriorityStore alloc] initWithDefaults:defaults] savePriorities:@[ scarlett, airPodsMic ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ airPods, airPodsMic, scarlett ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    for (int attempt = 0; attempt < 3; attempt++) {
        [audio setDefault:airPodsMic.platformID role:APBDeviceRoleInput];
        [model handleDefaultChanged:APBDeviceRoleInput];
    }

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentInputID, airPodsMic.platformID);
    XCTAssertEqualObjects(model.takeoverDevice.uid, airPodsMic.uid);
}

- (void)testOutputMovingBeforeTheDisconnectArrivesKeepsAutomaticOn {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    audio.catalog = @[ speaker, APBOutput(2, @"headphones", @"AirPods Pro") ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    // Seen in a real trace: the default moves to the speakers 40 ms before
    // the AirPods leave the device list.
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    audio.catalog = @[ speaker ];
    [model handleDevicesChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

- (void)testNewHeadphoneBecomesAutomaticOutput {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ speaker ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = @[ speaker, headphones ];
    [model handleDevicesChanged];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(headphones.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testLosingAndReturningHeadphonesSwitchesAutomaticOutput {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = @[ speaker ];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(speaker.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategorySpeaker);

    audio.catalog = @[ speaker, headphones ];
    [model handleDevicesChanged];

    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(headphones.platformID));
    XCTAssertEqual(model.activeOutputCategory, APBOutputCategoryHeadphone);
}

- (void)testManualModeNeverChangesDevicesAutomatically {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    [[APBPriorityStore alloc] initWithDefaults:defaults].isManualMode = YES;
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBOutput(1, @"speaker", nil) ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:APBOutput(2, @"headphones", @"AirPods Pro")];
    [model handleDevicesChanged];

    XCTAssertEqual(audio.selections.count, 0u);
    XCTAssertTrue(model.isManualMode);
}

- (void)testExplicitChoiceTurnsAutomaticOffUntilReenabled {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model selectManually:speaker];
    [audio.selections removeAllObjects];
    [model handleDevicesChanged];

    XCTAssertTrue(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
    XCTAssertEqual(audio.selections.count, 0u);

    [model setManualMode:NO];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, headphones.platformID);
    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(headphones.platformID));
}

- (void)testAppDefaultChangeEchoKeepsAutomaticOn {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headphones = APBOutput(1, @"headphones", @"AirPods Pro");
    audio.catalog = @[ headphones ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, headphones.platformID);
}

- (void)testSystemFallbackAfterDisconnectKeepsAutomaticOn {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    audio.catalog = @[ speaker, APBOutput(2, @"headphones", @"AirPods Pro") ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    audio.catalog = @[ speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

- (void)testSystemChoiceDuringConnectionStillAppliesPriority {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *preferred = APBOutput(2, @"preferred", @"AirPods Pro");
    APBAudioDevice *newcomer = APBOutput(3, @"newcomer", @"USB Headphones");
    audio.catalog = @[ speaker, preferred ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    audio.catalog = @[ speaker, preferred, newcomer ];
    [audio setDefault:newcomer.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, preferred.platformID);
    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(preferred.platformID));
}

- (void)testUnlinkedHeadsetIsSkippedDuringAutomaticSelection {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *unlinked = APBOutput(1, @"jabra", @"Jabra Link 380");
    APBAudioDevice *fallback = APBOutput(2, @"airpods", @"AirPods Pro");
    audio.catalog = @[ unlinked, fallback ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:@"jabra"];
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:@"jabra"] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);

    [model start];

    XCTAssertEqualObjects(audio.selectedIDs.lastObject, @(fallback.platformID));
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
    audio.catalog = @[ jabra ];
    APBAppModel *stranded = APBTestModel(audio, defaults, nil, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:@"jabra"] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);
    [stranded start];
    XCTAssertEqual(stranded.currentOutputID, jabra.platformID);
    XCTAssertTrue(stranded.isActiveOutputLinkDown);

    // Every other link state leaves the warning off, including the transient
    // checking window and the two states that mean "not known".
    for (NSNumber *state in @[ @(APBLinkStateUp), @(APBLinkStateChecking), @(APBLinkStateUnknown),
                               @(APBLinkStateMonitoringUnavailable) ]) {
        APBFakeAudio *other = [[APBFakeAudio alloc] init];
        other.catalog = @[ jabra ];
        APBAppModel *model = APBTestModel(other, defaults, nil, ^APBLinkState(APBAudioDevice *device) {
            return state.integerValue;
        }, nil);
        [model start];
        XCTAssertFalse(model.isActiveOutputLinkDown, @"state %@", state);
    }

    // No selected output at all.
    APBAppModel *idle = APBTestModel([[APBFakeAudio alloc] init], defaults, nil, nil, nil);
    [idle start];
    XCTAssertNil(idle.currentOutputDevice);
    XCTAssertFalse(idle.isActiveOutputLinkDown);
}

- (void)testFullDuplexMuteStateIsRoleScoped {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(7, @"shared", nil), APBOutput(7, @"shared", nil) ];
    [audio.muted addObject:@"input:7"];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertTrue([model isMuted:APBInput(7, @"shared", nil)]);
    XCTAssertFalse([model isMuted:APBOutput(7, @"shared", nil)]);
}

- (void)testReduceMotionKeepsMutedMicrophoneIndicatorSteady {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *microphone = APBInput(1, @"microphone", nil);
    audio.catalog = @[ microphone ];
    [audio setDefault:microphone.platformID role:APBDeviceRoleInput];
    [audio.muted addObject:@"input:1"];
    APBAppModel *model = [[APBAppModel alloc] initWithStore:[[APBPriorityStore alloc] initWithDefaults:APBIsolatedDefaults()]
                                                      audio:audio
                                                   isUsable:^BOOL(APBAudioDevice *device) { return YES; }
                                                  linkState:^APBLinkState(APBAudioDevice *device) { return APBLinkStateNone; }
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
// mute on the main element (macOS 26, probed 2026-09-26), which the fake
// models by default. ZoomAudioDevice has none and rests at zero volume.

- (void)testMicrophoneMuteMovesToTheNewMicrophone {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headset = APBInput(1, @"headset", @"Jabra Link 380");
    APBAudioDevice *builtIn = APBInput(2, @"builtin", @"MacBook Pro Microphone");
    audio.catalog = @[ headset, builtIn ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);

    audio.catalog = @[ builtIn ];
    [model handleDevicesChanged];
    XCTAssertEqual(model.currentInputID, 2u);
    XCTAssertTrue(model.isMicrophoneMuted);
    XCTAssertTrue([audio.muted containsObject:@"input:2"]);

    audio.catalog = @[ headset, builtIn ];
    [model handleDevicesChanged];
    XCTAssertEqual(model.currentInputID, 1u);
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);

    [model selectManually:builtIn];
    [model handleDefaultChanged:APBDeviceRoleInput];
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:2"]);
    XCTAssertTrue(model.isActiveInputMuted);
}

- (void)testMuteFallsBackToZeroVolumeAndRestoresTheLevel {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"zoom", @"ZoomAudioDevice") ];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @0.627f;
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];
    XCTAssertEqualObjects(audio.inputVolumes[@1], @0.0f);
    XCTAssertTrue(model.isActiveInputMuted);
    XCTAssertNotNil([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes[@"zoom"]);

    [model setMicrophoneMuted:NO];
    XCTAssertEqualObjects(audio.inputVolumes[@1], @0.627f);
    XCTAssertFalse(model.isActiveInputMuted);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0u);
}

- (void)testAVirtualMicrophoneRestingAtZeroVolumeIsNotShownMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"zoom", @"ZoomAudioDevice") ];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @0.0f;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);

    [model start];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertFalse(model.isActiveInputMuted);
}

- (void)testUnmutingElsewhereClearsTheMute {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil) ];
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [audio.muted removeObject:@"input:1"];
    [model refreshMute];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0u);
}

- (void)testAHeadsetMuteButtonIsFollowed {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"headset", nil) ];
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
    audio.catalog = @[ headset, builtIn ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    audio.catalog = @[ builtIn ];
    [model handleDevicesChanged];
    [model setMicrophoneMuted:NO];
    audio.catalog = @[ headset, builtIn ];
    [model handleDevicesChanged];

    XCTAssertEqual(model.currentInputID, 1u);
    XCTAssertEqual(audio.muted.count, 0u);
    XCTAssertFalse(model.isMicrophoneMuted);
}

- (void)testQuittingRestoresAppliedMutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil) ];
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [model stop];

    XCTAssertEqual(audio.muted.count, 0u);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].appliedMicrophoneMutes.count, 0u);
}

- (void)testRecordingIsReportedForTheCurrentMicrophoneOnly {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil), APBInput(2, @"other", nil) ];
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
    audio.catalog = @[ speaker ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    NSMutableArray *notices = [NSMutableArray array];
    model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) { [notices addObject:devices]; };

    audio.catalog = @[ speaker, APBOutput(2, @"headphones", @"AirPods Pro") ];
    [model handleDevicesChanged];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(APBUIDLists(notices), @[ @[ @"headphones" ] ]);
}

- (void)testManualSelectionShowsNoSwitchNotice {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    audio.catalog = @[ speaker, APBOutput(2, @"headphones", @"AirPods Pro") ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    NSMutableArray *notices = [NSMutableArray array];
    model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) { [notices addObject:devices]; };

    [model selectManually:speaker];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(notices.count, 0u);
}

- (void)testStartupShowsNoSwitchNotice {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil), APBOutput(2, @"speaker", nil) ];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    NSMutableArray *notices = [NSMutableArray array];
    model.onAutomaticSwitch = ^(NSArray<APBAudioDevice *> *devices) { [notices addObject:devices]; };

    [model start];

    XCTAssertEqual(notices.count, 0u);
}

- (void)testMovingTheMicrophoneLevelWhileMutedUnmutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"mic", nil) ];
    audio.inputVolumes[@1] = @0.627f;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    [model setMicrophoneMuted:YES];

    [model setMicrophoneLevel:0.4f];

    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual(audio.muted.count, 0u);
    XCTAssertEqualObjects(audio.inputVolumes[@1], @0.4f);
    XCTAssertEqual(model.microphoneLevel, 0.4f);
}

- (void)testAZeroVolumeMuteShowsTheLevelItWillRestore {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"zoom", @"ZoomAudioDevice") ];
    [audio.noMuteProperty addObject:@1];
    audio.inputVolumes[@1] = @0.627f;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model setMicrophoneMuted:YES];

    XCTAssertEqualObjects(audio.inputVolumes[@1], @0.0f);
    XCTAssertEqual(model.microphoneLevel, 0.627f);
}

- (void)testOutputMuteTogglesAndRaisingTheVolumeUnmutes {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBOutput(1, @"speaker", nil) ];
    [audio setDefault:1 role:APBDeviceRoleOutput];
    audio.volume = @0.43f;
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];
    XCTAssertTrue(model.isOutputMutable);

    [model setOutputMuted:YES];
    XCTAssertTrue(model.isActiveOutputMuted);

    [model setVolume:0.5f];
    XCTAssertFalse(model.isActiveOutputMuted);
    XCTAssertEqual(audio.muted.count, 0u);
}

- (void)testAMicrophoneWithNeitherMuteNorLevelCannotBeMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"scarlett", @"Scarlett Solo USB") ];
    [audio setDefault:1 role:APBDeviceRoleInput];
    [audio.noMuteProperty addObject:@1];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    XCTAssertFalse(model.isMicrophoneLevelControllable);
    XCTAssertFalse(model.isMicrophoneMutable);
}

- (void)testAnOutputWithNeitherVolumeNorMuteCannotBeControlled {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBOutput(1, @"scarlett", @"Scarlett Solo USB") ];
    [audio setDefault:1 role:APBDeviceRoleOutput];
    [audio.noMuteProperty addObject:@1];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    XCTAssertFalse(model.isVolumeControllable);
    XCTAssertFalse(model.isOutputMutable);
}

- (void)testURLCommandsMuteOnlyAMicrophoneThatCanBeMuted {
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ APBInput(1, @"headset", @"USB Headset") ];
    [audio setDefault:1 role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, APBIsolatedDefaults(), nil, nil, nil);
    [model start];

    [model performCommand:APBURLCommandToggleMicMute];
    XCTAssertTrue(model.isMicrophoneMuted);
    XCTAssertEqualObjects(audio.muted, [NSSet setWithObject:@"input:1"]);
    [model performCommand:APBURLCommandMuteMic];
    XCTAssertTrue(model.isMicrophoneMuted);
    [model performCommand:APBURLCommandToggleMicMute];
    XCTAssertFalse(model.isMicrophoneMuted);
    XCTAssertEqual(audio.muted.count, 0u);
    [model performCommand:APBURLCommandUnmuteMic];
    XCTAssertFalse(model.isMicrophoneMuted);

    [audio.noMuteProperty addObject:@1];
    [model refreshVolume];
    [model performCommand:APBURLCommandMuteMic];
    XCTAssertFalse(model.isMicrophoneMuted);
    [model performCommand:APBURLCommandToggleMicMute];
    XCTAssertFalse(model.isMicrophoneMuted);
}

@end
