#import <CoreAudio/CoreAudio.h>
#import <XCTest/XCTest.h>
#import "CoreAudioListeners.h"
#import "CoreAudioProperties.h"
#import "TestSupport.h"

@interface APBListenerLog : NSObject
@property (nonatomic, strong) NSMutableArray<NSNumber *> *systemAdds;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *systemRemoves;
@property (nonatomic, strong) NSMutableArray<APBDeviceListener *> *deviceAdds;
@property (nonatomic, strong) NSMutableArray<APBDeviceListener *> *deviceRemoves;
/// `@(APBSystemListener)`, or nil when none fails.
@property (nonatomic, strong, nullable) NSNumber *failingSystem;
@end

@implementation APBListenerLog

- (instancetype)init {
    if ((self = [super init])) {
        _systemAdds = [NSMutableArray array];
        _systemRemoves = [NSMutableArray array];
        _deviceAdds = [NSMutableArray array];
        _deviceRemoves = [NSMutableArray array];
    }
    return self;
}

@end

static APBCoreAudioListenerLifecycle *Lifecycle(APBListenerLog *log, NSArray<NSNumber *> *(^deviceIDs)(void)) {
    return [[APBCoreAudioListenerLifecycle alloc]
        initWithAddSystem:^BOOL(APBSystemListener listener) {
            [log.systemAdds addObject:@(listener)];
            return !(log.failingSystem && log.failingSystem.integerValue == listener);
        }
        removeSystem:^(APBSystemListener listener) { [log.systemRemoves addObject:@(listener)]; }
        deviceIDs:deviceIDs
        addDevice:^BOOL(APBDeviceListener *listener) {
            [log.deviceAdds addObject:listener];
            return YES;
        }
        removeDevice:^(APBDeviceListener *listener) { [log.deviceRemoves addObject:listener]; }];
}

@interface CoreAudioLifecycleTests : XCTestCase
@end

@implementation CoreAudioLifecycleTests

/// Values measured on real hardware, so the mapper is pinned to what macOS
/// actually reports rather than to what the headers suggest.
- (void)testTerminalMappingCoversBothValueSpaces {
    // USB and Bluetooth arrive translated into CoreAudio constants.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x68647068], APBOutputCategoryHeadphone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x73706B72], APBOutputCategorySpeaker);
    // Built-in devices report the raw USB Audio codes.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0302], APBOutputCategoryHeadphone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0301], APBOutputCategorySpeaker);
    // A speakerphone has no CoreAudio constant, only the raw codes.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0403], APBOutputCategorySpeaker);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0404], APBOutputCategorySpeaker);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0405], APBOutputCategorySpeaker);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x0402], APBOutputCategoryHeadphone);
}

- (void)testTerminalMappingDeclaresNothingForAmbiguousTerminals {
    // Aggregate devices report Unknown, and a monitor reports its own port.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0], APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x68646D69], APBOutputCategoryNone); // 'hdmi'
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x73706466], APBOutputCategoryNone); // 'spdf'
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminal:0x6C696E65], APBOutputCategoryNone); // 'line'
}

- (void)testStreamsMustAgreeBeforeTheyCountAsEvidence {
    // Every measured device has one stream, which is the ordinary case.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[@0x0301]], APBOutputCategorySpeaker);
    // An unrecognised stream alongside a recognised one does not veto it.
    XCTAssertEqual(([APBCoreAudioProperties categoryForTerminals:@[@0, @0x0302]]), APBOutputCategoryHeadphone);
    // Nothing recognised means no claim, so the caller falls back.
    XCTAssertEqual(([APBCoreAudioProperties categoryForTerminals:@[@0, @0x68646D69]]), APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[]], APBOutputCategoryNone);
    // Disagreement is no evidence rather than a coin toss on stream order.
    XCTAssertEqual(([APBCoreAudioProperties categoryForTerminals:@[@0x0301, @0x0302]]), APBOutputCategoryNone);
}

- (void)testBluetoothHeadphonesTerminalIsNoEvidence {
    // Measured: an Echo Dot, a Bluetooth loudspeaker, reports 'hdph'.
    UInt32 headphones = 0x68647068; // 'hdph'
    UInt32 speaker = 0x73706B72; // 'spkr'
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[@(headphones)]
                                                      transport:kAudioDeviceTransportTypeBluetooth],
                   APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[@(headphones)]
                                                      transport:kAudioDeviceTransportTypeBluetoothLE],
                   APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[@(speaker)]
                                                      transport:kAudioDeviceTransportTypeBluetooth],
                   APBOutputCategorySpeaker);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[@(headphones)]
                                                      transport:kAudioDeviceTransportTypeUSB],
                   APBOutputCategoryHeadphone);
}

- (void)testOnlyVideoCableTransportsCountAsDisplayOutputs {
    // Both attached Dell panels report HDMI, including the one behind a
    // USB-C hub, so the hub does not need its own case.
    XCTAssertTrue([APBCoreAudioProperties isDisplayTransport:0x68646D69]); // 'hdmi'
    XCTAssertTrue([APBCoreAudioProperties isDisplayTransport:0x64707274]); // 'dprt'

    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x626C746E]); // 'bltn'
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x75736220]); // 'usb '
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x626C7565]); // 'blue'
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x76697274]); // 'virt'
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x67727570]); // 'grup'
    // Thunderbolt carries a dock rather than a panel, so it is left out.
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0x7468756E]); // 'thun'
    XCTAssertFalse([APBCoreAudioProperties isDisplayTransport:0]);
}

- (void)testListenerStartRollsBackPartialRegistration {
    APBListenerLog *log = [[APBListenerLog alloc] init];
    log.failingSystem = @(APBSystemListenerDefaultOutput);
    APBCoreAudioListenerLifecycle *sut = Lifecycle(log, ^{ return @[@42]; });

    XCTAssertFalse([sut start]);
    XCTAssertEqualObjects(log.systemAdds, (@[@(APBSystemListenerDevices),
                                             @(APBSystemListenerDefaultInput),
                                             @(APBSystemListenerDefaultOutput)]));
    XCTAssertEqualObjects(log.systemRemoves, (@[@(APBSystemListenerDefaultInput),
                                                @(APBSystemListenerDevices)]));
    XCTAssertEqual(log.deviceAdds.count, 0u);
    XCTAssertFalse(sut.isListening);
}

- (void)testListenerStartRegistersMuteVolumeAndActivityPerDevice {
    APBListenerLog *log = [[APBListenerLog alloc] init];
    APBCoreAudioListenerLifecycle *sut = Lifecycle(log, ^{ return @[@10, @20]; });

    XCTAssertTrue([sut start]);
    XCTAssertEqualObjects(log.systemAdds, (@[@(APBSystemListenerDevices),
                                             @(APBSystemListenerDefaultInput),
                                             @(APBSystemListenerDefaultOutput)]));
    NSSet<APBDeviceListener *> *expected = [NSSet setWithArray:@[
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleOutput element:1],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleInput element:1],
        [APBDeviceListener volumeWithID:10],
        [APBDeviceListener inputVolumeWithID:10],
        [APBDeviceListener runningWithID:10],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleOutput element:1],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleInput element:1],
        [APBDeviceListener volumeWithID:20],
        [APBDeviceListener inputVolumeWithID:20],
        [APBDeviceListener runningWithID:20],
    ]];
    XCTAssertEqualObjects([NSSet setWithArray:log.deviceAdds], expected);
}

- (void)testRecycledDeviceIDStillForcesRemoveThenReadd {
    APBListenerLog *log = [[APBListenerLog alloc] init];
    APBCoreAudioListenerLifecycle *sut = Lifecycle(log, ^{ return @[@42]; });
    XCTAssertTrue([sut start]);
    [log.deviceAdds removeAllObjects];

    [sut rebuildDeviceListeners];

    XCTAssertEqual(log.deviceRemoves.count, 7u);
    XCTAssertEqual(log.deviceAdds.count, 7u);
    XCTAssertEqualObjects([NSSet setWithArray:log.deviceRemoves], [NSSet setWithArray:log.deviceAdds]);
}

- (void)testStopIsIdempotentAndAllowsRestart {
    APBListenerLog *log = [[APBListenerLog alloc] init];
    APBCoreAudioListenerLifecycle *sut = Lifecycle(log, ^{ return @[@1]; });
    XCTAssertTrue([sut start]);

    [sut stop];
    [sut stop];

    XCTAssertEqual(log.deviceRemoves.count, 7u);
    XCTAssertEqualObjects(log.systemRemoves, (@[@(APBSystemListenerDevices),
                                                @(APBSystemListenerDefaultInput),
                                                @(APBSystemListenerDefaultOutput)]));
    XCTAssertFalse(sut.isListening);
    XCTAssertTrue([sut start]);
}

- (void)testCallbackGateDropsEventsAfterStop {
    NSLock *lock = [[NSLock alloc] init];
    __block NSInteger counter = 0;
    APBCoreAudioCallbackGate *gate = [[APBCoreAudioCallbackGate alloc]
        initWithHandler:^(APBCoreAudioEventKind kind, APBDeviceRole role) {
            [lock lock];
            counter += 1;
            [lock unlock];
        }];

    [gate setActive:YES];
    [gate send:APBCoreAudioEventDevicesChanged role:APBDeviceRoleOutput];
    [gate setActive:NO];
    [gate send:APBCoreAudioEventMuteOrVolumeChanged role:APBDeviceRoleOutput];

    [lock lock];
    NSInteger value = counter;
    [lock unlock];
    XCTAssertEqual(value, 1);
}

@end
