#import <XCTest/XCTest.h>
#import <CoreAudio/CoreAudio.h>
#import "APBCoreAudio.h"
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Forwards CoreAudio's callbacks while active. The class is private to
/// APBCoreAudio.m, but its interface is redeclared here so the gate's behavior
/// can be tested, mirroring the Swift `CoreAudioCallbackGate` tests.
typedef NS_ENUM(NSInteger, APBCoreAudioEvent) {
    APBCoreAudioEventDevicesChanged,
    APBCoreAudioEventDefaultInputChanged,
    APBCoreAudioEventDefaultOutputChanged,
    APBCoreAudioEventMuteOrVolumeChanged,
};

@interface APBCoreAudioCallbackGate : NSObject
@property (nonatomic, copy) void (^handler)(APBCoreAudioEvent event);
- (void)setActive:(BOOL)active;
- (void)send:(APBCoreAudioEvent)event;
@end

/// A thread-safe counter, standing in for the Swift `Counter` class.
@interface APBEventCounter : NSObject
- (void)increment;
- (NSInteger)read;
@end

NS_ASSUME_NONNULL_END

@interface APBCoreAudioLifecycleTests : XCTestCase
@end

@implementation APBCoreAudioLifecycleTests {
    NSMutableArray<NSNumber *> *_systemAdds;
    NSMutableArray<NSNumber *> *_systemRemoves;
    NSMutableArray<APBDeviceListener *> *_deviceAdds;
    NSMutableArray<APBDeviceListener *> *_deviceRemoves;
    APBSystemListener _failingSystem;
}

- (void)setUp {
    _systemAdds = [NSMutableArray array];
    _systemRemoves = [NSMutableArray array];
    _deviceAdds = [NSMutableArray array];
    _deviceRemoves = [NSMutableArray array];
    _failingSystem = -1;
}

- (APBCoreAudioListenerLifecycle *)lifecycleWithDeviceIDs:(NSArray<NSNumber *> *)deviceIDs {
    return [[APBCoreAudioListenerLifecycle alloc]
        initWithAddSystem:^BOOL(APBSystemListener listener) {
            [self->_systemAdds addObject:@(listener)];
            return listener != self->_failingSystem;
        }
        removeSystem:^(APBSystemListener listener) {
            [self->_systemRemoves addObject:@(listener)];
        }
        deviceIDs:^NSArray<NSNumber *> *{
            return deviceIDs;
        }
        addDevice:^BOOL(APBDeviceListener *listener) {
            [self->_deviceAdds addObject:listener];
            return YES;
        }
        removeDevice:^(APBDeviceListener *listener) {
            [self->_deviceRemoves addObject:listener];
        }];
}

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
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@0, @0x0302])], APBOutputCategoryHeadphone);
    // Nothing recognised means no claim, so the caller falls back.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@0, @0x68646D69])], APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:@[]], APBOutputCategoryNone);
    // Disagreement is no evidence rather than a coin toss on stream order.
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@0x0301, @0x0302])], APBOutputCategoryNone);
}

- (void)testBluetoothHeadphonesTerminalIsNoEvidence {
    // Measured: an Echo Dot, a Bluetooth loudspeaker, reports 'hdph'.
    UInt32 headphones = 0x68647068; // 'hdph'
    UInt32 speaker = 0x73706B72;   // 'spkr'
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@(headphones)])
                                                       transport:kAudioDeviceTransportTypeBluetooth],
                    APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@(headphones)])
                                                       transport:kAudioDeviceTransportTypeBluetoothLE],
                    APBOutputCategoryNone);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@(speaker)])
                                                       transport:kAudioDeviceTransportTypeBluetooth],
                    APBOutputCategorySpeaker);
    XCTAssertEqual([APBCoreAudioProperties categoryForTerminals:(@[@(headphones)])
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
    _failingSystem = APBSystemListenerDefaultOutput;
    APBCoreAudioListenerLifecycle *sut = [self lifecycleWithDeviceIDs:@[@42]];

    XCTAssertFalse([sut start]);
    XCTAssertEqualObjects(_systemAdds, (@[ @(APBSystemListenerDevices),
                                           @(APBSystemListenerDefaultInput),
                                           @(APBSystemListenerDefaultOutput) ]));
    XCTAssertEqualObjects(_systemRemoves, (@[ @(APBSystemListenerDefaultInput),
                                             @(APBSystemListenerDevices) ]));
    XCTAssertEqual(_deviceAdds.count, 0);
    XCTAssertFalse(sut.isListening);
}

- (void)testListenerStartRegistersMuteVolumeAndActivityPerDevice {
    APBCoreAudioListenerLifecycle *sut = [self lifecycleWithDeviceIDs:@[@10, @20]];

    XCTAssertTrue([sut start]);
    XCTAssertEqualObjects(_systemAdds, (@[ @(APBSystemListenerDevices),
                                           @(APBSystemListenerDefaultInput),
                                           @(APBSystemListenerDefaultOutput) ]));
    NSSet<APBDeviceListener *> *expected = [NSSet setWithArray:@[
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleOutput element:1],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:10 role:APBDeviceRoleInput element:1],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindVolume deviceID:10],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindInputVolume deviceID:10],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindRunning deviceID:10],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleOutput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleOutput element:1],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleInput element:kAudioObjectPropertyElementMain],
        [APBDeviceListener muteWithID:20 role:APBDeviceRoleInput element:1],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindVolume deviceID:20],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindInputVolume deviceID:20],
        [APBDeviceListener listenerWithKind:APBDeviceListenerKindRunning deviceID:20],
    ]];
    XCTAssertEqualObjects([NSSet setWithArray:_deviceAdds], expected);
}

- (void)testRecycledDeviceIDStillForcesRemoveThenReadd {
    APBCoreAudioListenerLifecycle *sut = [self lifecycleWithDeviceIDs:@[@42]];
    XCTAssertTrue([sut start]);
    [_deviceAdds removeAllObjects];

    [sut rebuildDeviceListeners];

    XCTAssertEqual(_deviceRemoves.count, 7);
    XCTAssertEqual(_deviceAdds.count, 7);
    XCTAssertEqualObjects([NSSet setWithArray:_deviceRemoves], [NSSet setWithArray:_deviceAdds]);
}

- (void)testStopIsIdempotentAndAllowsRestart {
    APBCoreAudioListenerLifecycle *sut = [self lifecycleWithDeviceIDs:@[@1]];
    XCTAssertTrue([sut start]);

    [sut stop];
    [sut stop];

    XCTAssertEqual(_deviceRemoves.count, 7);
    XCTAssertEqualObjects(_systemRemoves, (@[ @(APBSystemListenerDevices),
                                               @(APBSystemListenerDefaultInput),
                                               @(APBSystemListenerDefaultOutput) ]));
    XCTAssertFalse(sut.isListening);
    XCTAssertTrue([sut start]);
}

- (void)testCallbackGateDropsEventsAfterStop {
    APBEventCounter *counter = [[APBEventCounter alloc] init];
    APBCoreAudioCallbackGate *gate = [[APBCoreAudioCallbackGate alloc] init];
    gate.handler = ^(APBCoreAudioEvent event) {
        [counter increment];
    };

    [gate setActive:YES];
    [gate send:APBCoreAudioEventDevicesChanged];
    [gate setActive:NO];
    [gate send:APBCoreAudioEventMuteOrVolumeChanged];

    XCTAssertEqual([counter read], 1);
}

@end

@implementation APBEventCounter {
    NSLock *_lock;
    NSInteger _value;
}

- (instancetype)init {
    self = [super init];
    if (self) _lock = [[NSLock alloc] init];
    return self;
}

- (void)increment {
    [_lock lock];
    _value += 1;
    [_lock unlock];
}

- (NSInteger)read {
    [_lock lock];
    NSInteger value = _value;
    [_lock unlock];
    return value;
}

@end
