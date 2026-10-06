#import <XCTest/XCTest.h>
#import "TestSupport.h"

/// A headset's output and input halves, which share a physical identity.
@interface APBDualRole : NSObject
@property (nonatomic, strong) APBAudioDevice *output;
@property (nonatomic, strong) APBAudioDevice *input;
@end

@implementation APBDualRole
@end

static APBDualRole *DualRoleWith(BOOL isVirtual, NSString *serial, UInt32 outputID, UInt32 inputID) {
    NSString *name = isVirtual ? @"ZoomAudioDevice" : @"USB Headset";
    NSString *baseUID = isVirtual
        ? @"zoom.us.zoomaudiodevice.001"
        : [NSString stringWithFormat:@"AppleUSBAudioEngine:Unknown Manufacturer:USB Headset:%@", serial];
    APBDualRole *pair = [[APBDualRole alloc] init];
    pair.output = [[APBAudioDevice alloc] initWithPlatformID:outputID
                                                         uid:isVirtual ? baseUID : [baseUID stringByAppendingString:@":1"]
                                                        name:name
                                                        role:APBDeviceRoleOutput
                                                 isConnected:YES
                                                   isVirtual:isVirtual
                                            declaredCategory:APBOutputCategoryNone
                                             isDisplayOutput:NO
                                               transportType:0];
    pair.input = [[APBAudioDevice alloc] initWithPlatformID:inputID
                                                        uid:isVirtual ? baseUID : [baseUID stringByAppendingString:@":2"]
                                                       name:name
                                                       role:APBDeviceRoleInput
                                                isConnected:YES
                                                  isVirtual:isVirtual
                                           declaredCategory:APBOutputCategoryNone
                                            isDisplayOutput:NO
                                              transportType:0];
    return pair;
}

/// `dualRole()` with the Swift default arguments.
static APBDualRole *DualRole(void) {
    return DualRoleWith(NO, @"serial", 1, 101);
}

@interface SelectionBehaviorTests : XCTestCase
@end

@implementation SelectionBehaviorTests

- (void)testAutomaticDecisionExplainsPoweredOffHeadphone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[speaker, jabra];
    APBAppModel *model = APBTestModel(audio, defaults,
        ^BOOL(APBAudioDevice *device) { return ![device.uid isEqualToString:jabra.uid]; },
        ^APBLinkState(APBAudioDevice *device) {
            return [device.uid isEqualToString:jabra.uid] ? APBLinkStateDown : APBLinkStateNone;
        },
        nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target, speaker);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped,
                          [[APBSkippedOutput alloc] initWithDevice:jabra reason:APBOutputSkipReasonOff]);
}

- (void)testAutomaticDecisionFailsOpenForUnknownHeadphone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[speaker, jabra];
    APBAppModel *model = APBTestModel(audio, defaults,
        ^BOOL(APBAudioDevice *device) { return YES; },
        ^APBLinkState(APBAudioDevice *device) {
            return [device.uid isEqualToString:jabra.uid] ? APBLinkStateUnknown : APBLinkStateNone;
        },
        nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target, jabra);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticSelectionWaitsWhileADongleIsStillBeingChecked {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *jabra = APBOutput(2, @"jabra", @"Jabra Link 380");
    audio.catalog = @[speaker, jabra];
    // The dongle lies about its link right after enumeration, so the monitor
    // reports `.checking` until its first authoritative answer arrives.
    __block APBLinkState linkState = APBLinkStateChecking;
    APBAppModel *model = APBTestModel(audio, defaults,
        ^BOOL(APBAudioDevice *device) {
            return [device.uid isEqualToString:jabra.uid]
                ? [APBJabraLink allowsSelectionIsSupported:YES state:linkState]
                : YES;
        },
        ^APBLinkState(APBAudioDevice *device) {
            return [device.uid isEqualToString:jabra.uid] ? linkState : APBLinkStateNone;
        },
        nil);

    [model start];

    // Nothing is routed yet: choosing the speaker now would only be undone.
    XCTAssertTrue(model.automaticOutputDecision.isDeferred);
    XCTAssertNil(model.automaticOutputDecision.target);
    XCTAssertEqual(audio.selections.count, 0u);

    // A row reading `linkState(for:)` must be told to redraw as soon as the
    // dongle's verdict changes, not only when something unrelated (like
    // hover) happens to re-run its body afterward.
    // Objective-C: the model's change notification stands in for
    // `withObservationTracking`. Drain first so a change posted by `start`
    // cannot satisfy the check.
    (void)[model linkStateForDevice:jabra];
    APBDrainMainQueue();
    __block BOOL didInvalidate = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:APBAppModelDidChangeNotification
                                                                  object:model
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *note) {
        didInvalidate = YES;
    }];

    // The answer arrives: the headset really is off, so the speaker wins.
    linkState = APBLinkStateDown;
    [model handleLinkChanged];
    APBDrainMainQueue();
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    XCTAssertTrue(didInvalidate);
    XCTAssertFalse(model.automaticOutputDecision.isDeferred);
    XCTAssertEqualObjects(model.automaticOutputDecision.target, speaker);
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
    audio.catalog = @[speaker, jabra];
    APBAppModel *model = APBTestModel(audio, defaults,
        ^BOOL(APBAudioDevice *device) { return YES; },
        ^APBLinkState(APBAudioDevice *device) {
            return [device.uid isEqualToString:jabra.uid] ? APBLinkStateChecking : APBLinkStateNone;
        },
        nil);

    [model start];

    XCTAssertFalse(model.automaticOutputDecision.isDeferred);
    XCTAssertEqualObjects(model.automaticOutputDecision.target, speaker);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped,
                          [[APBSkippedOutput alloc] initWithDevice:jabra reason:APBOutputSkipReasonNeverAutoSelect]);
}

- (void)testAutomaticDecisionExplainsNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    [store setNeverUse:headphones value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target, speaker);
    XCTAssertEqualObjects(model.automaticOutputDecision.skipped,
                          [[APBSkippedOutput alloc] initWithDevice:headphones reason:APBOutputSkipReasonNeverAutoSelect]);
}

- (void)testAutomaticDecisionIgnoresHiddenRowsShownForManagement {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    [store hide:headphones inCategory:APBOutputCategoryHeadphone];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    model.showAll = YES;

    [model start];

    XCTAssertEqualObjects(model.automaticOutputDecision.target, speaker);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticDecisionStaysQuietForActiveTopDeviceAndManualMode {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *headphones = APBOutput(1, @"headphones", @"AirPods Pro");
    audio.catalog = @[headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertEqualObjects(model.currentOutputDevice, headphones);
    XCTAssertNil(model.automaticOutputDecision.skipped);

    [model setManualMode:YES];

    XCTAssertNil(model.automaticOutputDecision.target);
    XCTAssertNil(model.automaticOutputDecision.skipped);
}

- (void)testAutomaticSelectionPairsAnAlreadyCurrentOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[macMic, paired.input] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(audio.selectedRoles, @[@(APBDeviceRoleInput)]);
    XCTAssertEqualObjects(audio.selectedIDs, @[@(paired.input.platformID)]);
}

- (void)testManualSelectionPairsPhysicalOutputAndInput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:paired.output];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(audio.selectedRoles, (@[@(APBDeviceRoleOutput), @(APBDeviceRoleInput)]));
}

- (void)testSoundSettingsOutputSelectionPairsItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *airPods = APBOutput(3, @"airpods", @"AirPods Pro");
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[macMic, paired.input] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[airPods, paired.output, paired.input, macMic];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];
    [audio.selections removeAllObjects];

    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(audio.selectedRoles, @[@(APBDeviceRoleInput)]);
    XCTAssertEqualObjects(audio.selectedIDs, @[@(paired.input.platformID)]);
}

- (void)testFailedOutputSelectionDoesNotMoveMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    audio.selectionSucceeds = NO;
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertFalse([model select:paired.output]);
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testAutomaticOutputFailureDoesNotMoveItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[macMic, paired.input] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    [audio.failedSelectionRoles addObject:@(APBDeviceRoleOutput)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertNil(model.currentOutputID);
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testAutomaticInputDoesNotPairANeverAutoSelectCurrentOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:paired.output value:YES];
    [store savePriorities:@[macMic, paired.input] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testSelectingAMicrophoneAlsoSelectsItsOutputWhenEnabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:paired.input];

    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    // Exactly the mic then its output: a returning cycle would fail this
    // count instead of only hanging.
    XCTAssertEqualObjects(audio.selectedRoles, (@[@(APBDeviceRoleInput), @(APBDeviceRoleOutput)]));
}

- (void)testSelectingAMicrophoneLeavesOutputAloneWhenDisabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    store.selectsPairedDevice = NO;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:paired.input];

    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testSelectOnlyLeavesOutputAloneWhenPairedSelectionIsEnabled {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectOnly:paired.input];

    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testSelectOnlyOutputSurvivesItsDefaultChangeEcho {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBAudioDevice *macMic = APBInput(102, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker, macMic];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    // The later changes are the user's own, made in Sound Settings.
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];

    [model selectOnly:paired.output];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));

    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
}

- (void)testSelectOnlyDoesNotSuppressPairingForARecycledDeviceID {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectOnly:paired.output];

    // CoreAudio reuses platform IDs, so another headset can arrive holding the
    // one "Output only" was applied to, and it still pairs normally.
    APBDualRole *replacement = DualRoleWith(NO, @"replacement", paired.output.platformID, 201);
    audio.catalog = @[replacement.output, replacement.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(replacement.output.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(model.currentInputID, @(replacement.input.platformID));
}

- (void)testAutomaticMicrophonePriorityDoesNotOverrideAnUnrelatedAutomaticOutput {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    // Forced rather than left to name detection, so this test exercises
    // priority order rather than headphone-keyword classification.
    [store setCategory:APBOutputCategorySpeaker forDevice:paired.output];
    APBAudioDevice *macSpeaker = APBOutput(2, @"mac-speaker", nil);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[macSpeaker, paired.output] category:APBOutputCategorySpeaker];
    [store savePriorities:@[paired.input, macMic] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[macSpeaker, macMic, paired.output, paired.input];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    // Output and microphone priority lists stay independent unless the
    // current output is itself the anchor: a microphone chosen purely by its
    // own priority must not reach back and move an unrelated output that
    // automatic selection already, separately, decided on.
    XCTAssertEqualObjects(model.currentOutputID, @(macSpeaker.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
}

- (void)testExplicitPairedSelectionWorksWhenDefaultIsSingleDevice {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    store.selectsPairedDevice = NO;
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectWithPairedDevice:paired.input];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
}

- (void)testSelectWithPairedDeviceStopsAtAFailedOutputSelection {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    [audio.failedSelectionRoles addObject:@(APBDeviceRoleOutput)];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectWithPairedDevice:paired.input];

    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testPairingSkipsMissingHiddenVirtualAndDisabledPartners {
    // (virtual, hidden, enabled)
    const BOOL configurations[3][3] = {
        {NO, YES, YES},
        {YES, NO, YES},
        {NO, NO, NO},
    };
    for (int index = 0; index < 3; index++) {
        BOOL isVirtual = configurations[index][0];
        BOOL hidden = configurations[index][1];
        BOOL enabled = configurations[index][2];
        NSUserDefaults *defaults = APBIsolatedDefaults();
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        store.isManualMode = YES;
        store.selectsPairedDevice = enabled;
        APBDualRole *paired = DualRoleWith(isVirtual, @"serial", 1, 101);
        APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
        if (hidden) [store hide:paired.input];
        APBFakeAudio *audio = [[APBFakeAudio alloc] init];
        audio.catalog = @[paired.output, paired.input, macMic];
        audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
        APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
        [model start];

        [model selectManually:paired.output];

        XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID), @"configuration %d", index);
    }

    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *outputOnly = APBOutput(1, @"output-only", nil);
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[outputOnly, macMic];
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model selectManually:outputOnly];

    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
}

- (void)testAutomaticPairingRespectsMicrophoneNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:paired.input value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    XCTAssertEqualObjects(model.currentOutputID, @(paired.output.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
}

- (void)testAutomaticOutputEchoRespectsMicrophoneNeverAutoSelect {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store setNeverUse:paired.input value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testDisablingPairingReappliesAutomaticMicrophonePriority {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *macMic = APBInput(2, @"mac-mic", nil);
    [store savePriorities:@[macMic, paired.input] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, macMic];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));

    [model setSelectsPairedDeviceEnabled:NO];

    XCTAssertFalse(model.selectsPairedDevice);
    XCTAssertFalse(model.store.selectsPairedDevice);
    XCTAssertEqualObjects(model.currentInputID, @(macMic.platformID));
}

- (void)testExternalNeverAutoSelectOutputStillPairsItsMicrophone {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBDualRole *paired = DualRole();
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBAudioDevice *macMic = APBInput(3, @"mac-mic", nil);
    [store setNeverUse:paired.output value:YES];
    [store setNeverUse:speaker value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[paired.output, paired.input, speaker, macMic];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(macMic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.defaults[@(APBDeviceRoleOutput)] = @(paired.output.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertEqualObjects(model.currentInputID, @(paired.input.platformID));
}

- (void)testDeviceCallbackBeforeDefaultCallbackDoesNotEnableManual {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *newcomer = APBOutput(2, @"new", @"USB Headphones");
    [store setNeverUse:newcomer value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:newcomer];
    audio.defaults[@(APBDeviceRoleOutput)] = @(newcomer.platformID);
    [model handleDevicesChanged];
    audio.defaults[@(APBDeviceRoleOutput)] = @(newcomer.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

@end
