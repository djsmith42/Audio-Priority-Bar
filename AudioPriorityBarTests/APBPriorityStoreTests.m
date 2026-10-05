#import <XCTest/XCTest.h>
#import "APBModels.h"
#import "APBPriorityStore.h"
#import "APBTestSupport.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBPriorityStoreTests : XCTestCase
@end

@implementation APBPriorityStoreTests

#pragma mark - Helpers

/// The values of a fixture plist copied flat into the test bundle's Resources.
static NSDictionary<NSString *, id> *fixtureValues(NSString *fixture) {
    NSURL *url = [[NSBundle bundleForClass:APBPriorityStoreTests.class]
        URLForResource:fixture withExtension:@"plist"];
    XCTAssertNotNil(url);
    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    NSDictionary *values = [NSPropertyListSerialization
        propertyListWithData:data
                      options:0
                       format:nil
                        error:nil];
    XCTAssertNotNil(values);
    return values;
}

/// A fresh defaults suite, optionally seeded from a fixture plist.
static NSUserDefaults *defaultsFromFixture(NSString *_Nullable fixture) {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    if (fixture != nil) {
        NSDictionary *values = fixtureValues(fixture);
        for (NSString *key in values) {
            [defaults setObject:values[key] forKey:key];
        }
    }
    return defaults;
}

/// A connected physical device that declares nothing.
static APBAudioDevice *device(NSString *uid, APBDeviceRole role, NSString *_Nullable name, UInt32 platformID) {
    return [[APBAudioDevice alloc] initWithPlatformID:platformID
                                                  uid:uid
                                                 name:name ?: uid
                                                 role:role
                                          isConnected:YES
                                            isVirtual:NO
                                     declaredCategory:APBOutputCategoryNone
                                      isDisplayOutput:NO
                                        transportType:0];
}

static APBAudioDevice *outputDevice(NSString *uid) {
    return device(uid, APBDeviceRoleOutput, nil, 1);
}

static APBAudioDevice *outputDeviceNamed(NSString *uid, NSString *name) {
    return device(uid, APBDeviceRoleOutput, name, 1);
}

static APBAudioDevice *inputDevice(NSString *uid) {
    return device(uid, APBDeviceRoleInput, nil, 1);
}

/// A monitor reached over a video cable.
static APBAudioDevice *monitor(NSString *uid, NSString *name) {
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

/// An output that says what it is through its terminal type.
static APBAudioDevice *declaring(NSString *uid, NSString *name, APBOutputCategory declared) {
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

/// A software routing device.
static APBAudioDevice *virtualDevice(NSString *uid, NSString *name) {
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

static NSArray<NSString *> *uids(NSArray<APBAudioDevice *> *devices) {
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    for (APBAudioDevice *device in devices) [list addObject:device.uid];
    return list;
}

static APBStoredDevice *stored(NSString *uid, NSString *name, BOOL isInput, NSTimeInterval lastSeen) {
    return [[APBStoredDevice alloc] initWithUID:uid
                                           name:name
                                        isInput:isInput
                                       lastSeen:[NSDate dateWithTimeIntervalSinceReferenceDate:lastSeen]
                               declaredCategory:APBOutputCategoryNone];
}

#pragma mark - Fixtures and migrations

- (void)testV2FixtureLoadsWithoutChangingMeaning {
    NSUserDefaults *defaults = defaultsFromFixture(@"v2.0.0-defaults");
    NSDictionary *before = defaults.dictionaryRepresentation;
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

    XCTAssertTrue(store.isManualMode);
    XCTAssertEqual(store.knownDevices.count, 3u);
    XCTAssertEqualObjects(store.knownDevices[0],
        stored(@"shared-device", @"Synthetic USB Headset", YES, 123456));
    XCTAssertEqual([store categoryForDevice:outputDeviceNamed(@"shared-device", @"Synthetic USB Headset")],
    APBOutputCategoryHeadphone);
    XCTAssertTrue([store isHidden:inputDevice(@"mic-hidden")]);
    XCTAssertTrue([store isHidden:outputDevice(@"speaker-hidden") inCategory:APBOutputCategorySpeaker]);
    XCTAssertTrue([store isNeverUse:inputDevice(@"mic-never")]);
    XCTAssertTrue([store isNeverUse:outputDevice(@"speaker-never")]);

    NSData *originalData = [defaults dataForKey:@"knownDevices"];
    XCTAssertNotNil(originalData);
    NSMutableArray *roundTripObjects = [NSMutableArray array];
    for (APBStoredDevice *known in store.knownDevices) [roundTripObjects addObject:known.JSONObject];
    NSData *roundTripData = [NSJSONSerialization dataWithJSONObject:roundTripObjects options:0 error:nil];
    id originalShape = [NSJSONSerialization JSONObjectWithData:originalData options:0 error:nil];
    id roundTripShape = [NSJSONSerialization JSONObjectWithData:roundTripData options:0 error:nil];
    XCTAssertEqualObjects((@{ @"value": originalShape }), (@{ @"value": roundTripShape }));

    NSDictionary *after = defaults.dictionaryRepresentation;
    XCTAssertEqualObjects(before, after);
}

- (void)testPublicV1SettingsMigrateOnceWithoutOverwritingV2Values {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    [defaults setObject:@[ @"current-speaker" ] forKey:@"speakerPriorities"];
    NSDictionary *legacy = fixtureValues(@"v1.2.1-defaults");
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults now:nil legacyDomain:legacy];

    XCTAssertTrue(store.isManualMode);
    XCTAssertEqualObjects([defaults stringArrayForKey:@"inputPriorities"], (@[ @"v1-mic" ]));
    XCTAssertEqualObjects([defaults stringArrayForKey:@"speakerPriorities"], (@[ @"current-speaker" ]));
    XCTAssertEqualObjects([defaults stringArrayForKey:@"headphonePriorities"], (@[ @"v1-headset" ]));
    XCTAssertEqual([store categoryForDevice:outputDeviceNamed(@"v1-headset", @"Synthetic V1 Headset")],
    APBOutputCategoryHeadphone);
    XCTAssertTrue([store isHidden:inputDevice(@"v1-mic-hidden")]);
    XCTAssertTrue([store isHidden:outputDevice(@"v1-speaker-hidden") inCategory:APBOutputCategorySpeaker]);
    XCTAssertTrue([store isHidden:outputDevice(@"v1-hidden") inCategory:APBOutputCategoryHeadphone]);
    XCTAssertEqual(store.knownDevices.count, 1u);
    XCTAssertEqualObjects(store.knownDevices.firstObject,
        stored(@"v1-headset", @"Synthetic V1 Headset", NO, 123456));
    XCTAssertTrue([store isNeverUse:inputDevice(@"v1-never")]);
    XCTAssertTrue([store isNeverUse:outputDevice(@"v1-never")]);
    XCTAssertTrue([defaults boolForKey:@"legacyBundleMigration_v1"]);

    NSDictionary *once = defaults.dictionaryRepresentation;
    [[APBPriorityStore alloc] initWithDefaults:defaults now:nil
        legacyDomain:@{ @"inputPriorities": @[ @"replacement" ] }];
    XCTAssertEqualObjects(once, defaults.dictionaryRepresentation);
}

- (void)testV1NeverUseImportsAfterV2RoleMigrationAlreadyRan {
    NSUserDefaults *defaults = defaultsFromFixture(@"v2.0.0-defaults");
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults now:nil
        legacyDomain:@{ @"neverUseDevices": @[ @"v1-never" ] }];

    XCTAssertTrue([store isNeverUse:inputDevice(@"mic-never")]);
    XCTAssertTrue([store isNeverUse:outputDevice(@"speaker-never")]);
    XCTAssertTrue([store isNeverUse:inputDevice(@"v1-never")]);
    XCTAssertTrue([store isNeverUse:outputDevice(@"v1-never")]);
    XCTAssertNil([defaults objectForKey:@"neverUseDevices"]);
}

- (void)testLegacyNeverUseMigratesOnceAndPreservesRoleEntries {
    NSUserDefaults *defaults = defaultsFromFixture(@"legacy-defaults");
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    XCTAssertTrue([store isNeverUse:inputDevice(@"shared-device")]);
    XCTAssertTrue([store isNeverUse:outputDevice(@"shared-device")]);
    XCTAssertEqualObjects([defaults stringArrayForKey:@"neverUseInputs"],
        (@[ @"input-existing", @"shared-device", @"legacy-only" ]));
    XCTAssertEqualObjects([defaults stringArrayForKey:@"neverUseOutputs"],
        (@[ @"output-existing", @"shared-device", @"legacy-only" ]));
    XCTAssertNil([defaults objectForKey:@"neverUseDevices"]);
    XCTAssertTrue([defaults boolForKey:@"roleSpecificNeverUseMigration_v1"]);

    NSDictionary *once = defaults.dictionaryRepresentation;
    [store isNeverUse:outputDevice(@"shared-device")];
    XCTAssertEqualObjects(once, defaults.dictionaryRepresentation);
}

#pragma mark - Ordering

- (void)testVisibleOrderMergesWithoutDroppingStoredDevices {
    struct { NSArray *visible; NSArray *stored; NSArray *expected; } cases[] = {
        { @[ @"C", @"B", @"A" ], @[ @"A", @"hidden-1", @"B", @"hidden-2", @"C" ],
          @[ @"C", @"hidden-1", @"B", @"hidden-2", @"A" ] },
        { @[ @"B", @"A", @"new" ], @[ @"A", @"disconnected", @"B" ],
          @[ @"B", @"disconnected", @"A", @"new" ] },
        { @[ @"B", @"B", @"A" ], @[ @"A", @"missing", @"A", @"B" ],
          @[ @"B", @"missing", @"A" ] },
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        XCTAssertEqualObjects(
            [APBPriorityStore mergeVisibleOrder:cases[i].visible into:cases[i].stored],
            cases[i].expected);
    }
}

- (void)testUnrankedDevicesKeepDiscoveryOrder {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    NSArray *devices = @[
        device(@"C", APBDeviceRoleOutput, nil, 3),
        device(@"A", APBDeviceRoleOutput, nil, 1),
        device(@"B", APBDeviceRoleOutput, nil, 2),
    ];
    XCTAssertEqualObjects(uids([store sorted:devices category:APBOutputCategorySpeaker]),
        (@[ @"C", @"A", @"B" ]));
}

- (void)testFullDuplexDeviceKeepsBothRoles {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    NSDate *fixedNow = [NSDate dateWithTimeIntervalSinceReferenceDate:999];
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults
        now:^NSDate * { return fixedNow; }
        legacyDomain:nil];
    [store rememberDevices:@[
        device(@"shared", APBDeviceRoleInput, @"USB Headset", 1),
        device(@"shared", APBDeviceRoleOutput, @"USB Headset", 1),
    ]];

    XCTAssertEqual(store.knownDevices.count, 2u);
    XCTAssertTrue([store storedDeviceWithUID:@"shared" role:APBDeviceRoleInput].isInput);
    XCTAssertFalse([store storedDeviceWithUID:@"shared" role:APBDeviceRoleOutput].isInput);
}

- (void)testUSBAudioEngineRolesShareAPairingKey {
    NSString *base = @"AppleUSBAudioEngine:Unknown Manufacturer:Jabra Link 380:50C275445423";
    XCTAssertEqualObjects([device([base stringByAppendingString:@":1"], APBDeviceRoleOutput, nil, 1) pairingKey], base);
    XCTAssertEqualObjects([device([base stringByAppendingString:@":2"], APBDeviceRoleInput, nil, 1) pairingKey], base);
    NSString *numericSerial = @"AppleUSBAudioEngine:Manufacturer:Device:2110000";
    XCTAssertEqualObjects([device(numericSerial, APBDeviceRoleOutput, nil, 1) pairingKey], numericSerial);
    XCTAssertEqualObjects([device([base stringByAppendingString:@":1,2"], APBDeviceRoleOutput, nil, 1) pairingKey],
        [base stringByAppendingString:@":1,2"]);
    XCTAssertEqualObjects([device(@"other-device:1", APBDeviceRoleOutput, nil, 1) pairingKey], @"other-device:1");
}

#pragma mark - Virtual devices

- (void)testVirtualDevicesDefaultOutOfAutomaticSelection {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *krisp = virtualDevice(@"krisp", @"krisp speaker");
    APBAudioDevice *speakers = outputDeviceNamed(@"builtin", @"MacBook Pro Speakers");

    [store rememberDevices:@[ krisp, speakers ]];

    XCTAssertTrue([store isNeverUse:krisp]);
    XCTAssertFalse([store isNeverUse:speakers]);
}

- (void)testOptingAVirtualDeviceBackInSurvivesLaterRefreshes {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *krisp = virtualDevice(@"krisp", @"krisp speaker");
    [store rememberDevices:@[ krisp ]];
    [store setNeverUse:krisp value:NO];

    [store rememberDevices:@[ krisp ]];

    XCTAssertFalse([store isNeverUse:krisp]);
}

- (void)testVirtualDefaultsAlsoSeedDevicesKnownBeforeTheFeature {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBAudioDevice *krisp = virtualDevice(@"krisp", @"krisp speaker");
    APBPriorityStore *older = [[APBPriorityStore alloc] initWithDefaults:defaults];
    [defaults removeObjectForKey:@"virtualNeverUseDefaults_v1"];
    [older rememberDevices:@[ krisp ]];
    [older setNeverUse:krisp value:NO];
    [defaults removeObjectForKey:@"virtualNeverUseDefaults_v1"];

    APBPriorityStore *upgraded = [[APBPriorityStore alloc] initWithDefaults:defaults];
    [upgraded rememberDevices:@[ krisp ]];

    XCTAssertTrue([upgraded isNeverUse:krisp]);
}

- (void)testEmptyRefreshDoesNotConsumeVirtualDeviceMigration {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    [store rememberDevices:@[]];
    XCTAssertFalse([defaults boolForKey:@"virtualNeverUseDefaults_v1"]);

    APBAudioDevice *krisp = virtualDevice(@"krisp", @"krisp speaker");
    [store rememberDevices:@[ krisp ]];

    XCTAssertTrue([store isNeverUse:krisp]);
}

#pragma mark - Never use

- (void)testNeverUseIsScopedByRole {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *input = inputDevice(@"shared");
    APBAudioDevice *output = outputDevice(@"shared");
    [store setNeverUse:input value:YES];
    XCTAssertTrue([store isNeverUse:input]);
    XCTAssertFalse([store isNeverUse:output]);
}

#pragma mark - Paired selection

- (void)testSelectsPairedDeviceDefaultsOnAndPersistsOff {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    XCTAssertTrue(store.selectsPairedDevice);

    store.selectsPairedDevice = NO;

    XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].selectsPairedDevice);
}

- (void)testSelectsPairedDeviceMigratesFromThePreRenameKeyOnce {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    [defaults setBool:NO forKey:@"linksMicrophone"];

    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

    XCTAssertFalse(store.selectsPairedDevice);

    // Migrating once means a later legacy write must not override the
    // now-authoritative value.
    [defaults setBool:YES forKey:@"linksMicrophone"];
    XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].selectsPairedDevice);
}

#pragma mark - Mute and notice preferences

- (void)testAppliedMicrophoneMutesAndNoticePreferencesPersist {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    XCTAssertEqual(store.appliedMicrophoneMutes.count, 0u);
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
}

#pragma mark - Menu bar

- (void)testMenuBarOutlineIsOffUntilTurnedOn {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].outlinesMenuBarIcon);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.outlinesMenuBarIcon = YES;
    XCTAssertTrue([[APBPriorityStore alloc] initWithDefaults:defaults].outlinesMenuBarIcon);
}

- (void)testMenuBarVolumeIsOffUntilTurnedOn {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].showsMenuBarVolume);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.showsMenuBarVolume = YES;
    XCTAssertTrue([[APBPriorityStore alloc] initWithDefaults:defaults].showsMenuBarVolume);
}

- (void)testMenuBarShowsOnlyTheOutputUntilChanged {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
        APBMenuBarDevicesOutputOnly);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.menuBarDevices = APBMenuBarDevicesBothLabeled;
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
        APBMenuBarDevicesBothLabeled);
    [defaults setObject:@"unknown" forKey:@"menuBarDevices"];
    XCTAssertEqual([[APBPriorityStore alloc] initWithDefaults:defaults].menuBarDevices,
        APBMenuBarDevicesOutputOnly);
}

#pragma mark - Display outputs

- (void)testDisplayOutputsAreHiddenOnceAndShowingOneSticks {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *dell = monitor(@"dell", @"DELL U2518D");
    [store rememberDevices:@[ dell ]];
    // Hidden in both categories, so a later move between Speakers and
    // Headphones cannot surface a display the user never asked to see.
    XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
    XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);

    [store unhide:dell fromCategory:APBOutputCategorySpeaker];
    [store unhide:dell fromCategory:APBOutputCategoryHeadphone];
    [store rememberDevices:@[ dell ]];

    // Deciding once is the whole point: a later sighting must not undo
    // the user showing it by hand.
    XCTAssertFalse([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
    XCTAssertFalse([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);
}

- (void)testDisplayDefaultAppliesToNewDevicesRatherThanRetroactively {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.hideNewDisplayOutputs = NO;
    APBAudioDevice *seen = monitor(@"dell", @"DELL U2518D");
    [store rememberDevices:@[ seen ]];
    XCTAssertFalse([store isHidden:seen inCategory:APBOutputCategorySpeaker]);

    store.hideNewDisplayOutputs = YES;
    [store rememberDevices:@[ seen ]];
    // Already dealt with, so enabling the preference leaves it alone.
    XCTAssertFalse([store isHidden:seen inCategory:APBOutputCategorySpeaker]);

    APBAudioDevice *arrived = monitor(@"dell2", @"DELL U2720Q");
    [store rememberDevices:@[ arrived ]];
    XCTAssertTrue([store isHidden:arrived inCategory:APBOutputCategorySpeaker]);
    XCTAssertTrue([store isHidden:arrived inCategory:APBOutputCategoryHeadphone]);
}

- (void)testDisplayDefaultLeavesOtherOutputsAndMicrophonesAlone {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *speaker = outputDeviceNamed(@"speakers", @"Haut-parleurs MacBook Pro");
    APBAudioDevice *mic = inputDevice(@"mic");
    [store rememberDevices:@[ speaker, mic ]];

    XCTAssertFalse([store isHidden:speaker inCategory:APBOutputCategorySpeaker]);
    XCTAssertFalse([store isHidden:mic]);
}

- (void)testDisplayPreferenceDefaultsOnAndPersistsOff {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    XCTAssertTrue(store.hideNewDisplayOutputs);

    store.hideNewDisplayOutputs = NO;

    XCTAssertFalse([[APBPriorityStore alloc] initWithDefaults:defaults].hideNewDisplayOutputs);
}

- (void)testForgettingADisplayLetsItBeTreatedAsNewAgain {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *dell = monitor(@"dell", @"DELL U2518D");
    [store rememberDevices:@[ dell ]];
    [store unhide:dell fromCategory:APBOutputCategorySpeaker];
    [store unhide:dell fromCategory:APBOutputCategoryHeadphone];

    [store forgetUID:dell.uid role:APBDeviceRoleOutput];
    [store rememberDevices:@[ dell ]];

    XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategorySpeaker]);
    XCTAssertTrue([store isHidden:dell inCategory:APBOutputCategoryHeadphone]);
}

- (void)testForgettingOneRolePreservesTheOther {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *input = inputDevice(@"shared");
    APBAudioDevice *output = outputDevice(@"shared");
    [store rememberDevices:@[ input, output ]];
    [store savePriorities:@[ input ] role:APBDeviceRoleInput];
    [store savePriorities:@[ output ] category:APBOutputCategorySpeaker];
    [store setNeverUse:input value:YES];
    [store setNeverUse:output value:YES];
    [store hide:input];
    [store hide:output inCategory:APBOutputCategorySpeaker];

    [store forgetUID:@"shared" role:APBDeviceRoleInput];

    XCTAssertNil([store storedDeviceWithUID:@"shared" role:APBDeviceRoleInput]);
    XCTAssertNotNil([store storedDeviceWithUID:@"shared" role:APBDeviceRoleOutput]);
    XCTAssertFalse([store isNeverUse:input]);
    XCTAssertTrue([store isNeverUse:output]);
    XCTAssertEqualObjects([defaults stringArrayForKey:@"inputPriorities"], (@[ ]));
    XCTAssertEqualObjects([defaults stringArrayForKey:@"speakerPriorities"], (@[ @"shared" ]));
}

#pragma mark - Selection

- (void)testSelectionSkipsUnavailableDevices {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *disconnected = [outputDevice(@"disconnected") deviceWithConnected:NO];
    APBAudioDevice *hidden = outputDevice(@"hidden");
    APBAudioDevice *never = outputDevice(@"never");
    APBAudioDevice *unlinked = outputDevice(@"unlinked");
    APBAudioDevice *selected = outputDevice(@"selected");
    [store hide:hidden];
    [store setNeverUse:never value:YES];

    APBAudioDevice *result = [store firstSelectableIn:@[ disconnected, hidden, never, unlinked, selected ]
        isUsable:^BOOL(APBAudioDevice *device) {
            return ![device.uid isEqualToString:@"unlinked"];
        }];
    XCTAssertEqualObjects(result.uid, selected.uid);
}

#pragma mark - Headphone detection

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
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];

    // A speaker that a brand keyword would misfile as headphones.
    XCTAssertEqual([store categoryForDevice:declaring(@"anker", @"Anker PowerConf S3", APBOutputCategorySpeaker)],
    APBOutputCategorySpeaker);
    // A localized name no English keyword matches, the headphone jack.
    XCTAssertEqual([store categoryForDevice:declaring(@"jack", @"Écouteurs externes", APBOutputCategoryHeadphone)],
    APBOutputCategoryHeadphone);
    // Without a claim the keyword list still decides, both ways.
    XCTAssertEqual([store categoryForDevice:declaring(@"jack", @"Écouteurs externes", APBOutputCategoryNone)],
    APBOutputCategorySpeaker);
    XCTAssertEqual([store categoryForDevice:declaring(@"pods", @"AirPods Pro", APBOutputCategoryNone)],
    APBOutputCategoryHeadphone);
}

- (void)testKnownSpeakerWinsEvenWhenTheDeviceClaimsHeadphones {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    // CoreAudio has no speakerphone terminal type, so a Speak may report
    // headphones. The product rule has to sit ahead of the claim to cover
    // tobi/AudioPriorityBar#39.
    APBAudioDevice *speak = declaring(@"speak", @"Jabra Speak2 75", APBOutputCategoryHeadphone);
    XCTAssertEqual([store categoryForDevice:speak], APBOutputCategorySpeaker);

    // The user still overrides everything, including that rule.
    [store setCategory:APBOutputCategoryHeadphone forDevice:speak];
    XCTAssertEqual([store categoryForDevice:speak], APBOutputCategoryHeadphone);
}

- (void)testRememberedDeviceKeepsWhatTheHardwareDeclared {
    NSUserDefaults *defaults = defaultsFromFixture(nil);
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    [store rememberDevices:@[ declaring(@"jack", @"Écouteurs externes", APBOutputCategoryHeadphone) ]];

    // Reconstructed while disconnected it must not fall back to the
    // keyword result, or it would change list the moment it is unplugged.
    APBStoredDevice *remembered = [store storedDeviceWithUID:@"jack" role:APBDeviceRoleOutput];
    XCTAssertNotNil(remembered);
    XCTAssertEqual(remembered.declaredCategory, APBOutputCategoryHeadphone);
    XCTAssertEqual([store categoryForDevice:remembered.disconnectedDevice], APBOutputCategoryHeadphone);
}

- (void)testStoredDevicesWrittenBeforeDeclarationsStillDecode {
    // The JSON the Swift app wrote before declarations were persisted.
    NSData *json = [@"[{\"uid\":\"old\",\"name\":\"Old Speaker\",\"isInput\":false,\"lastSeen\":0}]"
        dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *entries = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    XCTAssertEqual(entries.count, 1u);
    APBStoredDevice *decoded = [APBStoredDevice deviceWithJSONObject:entries.firstObject];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.declaredCategory, APBOutputCategoryNone);
}

@end

NS_ASSUME_NONNULL_END
