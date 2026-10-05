#import "APBTestSupport.h"
#import "APBJabra.h"

@interface APBSelectionBehaviorTests : XCTestCase
@end

/// A physically paired output and input, like a USB headset's two halves.
static void APBDualRole(BOOL isVirtual, NSString *serial, UInt32 outputID, UInt32 inputID,
                        APBAudioDevice **output, APBAudioDevice **input) {
    NSString *name = isVirtual ? @"ZoomAudioDevice" : @"USB Headset";
    NSString *baseUID = isVirtual
        ? @"zoom.us.zoomaudiodevice.001"
        : [NSString stringWithFormat:@"AppleUSBAudioEngine:Unknown Manufacturer:USB Headset:%@", serial];
    *output = [[APBAudioDevice alloc] initWithPlatformID:outputID
                                                     uid:isVirtual ? baseUID : [baseUID stringByAppendingString:@":1"]
                                                    name:name
                                                    role:APBDeviceRoleOutput
                                            isConnected:YES
                                              isVirtual:isVirtual
                                       declaredCategory:APBOutputCategoryNone
                                        isDisplayOutput:NO
                                          transportType:0];
    *input = [[APBAudioDevice alloc] initWithPlatformID:inputID
                                                    uid:isVirtual ? baseUID : [baseUID stringByAppendingString:@":2"]
                                                   name:name
                                                   role:APBDeviceRoleInput
                                           isConnected:YES
                                             isVirtual:isVirtual
                                      declaredCategory:APBOutputCategoryNone
                                       isDisplayOutput:NO
                                         transportType:0];
}

@implementation APBSelectionBehaviorTests

- (void)testAutomaticDecisionExplainsPoweredOffHeadphone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[ speaker, jabra ];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return ![device.uid isEqualToString:jabra.uid];
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:jabra.uid] ? APBLinkStateDown : APBLinkStateNone;
    }, nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, speaker.uid);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped.device.uid, jabra.uid);
    XCTAssertEqual(model.automaticOutputDecision.skipped.reason, APBOutputSkipReasonOff);
}

- (void)testAutomaticDecisionFailsOpenForUnknownHeadphone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[ speaker, jabra ];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return YES;
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:jabra.uid] ? APBLinkStateUnknown : APBLinkStateNone;
    }, nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, jabra.uid);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticSelectionWaitsWhileADongleIsStillBeingChecked {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[ speaker, jabra ];
    // The dongle lies about its link right after enumeration, so the monitor
    // reports `.checking` until its first authoritative answer arrives.
    __block APBLinkState linkState = APBLinkStateChecking;
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return [device.uid isEqualToString:jabra.uid]
            ? [APBJabraLink allowsSelectionWhenSupported:YES state:linkState]
            : YES;
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:jabra.uid] ? linkState : APBLinkStateNone;
    }, nil);

    [model start];

    // Nothing is routed yet: choosing the speaker now would only be undone.
    XCTAssertTrue(model.automaticOutputDecision.isDeferred);
    XCTAssertNil(model.automaticOutputDecision.target);
    XCTAssertEqual(audio.selections.count, 0u);

    // A row reading `linkStateForDevice:` must be told to redraw as soon as the
    // dongle's verdict changes, not only when something unrelated (like
    // hover) happens to re-run its body afterward.
    __block BOOL didInvalidate = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:APBAppModelDidChangeNotification
                                                                     object:model
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *note) {
        didInvalidate = YES;
    }];
    (void)[model linkStateForDevice:jabra];

    // The answer arrives: the headset really is off, so the speaker wins.
    linkState = APBLinkStateDown;
    [model handleLinkChanged];

    XCTAssertTrue(APBWaitUntil(1, ^BOOL { return didInvalidate; }));
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    XCTAssertFalse(model.automaticOutputDecision.isDeferred);
    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, speaker.uid);
    XCTAssertTrue([audio.selectedIDs containsObject:@(speaker.platformID)]);
    XCTAssertFalse([audio.selectedIDs containsObject:@(jabra.platformID)]);
}

- (void)testCheckingDoesNotDeferDevicesAlreadyRuledOut {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    // Never-auto-select by the user, so its link state is irrelevant and
    // waiting for it would stall selection for nothing.
    [store setNeverUse:jabra value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, jabra ];
    APBAppModel *model = APBTestModel(audio, defaults, ^BOOL(APBAudioDevice *device) {
        return YES;
    }, ^APBLinkState(APBAudioDevice *device) {
        return [device.uid isEqualToString:jabra.uid] ? APBLinkStateChecking : APBLinkStateNone;
    }, nil);

    [model start];

    XCTAssertFalse(model.automaticOutputDecision.isDeferred);
    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, speaker.uid);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped.device.uid, jabra.uid);
    XCTAssertEqual(model.automaticOutputDecision.skipped.reason, APBOutputSkipReasonNeverAutoSelect);
}

- (void)testAutomaticDecisionExplainsNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    [store setNeverUse:headphones value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, speaker.uid);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped.device.uid, headphones.uid);
    XCTAssertEqual(model.automaticOutputDecision.skipped.reason, APBOutputSkipReasonNeverAutoSelect);
}

- (void)testAutomaticDecisionIgnoresHiddenRowsShownForManagement {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    [store hide:headphones inCategory:APBOutputCategoryHeadphone];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker, headphones ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    model.showAll = YES;

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target.uid, speaker.uid);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticDecisionStaysQuietForActiveTopDeviceAndManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headphones = APBOutput(1, @"headphones", @"AirPods Pro");
    audio.catalog = @[ headphones ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertEqualObjects(model.currentOutputDevice.uid, headphones.uid);
    XCTAssertNil(model.automaticOutputDecision.skipped);

    [model setManualMode:YES];

    XCTAssertNil(model.automaticOutputDecision.target);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticSelectionPairsAnAlreadyCurrentOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[ macMic, pairedInput ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqualObjects(audio.selectedRoles, (@[ @(APBDeviceRoleInput) ]));
    XCTAssertEqualObjects(audio.selectedIDs, (@[ @(pairedInput.platformID) ]));
}

- (void)testManualSelectionPairsPhysicalOutputAndInput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:pairedOutput];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqualObjects(audio.selectedRoles, (@[ @(APBDeviceRoleOutput), @(APBDeviceRoleInput) ]));
}

- (void)testSoundSettingsOutputSelectionPairsItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *airPods = APBOutput(3, @"airpods", @"AirPods Pro");
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[ macMic, pairedInput ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ airPods, pairedOutput, pairedInput, macMic ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];
    [audio.selections removeAllObjects];

    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqualObjects(audio.selectedRoles, (@[ @(APBDeviceRoleInput) ]));
    XCTAssertEqualObjects(audio.selectedIDs, (@[ @(pairedInput.platformID) ]));
}

- (void)testFailedOutputSelectionDoesNotMoveMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    audio.selectionSucceeds = NO;
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertFalse([model select:pairedOutput]);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testAutomaticOutputFailureDoesNotMoveItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[ macMic, pairedInput ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    [audio.failedSelectionRoles addObject:@(APBDeviceRoleOutput)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, 0u);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testAutomaticInputDoesNotPairANeverAutoSelectCurrentOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:pairedOutput value:YES];
    [store savePriorities:@[ macMic, pairedInput ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testSelectingAMicrophoneAlsoSelectsItsOutputWhenEnabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:pairedInput];

    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    // Exactly the mic then its output: a returning cycle would fail this
    // count instead of only hanging.
    XCTAssertEqualObjects(audio.selectedRoles, (@[ @(APBDeviceRoleInput), @(APBDeviceRoleOutput) ]));
}

- (void)testSelectingAMicrophoneLeavesOutputAloneWhenDisabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    store.selectsPairedDevice = NO;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:pairedInput];

    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

- (void)testSelectOnlyLeavesOutputAloneWhenPairedSelectionIsEnabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectOnly:pairedInput];

    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

- (void)testSelectOnlyOutputSurvivesItsDefaultChangeEcho {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBAudioDevice *macMic = APBInput(102, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker, macMic ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    // The later changes are the user's own, made in Sound Settings.
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];

    [model selectOnly:pairedOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, macMic.platformID);

    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
}

- (void)testSelectOnlyDoesNotSuppressPairingForARecycledDeviceID {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectOnly:pairedOutput];

    // CoreAudio reuses platform IDs, so another headset can arrive holding the
    // one "Output only" was applied to, and it still pairs normally.
    APBAudioDevice *replacementOutput = nil, *replacementInput = nil;
    APBDualRole(NO, @"replacement", pairedOutput.platformID, 201, &replacementOutput, &replacementInput);
    audio.catalog = @[ replacementOutput, replacementInput, speaker ];
    [audio setDefault:replacementOutput.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(model.currentInputID, replacementInput.platformID);
}

- (void)testAutomaticMicrophonePriorityDoesNotOverrideAnUnrelatedAutomaticOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    // Forced rather than left to name detection, so this test exercises
    // priority order rather than headphone-keyword classification.
    [store setCategory:APBOutputCategorySpeaker forDevice:pairedOutput];
    APBAudioDevice *macSpeaker = APBOutput(2, @"mac-speaker", nil);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[ macSpeaker, pairedOutput ] category:APBOutputCategorySpeaker];
    [store savePriorities:@[ pairedInput, macMic ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ macSpeaker, macMic, pairedOutput, pairedInput ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    // Output and microphone priority lists stay independent unless the
    // current output is itself the anchor: a microphone chosen purely by its
    // own priority must not reach back and move an unrelated output that
    // automatic selection already, separately, decided on.
    XCTAssertEqual(model.currentOutputID, macSpeaker.platformID);
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
}

- (void)testExplicitPairedSelectionWorksWhenDefaultIsSingleDevice {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    store.selectsPairedDevice = NO;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectWithPairedDevice:pairedInput];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
}

- (void)testSelectWithPairedDeviceStopsAtAFailedOutputSelection {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    [audio.failedSelectionRoles addObject:@(APBDeviceRoleOutput)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectWithPairedDevice:pairedInput];

    XCTAssertEqual(model.currentInputID, macMic.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testPairingSkipsMissingHiddenVirtualAndDisabledPartners {
    NSDictionary *configurations = @[
        @{ @"virtual": @NO, @"hidden": @YES, @"enabled": @YES },
        @{ @"virtual": @YES, @"hidden": @NO, @"enabled": @YES },
        @{ @"virtual": @NO, @"hidden": @NO, @"enabled": @NO },
    ];
    for (NSDictionary *configuration in configurations) {
        NSUserDefaults *defaults = APBIsolatedDefaults();
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        store.isManualMode = YES;
        store.selectsPairedDevice = [configuration[@"enabled"] boolValue];
        APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
        APBDualRole([configuration[@"virtual"] boolValue], @"serial", 1, 101, &pairedOutput, &pairedInput);
        APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
        if ([configuration[@"hidden"] boolValue]) {
            [store hide:pairedInput];
        }
        APBFakeAudio *audio = [[APBFakeAudio alloc] init];
        audio.catalog = @[ pairedOutput, pairedInput, macMic ];
        [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
        APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
        [model start];

        [model selectManually:pairedOutput];

        XCTAssertEqual(model.currentInputID, macMic.platformID);
    }

    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *outputOnly = APBOutput(1, @"output-only", nil);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ outputOnly, macMic ];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:outputOnly];

    XCTAssertEqual(model.currentInputID, macMic.platformID);
}

- (void)testAutomaticPairingRespectsMicrophoneNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:pairedInput value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqual(model.currentOutputID, pairedOutput.platformID);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
}

- (void)testAutomaticOutputEchoRespectsMicrophoneNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:pairedInput value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testDisablingPairingReappliesAutomaticMicrophonePriority {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[ macMic, pairedInput ] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, macMic ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    XCTAssertEqual(model.currentInputID, pairedInput.platformID);

    [model setSelectsPairedDevice:NO];

    XCTAssertFalse(model.selectsPairedDevice);
    XCTAssertFalse(model.store.selectsPairedDevice);
    XCTAssertEqual(model.currentInputID, macMic.platformID);
}

- (void)testExternalNeverAutoSelectOutputStillPairsItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *pairedOutput = nil, *pairedInput = nil;
    APBDualRole(NO, @"serial", 1, 101, &pairedOutput, &pairedInput);
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBAudioDevice *macMic = APBInput(3, @"mac-mic", nil);
    [store setNeverUse:pairedOutput value:YES];
    [store setNeverUse:speaker value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ pairedOutput, pairedInput, speaker, macMic ];
    [audio setDefault:speaker.platformID role:APBDeviceRoleOutput];
    [audio setDefault:macMic.platformID role:APBDeviceRoleInput];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [audio setDefault:pairedOutput.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqual(model.currentInputID, pairedInput.platformID);
}

- (void)testDeviceCallbackBeforeDefaultCallbackDoesNotEnableManual {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *newcomer = APBOutput(2, @"new", @"USB Headphones");
    [store setNeverUse:newcomer value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[ speaker ];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:newcomer];
    [audio setDefault:newcomer.platformID role:APBDeviceRoleOutput];
    [model handleDevicesChanged];
    [audio setDefault:newcomer.platformID role:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqual(model.currentOutputID, speaker.platformID);
}

@end
