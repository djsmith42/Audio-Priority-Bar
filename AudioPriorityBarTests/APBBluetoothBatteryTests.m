#import <XCTest/XCTest.h>
#import "APBBluetoothBattery.h"
#import "APBModels.h"

@interface APBBluetoothBatteryTests : XCTestCase
@end

@implementation APBBluetoothBatteryTests

- (NSString *)sample {
    return @"{\"SPBluetoothDataType\": [{"
        "\"device_connected\": ["
        "{\"Dave’s AirPods Pro\": {"
        "\"device_address\": \"70:AE:2A:5E:21:CD\","
        "\"device_batteryLevelCase\": \"73%\","
        "\"device_batteryLevelLeft\": \"100%\","
        "\"device_batteryLevelRight\": \"95%\","
        "\"device_vendorID\": \"0x004C\""
        "}},"
        "{\"AirPods Max\": {"
        "\"device_address\": \"11:22:33:44:55:66\","
        "\"device_batteryLevelMain\": \"40%\","
        "\"device_vendorID\": \"0x004C\""
        "}},"
        "{\"Other Headset\": {"
        "\"device_address\": \"AA:BB:CC:DD:EE:FF\","
        "\"device_batteryLevelMain\": \"50%\","
        "\"device_vendorID\": \"0x0A12\""
        "}},"
        "{\"Magic Keyboard\": {"
        "\"device_address\": \"12:34:56:78:9A:BC\","
        "\"device_vendorID\": \"0x004C\""
        "}}"
        "],"
        "\"device_not_connected\": ["
        "{\"Old AirPods\": {"
        "\"device_address\": \"E4:90:FD:64:D9:70\","
        "\"device_batteryLevelCase\": \"10%\","
        "\"device_vendorID\": \"0x004C\""
        "}}"
        "]"
        "}]}";
}

- (APBBatteryLevels *)levelsWithLeft:(NSInteger)left
                               right:(NSInteger)right
                           caseLevel:(NSInteger)caseLevel
                                main:(NSInteger)main {
    return [[APBBatteryLevels alloc] initWithLeft:left right:right caseLevel:caseLevel main:main];
}

- (BOOL)levels:(APBBatteryLevels *)actual
    equalsLeft:(NSInteger)left
         right:(NSInteger)right
     caseLevel:(NSInteger)caseLevel
          main:(NSInteger)main {
    APBBatteryLevels *expected = [self levelsWithLeft:left right:right caseLevel:caseLevel main:main];
    return actual.left == expected.left && actual.right == expected.right &&
           actual.caseLevel == expected.caseLevel && actual.main == expected.main;
}

- (NSArray<NSString *> *)badgeTexts:(NSArray<APBBatteryBadge *> *)badges {
    return [badges valueForKey:@"text"];
}

- (NSArray<NSString *> *)badgeIcons:(NSArray<APBBatteryBadge *> *)badges {
    return [badges valueForKey:@"icon"];
}

- (NSArray<NSString *> *)badgeSpokenTexts:(NSArray<APBBatteryBadge *> *)badges {
    return [badges valueForKey:@"spokenText"];
}

- (void)testBatteryParsingKeepsConnectedAppleDevicesWithLevels {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:[[self sample] dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(report.byAddress.count, 2);
    XCTAssertTrue([self levels:report.byAddress[@"70AE2A5E21CD"]
                   equalsLeft:100
                        right:95
                    caseLevel:73
                         main:APBBatteryLevelNone]);
    XCTAssertTrue([self levels:report.byAddress[@"112233445566"]
                   equalsLeft:APBBatteryLevelNone
                        right:APBBatteryLevelNone
                    caseLevel:APBBatteryLevelNone
                         main:40]);
    XCTAssertTrue([self levels:report.byName[@"AirPods Max"]
                   equalsLeft:APBBatteryLevelNone
                        right:APBBatteryLevelNone
                    caseLevel:APBBatteryLevelNone
                         main:40]);
}

- (void)testBatteryLevelsMatchCoreAudioBluetoothUIDs {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:[[self sample] dataUsingEncoding:NSUTF8StringEncoding]];
    APBAudioDevice *output = [[APBAudioDevice alloc] initWithPlatformID:1
                                                                    uid:@"70-AE-2A-5E-21-CD:output"
                                                                   name:@"Renamed"
                                                                   role:APBDeviceRoleOutput];
    APBAudioDevice *input = [[APBAudioDevice alloc] initWithPlatformID:2
                                                                   uid:@"70-AE-2A-5E-21-CD:input"
                                                                  name:@"Renamed"
                                                                  role:APBDeviceRoleInput];
    XCTAssertEqual([report levelsForDevice:output].caseLevel, 73);
    XCTAssertEqual([report levelsForDevice:input].left, 100);
}

- (void)testBatteryLevelsFallBackToNameAndIgnoreOtherDevices {
    APBBluetoothBatteryReport *report = [APBBluetoothBattery parse:[[self sample] dataUsingEncoding:NSUTF8StringEncoding]];
    APBAudioDevice *byName = [[APBAudioDevice alloc] initWithPlatformID:1
                                                                    uid:@"odd-uid"
                                                                   name:@"AirPods Max"
                                                                   role:APBDeviceRoleOutput];
    APBAudioDevice *builtIn = [[APBAudioDevice alloc] initWithPlatformID:2
                                                                     uid:@"BuiltInSpeakerDevice"
                                                                    name:@"MacBook Pro Speakers"
                                                                    role:APBDeviceRoleOutput];
    XCTAssertEqual([report levelsForDevice:byName].main, 40);
    XCTAssertNil([report levelsForDevice:builtIn]);
}

- (void)testBatteryParsingToleratesUnexpectedOutput {
    APBBluetoothBatteryReport *notJSON = [APBBluetoothBattery parse:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]];
    APBBluetoothBatteryReport *empty = [APBBluetoothBattery parse:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(notJSON.byAddress.count, 0);
    XCTAssertEqual(notJSON.byName.count, 0);
    XCTAssertEqual(empty.byAddress.count, 0);
    XCTAssertEqual(empty.byName.count, 0);
}

- (void)testBatteryBadgesShowDifferingEarbudsSeparatelyThenTheCase {
    NSArray<APBBatteryBadge *> *badges =
        [[self levelsWithLeft:90 right:100 caseLevel:73 main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([self badgeTexts:badges], (@[ @"L 90% R 100%", @"73%" ]));
    XCTAssertEqualObjects([self badgeIcons:badges], (@[ @"airpods", @"airpods.chargingcase" ]));
    XCTAssertEqualObjects([self badgeSpokenTexts:badges],
                           (@[ @"Left earbud 90%, Right earbud 100%", @"Case 73%" ]));
}

- (void)testBatteryBadgesShowMatchingEarbudsAsOneNumber {
    NSArray<APBBatteryBadge *> *badges =
        [[self levelsWithLeft:100 right:100 caseLevel:73 main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([self badgeTexts:badges], (@[ @"100%", @"73%" ]));
    XCTAssertEqualObjects([self badgeSpokenTexts:badges].firstObject, @"Earbuds 100%");
}

- (void)testBatteryBadgesShowWhicheverEarbudReports {
    NSArray<APBBatteryBadge *> *leftOnly =
        [[self levelsWithLeft:90 right:APBBatteryLevelNone caseLevel:APBBatteryLevelNone
                          main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([self badgeTexts:leftOnly], (@[ @"L 90%" ]));
    NSArray<APBBatteryBadge *> *rightAndCase =
        [[self levelsWithLeft:APBBatteryLevelNone right:85 caseLevel:40
                          main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([self badgeTexts:rightAndCase], (@[ @"R 85%", @"40%" ]));
    NSArray<APBBatteryBadge *> *caseOnly =
        [[self levelsWithLeft:APBBatteryLevelNone right:APBBatteryLevelNone caseLevel:40
                          main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([self badgeSpokenTexts:caseOnly], (@[ @"Case 40%" ]));
    XCTAssertEqual([[self levelsWithLeft:APBBatteryLevelNone right:APBBatteryLevelNone
                                caseLevel:APBBatteryLevelNone main:APBBatteryLevelNone] badges].count, 0);
}

- (void)testBatteryBadgesShowASingleBattery {
    NSArray<APBBatteryBadge *> *badges =
        [[self levelsWithLeft:APBBatteryLevelNone right:APBBatteryLevelNone
                    caseLevel:APBBatteryLevelNone main:55] badges];
    XCTAssertEqual(badges.count, 1);
    XCTAssertEqualObjects(badges.firstObject.icon, @"airpodsmax");
    XCTAssertEqualObjects(badges.firstObject.text, @"55%");
    XCTAssertEqualObjects(badges.firstObject.spokenText, @"Battery 55%");
    // The Swift badge's `level` is not exposed in the Objective-C port, so the
    // level itself is not asserted here.
}

- (void)testBatteryBadgesFlagLowLevelsByTheLowestEarbud {
    NSArray<APBBatteryBadge *> *badges =
        [[self levelsWithLeft:80 right:20 caseLevel:21 main:APBBatteryLevelNone] badges];
    XCTAssertEqualObjects([badges valueForKey:@"isLow"], (@[ @YES, @NO ]));
    APBBatteryBadge *main = [[[self levelsWithLeft:APBBatteryLevelNone right:APBBatteryLevelNone
                                          caseLevel:APBBatteryLevelNone main:5] badges] firstObject];
    XCTAssertTrue(main.isLow);
}

@end
