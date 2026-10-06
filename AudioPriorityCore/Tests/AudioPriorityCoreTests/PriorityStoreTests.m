#import <XCTest/XCTest.h>
#import "AudioPriorityCore.h"

static APBAudioDevice *Device(NSString *uid, APBDeviceRole role, BOOL connected, NSString *name, UInt32 platformID) {
    return [[APBAudioDevice alloc] initWithPlatformID:platformID
                                                  uid:uid
                                                 name:name ?: uid
                                                 role:role
                                          isConnected:connected
                                            isVirtual:NO
                                     declaredCategory:APBOutputCategoryNone
                                      isDisplayOutput:NO
                                        transportType:0];
}

static APBAudioDevice *Output(NSString *uid) {
    return Device(uid, APBDeviceRoleOutput, YES, nil, 1);
}

static APBAudioDevice *Input(NSString *uid) {
    return Device(uid, APBDeviceRoleInput, YES, nil, 1);
}

static APBAudioDevice *Named(NSString *uid, APBDeviceRole role, NSString *name) {
    return Device(uid, role, YES, name, 1);
}

static APBAudioDevice *Virtual(NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:1
                                                  uid:uid
                                                 name:name
                                                 role:APBDeviceRoleOutput
                                          isConnected:YES
                                            isVirtual:YES
                                     declaredCategory:APBOutputCategoryNone
                                      isDisplayOutput:NO
                                        transportType:0];
}

static APBAudioDevice *Monitor(NSString *uid, NSString *name) {
    return [[APBAudioDevice alloc] initWithPlatformID:1
                                                  uid:uid
                                                 name:name
                                                 role:APBDeviceRoleOutput
                                          isConnected:YES
                                            isVirtual:NO
                                     declaredCategory:APBOutputCategoryNone
                                      isDisplayOutput:YES
                                        transportType:0];
}

static APBAudioDevice *Declaring(NSString *uid, NSString *name, APBOutputCategory declared) {
    return [[APBAudioDevice alloc] initWithPlatformID:1
                                                  uid:uid
                                                 name:name
                                                 role:APBDeviceRoleOutput
                                          isConnected:YES
                                            isVirtual:NO
                                     declaredCategory:declared
                                      isDisplayOutput:NO
                                        transportType:0];
}

static APBStoredDevice *Stored(NSString *uid, NSString *name, BOOL isInput, NSTimeInterval lastSeen) {
    return [[APBStoredDevice alloc] initWithUID:uid
                                           name:name
                                        isInput:isInput
                                       lastSeen:[NSDate dateWithTimeIntervalSinceReferenceDate:lastSeen]
                               declaredCategory:APBOutputCategoryNone];
}

static APBPriorityStore *Store(NSUserDefaults *defaults, NSDictionary<NSString *, id> *legacyDomain) {
    return [[APBPriorityStore alloc] initWithDefaults:defaults now:nil legacyDomain:legacyDomain];
}

@interface PriorityStoreTests : XCTestCase
@end

@implementation PriorityStoreTests

- (NSDictionary<NSString *, id> *)fixtureValues:(NSString *)fixture {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:fixture
                                                        withExtension:@"plist"
                                                         subdirectory:@"Fixtures"];
    XCTAssertNotNil(url, @"missing fixture %@", fixture);
    if (!url) return @{};
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSError *error = nil;
    id values = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
    XCTAssertTrue([values isKindOfClass:NSDictionary.class], @"%@", error);
    return [values isKindOfClass:NSDictionary.class] ? values : @{};
}

- (void)withDefaultsFixture:(NSString *)fixture body:(void (^)(NSUserDefaults *defaults))body {
    NSString *suite = [@"AudioPriorityCoreTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    XCTAssertNotNil(defaults);
    if (!defaults) return;

    if (fixture) {
        [[self fixtureValues:fixture] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            [defaults setObject:value forKey:key];
        }];
    }
    body(defaults);
    [defaults removePersistentDomainForName:suite];
}

- (void)withDefaults:(void (^)(NSUserDefaults *defaults))body {
    [self withDefaultsFixture:nil body:body];
}

- (void)testV2FixtureLoadsWithoutChangingMeaning {
    [self withDefaultsFixture:@"v2.0.0-defaults" body:^(NSUserDefaults *defaults) {
        NSDictionary *before = defaults.dictionaryRepresentation;
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

        XCTAssertTrue(store.isManualMode);
        XCTAssertEqual(store.knownDevices.count, 3);
        XCTAssertEqualObjects(store.knownDevices.firstObject,
                              Stored(@"shared-device", @"Synthetic USB Headset", YES, 123456));
        XCTAssertEqual([store categoryForDevice:Named(@"shared-device", APBDeviceRoleOutput, @"Synthetic USB Headset")],
                       APBOutputCategoryHeadphone);
        XCTAssertTrue([store isHidden:Input(@"mic-hidden")]);
        XCTAssertTrue([store isHidden:Output(@"speaker-hidden") inCategory:APBOutputCategorySpeaker]);
        XCTAssertTrue([store isNeverUse:Input(@"mic-never")]);
        XCTAssertTrue([store isNeverUse:Output(@"speaker-never")]);

        NSData *originalData = [defaults dataForKey:@"knownDevices"];
        XCTAssertNotNil(originalData);
        if (!originalData) return;
        NSMutableArray *roundTrip = [NSMutableArray array];
        for (APBStoredDevice *stored in store.knownDevices) {
            [roundTrip addObject:stored.JSONObject];
        }
        NSError *error = nil;
        NSData *roundTripData = [NSJSONSerialization dataWithJSONObject:roundTrip options:0 error:&error];
        XCTAssertNotNil(roundTripData, @"%@", error);
        if (!roundTripData) return;
        id originalShape = [NSJSONSerialization JSONObjectWithData:originalData options:0 error:NULL];
        id roundTripShape = [NSJSONSerialization JSONObjectWithData:roundTripData options:0 error:NULL];
        XCTAssertNotNil(originalShape);
        XCTAssertNotNil(roundTripShape);
        XCTAssertEqualObjects((@{@"value": originalShape ?: NSNull.null}),
                              (@{@"value": roundTripShape ?: NSNull.null}));

        NSDictionary *after = defaults.dictionaryRepresentation;
        XCTAssertEqualObjects(before, after);
    }];
}

- (void)testPublicV1SettingsMigrateOnceWithoutOverwritingV2Values {
    [self withDefaults:^(NSUserDefaults *defaults) {
        [defaults setObject:@[@"current-speaker"] forKey:@"speakerPriorities"];
        NSDictionary *legacy = [self fixtureValues:@"v1.2.1-defaults"];
        APBPriorityStore *store = Store(defaults, legacy);

        XCTAssertTrue(store.isManualMode);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"inputPriorities"], @[@"v1-mic"]);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"speakerPriorities"], @[@"current-speaker"]);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"headphonePriorities"], @[@"v1-headset"]);
        XCTAssertEqual([store categoryForDevice:Named(@"v1-headset", APBDeviceRoleOutput, @"Synthetic V1 Headset")],
                       APBOutputCategoryHeadphone);
        XCTAssertTrue([store isHidden:Input(@"v1-mic-hidden")]);
        XCTAssertTrue([store isHidden:Output(@"v1-speaker-hidden") inCategory:APBOutputCategorySpeaker]);
        XCTAssertTrue([store isHidden:Output(@"v1-hidden") inCategory:APBOutputCategoryHeadphone]);
        XCTAssertEqualObjects(store.knownDevices,
                              @[Stored(@"v1-headset", @"Synthetic V1 Headset", NO, 123456)]);
        XCTAssertTrue([store isNeverUse:Input(@"v1-never")]);
        XCTAssertTrue([store isNeverUse:Output(@"v1-never")]);
        XCTAssertTrue([defaults boolForKey:@"legacyBundleMigration_v1"]);

        NSDictionary *once = defaults.dictionaryRepresentation;
        (void)Store(defaults, @{@"inputPriorities": @[@"replacement"]});
        XCTAssertEqualObjects(once, defaults.dictionaryRepresentation);
    }];
}

- (void)testV1NeverUseImportsAfterV2RoleMigrationAlreadyRan {
    [self withDefaultsFixture:@"v2.0.0-defaults" body:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = Store(defaults, @{@"neverUseDevices": @[@"v1-never"]});

        XCTAssertTrue([store isNeverUse:Input(@"mic-never")]);
        XCTAssertTrue([store isNeverUse:Output(@"speaker-never")]);
        XCTAssertTrue([store isNeverUse:Input(@"v1-never")]);
        XCTAssertTrue([store isNeverUse:Output(@"v1-never")]);
        XCTAssertNil([defaults objectForKey:@"neverUseDevices"]);
    }];
}

- (void)testLegacyNeverUseMigratesOnceAndPreservesRoleEntries {
    [self withDefaultsFixture:@"legacy-defaults" body:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        XCTAssertTrue([store isNeverUse:Input(@"shared-device")]);
        XCTAssertTrue([store isNeverUse:Output(@"shared-device")]);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"neverUseInputs"],
                              (@[@"input-existing", @"shared-device", @"legacy-only"]));
        XCTAssertEqualObjects([defaults stringArrayForKey:@"neverUseOutputs"],
                              (@[@"output-existing", @"shared-device", @"legacy-only"]));
        XCTAssertNil([defaults objectForKey:@"neverUseDevices"]);
        XCTAssertTrue([defaults boolForKey:@"roleSpecificNeverUseMigration_v1"]);

        NSDictionary *once = defaults.dictionaryRepresentation;
        (void)[store isNeverUse:Output(@"shared-device")];
        NSDictionary *twice = defaults.dictionaryRepresentation;
        XCTAssertEqualObjects(once, twice);
    }];
}

- (void)testVisibleOrderMergesWithoutDroppingStoredDevices {
    NSArray<NSArray<NSArray<NSString *> *> *> *cases = @[
        @[
            @[@"C", @"B", @"A"],
            @[@"A", @"hidden-1", @"B", @"hidden-2", @"C"],
            @[@"C", @"hidden-1", @"B", @"hidden-2", @"A"],
        ],
        @[
            @[@"B", @"A", @"new"],
            @[@"A", @"disconnected", @"B"],
            @[@"B", @"disconnected", @"A", @"new"],
        ],
        @[
            @[@"B", @"B", @"A"],
            @[@"A", @"missing", @"A", @"B"],
            @[@"B", @"missing", @"A"],
        ],
    ];
    for (NSArray<NSArray<NSString *> *> *testCase in cases) {
        NSArray<NSString *> *visible = testCase[0];
        NSArray<NSString *> *stored = testCase[1];
        XCTAssertEqualObjects([APBPriorityStore mergeVisibleOrder:visible into:stored], testCase[2],
                              @"visible %@ into stored %@", visible, stored);
    }
}

- (void)testUnrankedDevicesKeepDiscoveryOrder {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        NSArray *devices = @[
            Device(@"C", APBDeviceRoleOutput, YES, nil, 3),
            Device(@"A", APBDeviceRoleOutput, YES, nil, 1),
            Device(@"B", APBDeviceRoleOutput, YES, nil, 2),
        ];
        XCTAssertEqualObjects([[store sorted:devices category:APBOutputCategorySpeaker] valueForKey:@"uid"],
                              (@[@"C", @"A", @"B"]));
    }];
}

- (void)testFullDuplexDeviceKeepsBothRoles {
    [self withDefaults:^(NSUserDefaults *defaults) {
        NSDate *fixedNow = [NSDate dateWithTimeIntervalSinceReferenceDate:999];
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults
                                                                         now:^NSDate * { return fixedNow; }
                                                                legacyDomain:nil];
        [store remember:@[
            Named(@"shared", APBDeviceRoleInput, @"USB Headset"),
            Named(@"shared", APBDeviceRoleOutput, @"USB Headset"),
        ]];

        XCTAssertEqual(store.knownDevices.count, 2);
        APBStoredDevice *input = [store storedDeviceWithUID:@"shared" role:@(APBDeviceRoleInput)];
        APBStoredDevice *output = [store storedDeviceWithUID:@"shared" role:@(APBDeviceRoleOutput)];
        XCTAssertNotNil(input);
        XCTAssertTrue(input.isInput);
        XCTAssertNotNil(output);
        XCTAssertFalse(output.isInput);
    }];
}

- (void)testUsbAudioEngineRolesShareAPairingKey {
    NSString *base = @"AppleUSBAudioEngine:Unknown Manufacturer:Jabra Link 380:50C275445423";
    XCTAssertEqualObjects(Output([base stringByAppendingString:@":1"]).pairingKey, base);
    XCTAssertEqualObjects(Input([base stringByAppendingString:@":2"]).pairingKey, base);
    NSString *numericSerial = @"AppleUSBAudioEngine:Manufacturer:Device:2110000";
    XCTAssertEqualObjects(Output(numericSerial).pairingKey, numericSerial);
    XCTAssertEqualObjects(Output([base stringByAppendingString:@":1,2"]).pairingKey,
                          [base stringByAppendingString:@":1,2"]);
    XCTAssertEqualObjects(Output(@"other-device:1").pairingKey, @"other-device:1");
}

- (void)testVirtualDevicesDefaultOutOfAutomaticSelection {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *krisp = Virtual(@"krisp", @"krisp speaker");
        APBAudioDevice *speakers = Named(@"builtin", APBDeviceRoleOutput, @"MacBook Pro Speakers");

        [store remember:@[krisp, speakers]];

        XCTAssertTrue([store isNeverUse:krisp]);
        XCTAssertFalse([store isNeverUse:speakers]);
    }];
}

- (void)testOptingAVirtualDeviceBackInSurvivesLaterRefreshes {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *krisp = Virtual(@"krisp", @"krisp speaker");
        [store remember:@[krisp]];
        [store setNeverUse:krisp value:NO];

        [store remember:@[krisp]];

        XCTAssertFalse([store isNeverUse:krisp]);
    }];
}

- (void)testVirtualDefaultsAlsoSeedDevicesKnownBeforeTheFeature {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBAudioDevice *krisp = Virtual(@"krisp", @"krisp speaker");
        APBPriorityStore *older = [[APBPriorityStore alloc] initWithDefaults:defaults];
        [defaults removeObjectForKey:@"virtualNeverUseDefaults_v1"];
        [older remember:@[krisp]];
        [older setNeverUse:krisp value:NO];
        [defaults removeObjectForKey:@"virtualNeverUseDefaults_v1"];

        APBPriorityStore *upgraded = [[APBPriorityStore alloc] initWithDefaults:defaults];
        [upgraded remember:@[krisp]];

        XCTAssertTrue([upgraded isNeverUse:krisp]);
    }];
}

- (void)testEmptyRefreshDoesNotConsumeVirtualDeviceMigration {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        [store remember:@[]];
        XCTAssertFalse([defaults boolForKey:@"virtualNeverUseDefaults_v1"]);

        APBAudioDevice *krisp = Virtual(@"krisp", @"krisp speaker");
        [store remember:@[krisp]];

        XCTAssertTrue([store isNeverUse:krisp]);
    }];
}

- (void)testNeverUseIsScopedByRole {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *input = Input(@"shared");
        APBAudioDevice *output = Output(@"shared");
        [store setNeverUse:input value:YES];
        XCTAssertTrue([store isNeverUse:input]);
        XCTAssertFalse([store isNeverUse:output]);
    }];
}

- (void)testSelectsPairedDeviceDefaultsOnAndPersistsOff {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        XCTAssertTrue(store.selectsPairedDevice);

        store.selectsPairedDevice = NO;

        XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].selectsPairedDevice);
    }];
}

- (void)testSelectsPairedDeviceMigratesFromThePreRenameKeyOnce {
    [self withDefaults:^(NSUserDefaults *defaults) {
        [defaults setBool:NO forKey:@"linksMicrophone"];

        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

        XCTAssertFalse(store.selectsPairedDevice);

        // Migrating once means a later legacy write must not override the
        // now-authoritative value.
        [defaults setBool:YES forKey:@"linksMicrophone"];
        XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].selectsPairedDevice);
    }];
}

- (void)testAppliedMicrophoneMutesAndNoticePreferencesPersist {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        XCTAssertEqual(store.appliedMicrophoneMutes.count, 0);
        XCTAssertTrue(store.showsSwitchNotice);
        XCTAssertTrue(store.remindsWhenMuted);

        // 0.627 is the MacBook Pro microphone level read on macOS 26.
        store.appliedMicrophoneMutes = @{
            @"mic": @0.627,
            @"jabra": @(APBPriorityStore.mutedByProperty),
        };
        store.showsSwitchNotice = NO;
        store.remindsWhenMuted = NO;

        APBPriorityStore *reloaded = [[APBPriorityStore alloc] initWithDefaults:defaults];
        XCTAssertEqualObjects(reloaded.appliedMicrophoneMutes, (@{
            @"mic": @0.627,
            @"jabra": @(APBPriorityStore.mutedByProperty),
        }));
        XCTAssertFalse(reloaded.showsSwitchNotice);
        XCTAssertFalse(reloaded.remindsWhenMuted);
    }];
}

- (void)testMenuBarOutlineIsOffUntilTurnedOn {
    [self withDefaults:^(NSUserDefaults *defaults) {
        XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].outlinesMenuBarIcon);
        [[APBPriorityStore alloc] initWithDefaults:defaults].outlinesMenuBarIcon = YES;
        XCTAssertTrue([[APBPriorityStore alloc] initWithDefaults:defaults].outlinesMenuBarIcon);
    }];
}

- (void)testMenuBarVolumeIsOffUntilTurnedOn {
    [self withDefaults:^(NSUserDefaults *defaults) {
        XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].showsMenuBarVolume);
        [[APBPriorityStore alloc] initWithDefaults:defaults].showsMenuBarVolume = YES;
        XCTAssertTrue([[APBPriorityStore alloc] initWithDefaults:defaults].showsMenuBarVolume);
    }];
}

- (void)testMenuBarShowsOnlyTheOutputUntilChanged {
    [self withDefaults:^(NSUserDefaults *defaults) {
        XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
                       APBMenuBarDevicesOutputOnly);
        [[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices = APBMenuBarDevicesBothLabeled;
        XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
                       APBMenuBarDevicesBothLabeled);
        [defaults setObject:@"unknown" forKey:@"menuBarDevices"];
        XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
                       APBMenuBarDevicesOutputOnly);
    }];
}

- (void)testDisplayOutputsAreHiddenOnceAndShowingOneSticks {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *dell = Monitor(@"dell", @"DELL U2518D");
        [store remember:@[dell]];
        // Hidden in both categories, so a later move between Speakers and
        // Headphones cannot surface a display the user never asked to see.
        XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
        XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);

        [store unhide:dell fromCategory:APBOutputCategorySpeaker];
        [store unhide:dell fromCategory:APBOutputCategoryHeadphone];
        [store remember:@[dell]];

        // Deciding once is the whole point: a later sighting must not undo
        // the user showing it by hand.
        XCTAssertFalse([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
        XCTAssertFalse([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);
    }];
}

- (void)testDisplayDefaultAppliesToNewDevicesRatherThanRetroactively {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        store.hideNewDisplayOutputs = NO;
        APBAudioDevice *seen = Monitor(@"dell", @"DELL U2518D");
        [store remember:@[seen]];
        XCTAssertFalse([store isHidden:seen inCategory:APBOutputCategorySpeaker]);

        store.hideNewDisplayOutputs = YES;
        [store remember:@[seen]];
        // Already dealt with, so enabling the preference leaves it alone.
        XCTAssertFalse([store isHidden:seen inCategory:APBOutputCategorySpeaker]);

        APBAudioDevice *arrived = Monitor(@"dell2", @"DELL U2720Q");
        [store remember:@[arrived]];
        XCTAssertTrue([store isHidden:arrived inCategory:APBOutputCategorySpeaker]);
        XCTAssertTrue([store isHidden:arrived inCategory:APBOutputCategoryHeadphone]);
    }];
}

- (void)testDisplayDefaultLeavesOtherOutputsAndMicrophonesAlone {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *speaker = Named(@"speakers", APBDeviceRoleOutput, @"Haut-parleurs MacBook Pro");
        APBAudioDevice *mic = Input(@"mic");
        [store remember:@[speaker, mic]];

        XCTAssertFalse([store isHidden:speaker inCategory:APBOutputCategorySpeaker]);
        XCTAssertFalse([store isHidden:mic]);
    }];
}

- (void)testDisplayPreferenceDefaultsOnAndPersistsOff {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        XCTAssertTrue(store.hideNewDisplayOutputs);

        store.hideNewDisplayOutputs = NO;

        XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].hideNewDisplayOutputs);
    }];
}

- (void)testForgettingADisplayLetsItBeTreatedAsNewAgain {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *dell = Monitor(@"dell", @"DELL U2518D");
        [store remember:@[dell]];
        [store unhide:dell fromCategory:APBOutputCategorySpeaker];
        [store unhide:dell fromCategory:APBOutputCategoryHeadphone];

        [store forgetUID:dell.uid role:APBDeviceRoleOutput];
        [store remember:@[dell]];

        XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
        XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);
    }];
}

- (void)testForgettingOneRolePreservesTheOther {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *input = Input(@"shared");
        APBAudioDevice *output = Output(@"shared");
        [store remember:@[input, output]];
        [store savePriorities:@[input] role:APBDeviceRoleInput];
        [store savePriorities:@[output] category:APBOutputCategorySpeaker];
        [store setNeverUse:input value:YES];
        [store setNeverUse:output value:YES];
        [store hide:input];
        [store hide:output inCategory:APBOutputCategorySpeaker];

        [store forgetUID:@"shared" role:APBDeviceRoleInput];

        XCTAssertNil([store storedDeviceWithUID:@"shared" role:@(APBDeviceRoleInput)]);
        XCTAssertNotNil([store storedDeviceWithUID:@"shared" role:@(APBDeviceRoleOutput)]);
        XCTAssertFalse([store isNeverUse:input]);
        XCTAssertTrue([store isNeverUse:output]);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"inputPriorities"], @[]);
        XCTAssertEqualObjects([defaults stringArrayForKey:@"speakerPriorities"], @[@"shared"]);
    }];
}

- (void)testSelectionSkipsUnavailableDevices {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        APBAudioDevice *disconnected = Device(@"disconnected", APBDeviceRoleOutput, NO, nil, 1);
        APBAudioDevice *hidden = Output(@"hidden");
        APBAudioDevice *never = Output(@"never");
        APBAudioDevice *unlinked = Output(@"unlinked");
        APBAudioDevice *selected = Output(@"selected");
        [store hide:hidden];
        [store setNeverUse:never value:YES];

        APBAudioDevice *result = [store firstSelectableIn:@[disconnected, hidden, never, unlinked, selected]
                                                 isUsable:^BOOL(APBAudioDevice *device) {
            return ![device.uid isEqualToString:@"unlinked"];
        }];
        XCTAssertEqualObjects(result, selected);
    }];
}

- (void)testHeadphoneDetectionIsCaseInsensitive {
    XCTAssertTrue([APBHeadphoneDetection isHeadphone:@"JABRA LINK 390"]);
    XCTAssertTrue([APBHeadphoneDetection isHeadphone:@"AirPods Pro"]);
    XCTAssertFalse([APBHeadphoneDetection isHeadphone:@"Studio Display Speakers"]);
}

- (void)testKnownSpeakerProductsOutrankTheirBrandKeyword {
    // The bare "jabra" keyword would otherwise claim these.
    XCTAssertTrue([APBHeadphoneDetection isKnownSpeaker:@"Jabra Speak2 75"]);
    XCTAssertTrue([APBHeadphoneDetection isKnownSpeaker:@"JABRA SPEAK 750"]);
    XCTAssertFalse([APBHeadphoneDetection isKnownSpeaker:@"Jabra Evolve2 85"]);
    XCTAssertFalse([APBHeadphoneDetection isKnownSpeaker:@"Jabra Elite 8 Active"]);
    XCTAssertFalse([APBHeadphoneDetection isKnownSpeaker:@"Jabra Link 380"]);
    // Brands stay out of the list, so their headphones are unaffected.
    XCTAssertFalse([APBHeadphoneDetection isKnownSpeaker:@"Marshall Major IV"]);
}

- (void)testCategoryPrefersTheDeviceClaimOverNameKeywords {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

        // A speaker that a brand keyword would misfile as headphones.
        XCTAssertEqual([store categoryForDevice:Declaring(@"anker", @"Anker PowerConf S3", APBOutputCategorySpeaker)],
                       APBOutputCategorySpeaker);
        // A localized name no English keyword matches, the headphone jack.
        XCTAssertEqual([store categoryForDevice:Declaring(@"jack", @"Écouteurs externes", APBOutputCategoryHeadphone)],
                       APBOutputCategoryHeadphone);
        // Without a claim the keyword list still decides, both ways.
        XCTAssertEqual([store categoryForDevice:Declaring(@"jack", @"Écouteurs externes", APBOutputCategoryNone)],
                       APBOutputCategorySpeaker);
        XCTAssertEqual([store categoryForDevice:Declaring(@"pods", @"AirPods Pro", APBOutputCategoryNone)],
                       APBOutputCategoryHeadphone);
    }];
}

- (void)testKnownSpeakerWinsEvenWhenTheDeviceClaimsHeadphones {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        // CoreAudio has no speakerphone terminal type, so a Speak may report
        // headphones. The product rule has to sit ahead of the claim to cover
        // tobi/AudioPriorityBar#39.
        APBAudioDevice *speak = Declaring(@"speak", @"Jabra Speak2 75", APBOutputCategoryHeadphone);
        XCTAssertEqual([store categoryForDevice:speak], APBOutputCategorySpeaker);

        // The user still overrides everything, including that rule.
        [store setCategory:APBOutputCategoryHeadphone forDevice:speak];
        XCTAssertEqual([store categoryForDevice:speak], APBOutputCategoryHeadphone);
    }];
}

- (void)testRememberedDeviceKeepsWhatTheHardwareDeclared {
    [self withDefaults:^(NSUserDefaults *defaults) {
        APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
        [store remember:@[Declaring(@"jack", @"Écouteurs externes", APBOutputCategoryHeadphone)]];

        // Reconstructed while disconnected it must not fall back to the
        // keyword result, or it would change list the moment it is unplugged.
        APBStoredDevice *remembered = [store storedDeviceWithUID:@"jack" role:@(APBDeviceRoleOutput)];
        XCTAssertNotNil(remembered);
        if (!remembered) return;
        XCTAssertEqual(remembered.declaredCategory, APBOutputCategoryHeadphone);
        XCTAssertEqual([store categoryForDevice:[remembered disconnectedDevice]], APBOutputCategoryHeadphone);
    }];
}

- (void)testStoredDevicesWrittenBeforeDeclarationsStillDecode {
    NSData *json = [@"[{\"uid\":\"old\",\"name\":\"Old Speaker\",\"isInput\":false,\"lastSeen\":0}]"
                    dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *objects = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    NSMutableArray<APBStoredDevice *> *decoded = [NSMutableArray array];
    for (id object in objects) {
        APBStoredDevice *device = [APBStoredDevice deviceWithJSONObject:object];
        XCTAssertNotNil(device, @"%@", object);
        if (device) [decoded addObject:device];
    }
    XCTAssertEqual(decoded.count, 1);
    // Swift's nil category maps to APBOutputCategoryNone.
    XCTAssertEqual(decoded.firstObject.declaredCategory, APBOutputCategoryNone);
}

@end
