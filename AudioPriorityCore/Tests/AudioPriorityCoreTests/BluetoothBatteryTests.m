#import <XCTest/XCTest.h>
#import "AudioPriorityCore.h"

static NSData *Sample(void) {
    return [@"{\"SPBluetoothDataType\": [{\n"
        "  \"device_connected\": [\n"
        "    {\"Dave’s AirPods Pro\": {\n"
        "      \"device_address\": \"70:AE:2A:5E:21:CD\",\n"
        "      \"device_batteryLevelCase\": \"73%\",\n"
        "      \"device_batteryLevelLeft\": \"100%\",\n"
        "      \"device_batteryLevelRight\": \"95%\",\n"
        "      \"device_vendorID\": \"0x004C\"\n"
        "    }},\n"
        "    {\"AirPods Max\": {\n"
        "      \"device_address\": \"11:22:33:44:55:66\",\n"
        "      \"device_batteryLevelMain\": \"40%\",\n"
        "      \"device_vendorID\": \"0x004C\"\n"
        "    }},\n"
        "    {\"Other Headset\": {\n"
        "      \"device_address\": \"AA:BB:CC:DD:EE:FF\",\n"
        "      \"device_batteryLevelMain\": \"50%\",\n"
        "      \"device_vendorID\": \"0x0A12\"\n"
        "    }},\n"
        "    {\"Magic Keyboard\": {\n"
        "      \"device_address\": \"12:34:56:78:9A:BC\",\n"
        "      \"device_vendorID\": \"0x004C\"\n"
        "    }}\n"
        "  ],\n"
        "  \"device_not_connected\": [\n"
        "    {\"Old AirPods\": {\n"
        "      \"device_address\": \"E4:90:FD:64:D9:70\",\n"
        "      \"device_batteryLevelCase\": \"10%\",\n"
        "      \"device_vendorID\": \"0x004C\"\n"
        "    }}\n"
        "  ]\n"
        "}]}" dataUsingEncoding:NSUTF8StringEncoding];
}

static APBBatteryLevels *Levels(NSNumber *left, NSNumber *right, NSNumber *caseLevel, NSNumber *main) {
    return [APBBatteryLevels levelsWithLeft:left right:right caseLevel:caseLevel main:main headset:nil];
}

@interface BluetoothBatteryTests : XCTestCase
@end

@implementation BluetoothBatteryTests

- (void)testBatteryParsingKeepsConnectedAppleDevicesWithLevels {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:Sample()];
    XCTAssertEqualObjects(report.byAddress, (@{
        @"70AE2A5E21CD": Levels(@100, @95, @73, nil),
        @"112233445566": Levels(nil, nil, nil, @40),
    }));
    XCTAssertEqualObjects(report.byName[@"AirPods Max"], Levels(nil, nil, nil, @40));
}

- (void)testBatteryLevelsMatchCoreAudioBluetoothUIDs {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:Sample()];
    APBAudioDevice *output = [[APBAudioDevice alloc] initWithPlatformID:1
                                                                    uid:@"70-AE-2A-5E-21-CD:output"
                                                                   name:@"Renamed"
                                                                   role:APBDeviceRoleOutput];
    APBAudioDevice *input = [[APBAudioDevice alloc] initWithPlatformID:2
                                                                   uid:@"70-AE-2A-5E-21-CD:input"
                                                                  name:@"Renamed"
                                                                  role:APBDeviceRoleInput];
    XCTAssertEqualObjects([report levelsForDevice:output].caseLevel, @73);
    XCTAssertEqualObjects([report levelsForDevice:input].left, @100);
}

- (void)testBatteryLevelsFallBackToNameAndIgnoreOtherDevices {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:Sample()];
    APBAudioDevice *byName = [[APBAudioDevice alloc] initWithPlatformID:1
                                                                    uid:@"odd-uid"
                                                                   name:@"AirPods Max"
                                                                   role:APBDeviceRoleOutput];
    APBAudioDevice *builtIn = [[APBAudioDevice alloc] initWithPlatformID:2
                                                                     uid:@"BuiltInSpeakerDevice"
                                                                    name:@"MacBook Pro Speakers"
                                                                    role:APBDeviceRoleOutput];
    XCTAssertEqualObjects([report levelsForDevice:byName], Levels(nil, nil, nil, @40));
    XCTAssertNil([report levelsForDevice:builtIn]);
}

- (void)testBatteryParsingToleratesUnexpectedOutput {
    APBBluetoothBatteryReport *empty = [[APBBluetoothBatteryReport alloc] init];
    XCTAssertEqualObjects([APBBluetoothBattery parse:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]], empty);
    XCTAssertEqualObjects([APBBluetoothBattery parse:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]], empty);
}

- (void)testBatteryBadgesShowDifferingEarbudsSeparatelyThenTheCase {
    NSArray<APBBatteryBadge *> *badges = Levels(@90, @100, @73, nil).badges;
    XCTAssertEqualObjects([badges valueForKey:@"text"], (@[@"L 90% R 100%", @"73%"]));
    XCTAssertEqualObjects([badges valueForKey:@"icon"], (@[@"airpods", @"airpods.chargingcase"]));
    XCTAssertEqualObjects([badges valueForKey:@"spokenText"],
                          (@[@"Left earbud 90%, Right earbud 100%", @"Case 73%"]));
}

- (void)testBatteryBadgesShowMatchingEarbudsAsOneNumber {
    NSArray<APBBatteryBadge *> *badges = Levels(@100, @100, @73, nil).badges;
    XCTAssertEqualObjects([badges valueForKey:@"text"], (@[@"100%", @"73%"]));
    XCTAssertEqualObjects(badges.firstObject.spokenText, @"Earbuds 100%");
}

- (void)testBatteryBadgesShowWhicheverEarbudReports {
    XCTAssertEqualObjects([Levels(@90, nil, nil, nil).badges valueForKey:@"text"], (@[@"L 90%"]));
    XCTAssertEqualObjects([Levels(nil, @85, @40, nil).badges valueForKey:@"text"], (@[@"R 85%", @"40%"]));
    XCTAssertEqualObjects([Levels(nil, nil, @40, nil).badges valueForKey:@"spokenText"], (@[@"Case 40%"]));
    XCTAssertEqual(Levels(nil, nil, nil, nil).badges.count, 0);
}

- (void)testBatteryBadgesShowASingleBattery {
    XCTAssertEqualObjects(Levels(nil, nil, nil, @55).badges, (@[
        [[APBBatteryBadge alloc] initWithIcon:@"airpodsmax" text:@"55%" spokenText:@"Battery 55%" level:55],
    ]));
}

- (void)testBatteryBadgesFlagLowLevelsByTheLowestEarbud {
    NSArray<APBBatteryBadge *> *badges = Levels(@80, @20, @21, nil).badges;
    XCTAssertEqualObjects([badges valueForKey:@"isLow"], (@[@YES, @NO]));
    XCTAssertTrue(Levels(nil, nil, nil, @5).badges.firstObject.isLow);
}

@end
