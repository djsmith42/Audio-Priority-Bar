#import <XCTest/XCTest.h>
#import <CoreAudio/CoreAudio.h>
#import "TestSupport.h"
#import "DeviceIcon.h"

@interface DeviceIconCase : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic) APBDeviceRole role;
@property (nonatomic) UInt32 transport;
@property (nonatomic) BOOL isDisplayOutput;
@property (nonatomic) APBOutputCategory category;
@property (nonatomic, copy) NSString *expected;

@property (nonatomic, readonly) NSString *testDescription;
@property (nonatomic, readonly) APBAudioDevice *device;

@end

@implementation DeviceIconCase

- (NSString *)testDescription {
    return [NSString stringWithFormat:@"%@ (%@, %@)", _name, APBDeviceRoleName(_role),
                                      APBOutputCategoryName(_category) ?: @"no category"];
}

- (APBAudioDevice *)device {
    return [[APBAudioDevice alloc] initWithPlatformID:1
                                                  uid:_name
                                                 name:_name
                                                 role:_role
                                          isConnected:YES
                                            isVirtual:NO
                                     declaredCategory:APBOutputCategoryNone
                                      isDisplayOutput:_isDisplayOutput
                                        transportType:_transport];
}

@end

static DeviceIconCase *Case(NSString *name, APBDeviceRole role, UInt32 transport, APBOutputCategory category,
                      BOOL isDisplayOutput, NSString *expected) {
    DeviceIconCase *icon = [[DeviceIconCase alloc] init];
    icon.name = name;
    icon.role = role;
    icon.transport = transport;
    icon.category = category;
    icon.isDisplayOutput = isDisplayOutput;
    icon.expected = expected;
    return icon;
}

static DeviceIconCase *Output(NSString *name, UInt32 transport, APBOutputCategory category, NSString *expected) {
    return Case(name, APBDeviceRoleOutput, transport, category, NO, expected);
}

static DeviceIconCase *DisplayOutput(NSString *name, UInt32 transport, APBOutputCategory category, NSString *expected) {
    return Case(name, APBDeviceRoleOutput, transport, category, YES, expected);
}

static DeviceIconCase *Input(NSString *name, UInt32 transport, NSString *expected) {
    return Case(name, APBDeviceRoleInput, transport, APBOutputCategoryNone, NO, expected);
}

static const UInt32 usb = kAudioDeviceTransportTypeUSB;
static const UInt32 bluetooth = kAudioDeviceTransportTypeBluetooth;
static const UInt32 builtIn = kAudioDeviceTransportTypeBuiltIn;

/// Devices seen on a real Mac, with the transport each one reports.
static NSArray<DeviceIconCase *> *RealDevices(void) {
    return @[
        Input(@"Razer Kiyo", usb, @"web.camera"),
        DisplayOutput(@"DELL U3419W", kAudioDeviceTransportTypeHDMI, APBOutputCategorySpeaker, @"display"),
        DisplayOutput(@"DECIMATOR", kAudioDeviceTransportTypeDisplayPort, APBOutputCategorySpeaker, @"display"),
        Output(@"AirPods Pro", bluetooth, APBOutputCategoryHeadphone, @"airpodspro"),
        // Some AirPods report a lowercase "p", so matching must ignore case.
        Input(@"Airpods Pro", bluetooth, @"airpodspro"),
        Input(@"iPhone 16 Pro Microphone", kAudioDeviceTransportTypeContinuityCaptureWireless, @"iphone"),
        Output(@"PowerConf", usb, APBOutputCategorySpeaker, @"speaker.wave.2"),
        Output(@"Scarlett 2i2 USB", usb, APBOutputCategorySpeaker, @"speaker.wave.2"),
        Output(@"Microsoft Teams Audio", kAudioDeviceTransportTypeVirtual, APBOutputCategorySpeaker, @"waveform"),
        Input(@"MacBook Air Microphone", builtIn, @"laptopcomputer"),
        Output(@"MacBook Air Speakers", builtIn, APBOutputCategorySpeaker, @"laptopcomputer"),
    ];
}

/// One case for each remaining branch of `hardwareIcon`.
static NSArray<DeviceIconCase *> *Branches(void) {
    return @[
        Output(@"AirPods Max", bluetooth, APBOutputCategoryHeadphone, @"airpodsmax"),
        Output(@"AirPods", bluetooth, APBOutputCategoryHeadphone, @"airpods"),
        Output(@"Beats Studio Pro", bluetooth, APBOutputCategoryHeadphone, @"beats.headphones"),
        // Beats makes speakers too, so only the Headphones section gets the logo.
        Output(@"Beats Pill", bluetooth, APBOutputCategorySpeaker, @"hifispeaker"),
        Output(@"iPad", 0, APBOutputCategorySpeaker, @"ipad"),
        Output(@"Studio Display Speakers", usb, APBOutputCategorySpeaker, @"display"),
        Output(@"Living Room", kAudioDeviceTransportTypeAirPlay, APBOutputCategorySpeaker, @"airplayaudio"),
        Input(@"Desk Mic", kAudioDeviceTransportTypeContinuityCaptureWired, @"iphone"),
        Output(@"Multi-Output Device", kAudioDeviceTransportTypeAggregate, APBOutputCategorySpeaker, @"waveform"),
        Output(@"Auto Aggregate", kAudioDeviceTransportTypeAutoAggregate, APBOutputCategorySpeaker, @"waveform"),
        Input(@"USB Audio Device", usb, @"mic"),
        // The section is the user's choice, so a headset brand's name decides nothing.
        Output(@"Jabra Speak 510 USB", usb, APBOutputCategorySpeaker, @"speaker.wave.2"),
        Output(@"Jabra Evolve2 65", usb, APBOutputCategoryNone, @"speaker.wave.2"),
        Output(@"Jabra Evolve2 65", usb, APBOutputCategoryHeadphone, @"headphones"),
        // Studio monitors are speakers, not displays.
        Output(@"KRK Studio Monitor", usb, APBOutputCategorySpeaker, @"speaker.wave.2"),
        Output(@"SoundLink Flex", kAudioDeviceTransportTypeBluetoothLE, APBOutputCategorySpeaker, @"hifispeaker"),
        // The Headphones section decides over the transport too.
        Output(@"External Headphones", builtIn, APBOutputCategoryHeadphone, @"headphones"),
        Output(@"krisp speaker", kAudioDeviceTransportTypeVirtual, APBOutputCategoryHeadphone, @"headphones"),
        Output(@"MacBook Pro Speakers", builtIn, APBOutputCategorySpeaker, @"laptopcomputer"),
        Input(@"iMac Microphone", builtIn, @"desktopcomputer"),
        Output(@"Mac mini Speakers", builtIn, APBOutputCategorySpeaker, @"macmini"),
        Output(@"Mac Studio Speakers", builtIn, APBOutputCategorySpeaker, @"macstudio"),
        Output(@"Mac Pro Speakers", builtIn, APBOutputCategorySpeaker, @"macpro.gen3"),
        // The headphone jack is built in too, but it is not the Mac itself.
        Input(@"External Microphone", builtIn, @"mic"),
        // Only the Mac's own hardware gets its icon, not a device named after it.
        Output(@"MacBook Pro Speakers", kAudioDeviceTransportTypeVirtual, APBOutputCategorySpeaker, @"waveform"),
    ];
}

static NSArray<DeviceIconCase *> *AllCases(void) {
    return [RealDevices() arrayByAddingObjectsFromArray:Branches()];
}

@interface DeviceIconTests : XCTestCase
@end

@implementation DeviceIconTests

- (void)testHardwareIconMatchesTheDevice {
    for (DeviceIconCase *icon in AllCases()) {
        XCTAssertEqualObjects([icon.device hardwareIconForCategory:icon.category], icon.expected,
                              @"%@", icon.testDescription);
    }
}

- (void)testHardwareIconsListsEveryIconTheMenuBarMayShow {
    for (DeviceIconCase *icon in AllCases()) {
        XCTAssertTrue([APBAudioDevice.hardwareIcons containsObject:[icon.device menuBarIconForCategory:icon.category]],
                      @"%@", icon.testDescription);
    }
}

- (void)testTheMenuBarShowsTheMacsOwnDevicesByRole {
    XCTAssertEqualObjects([Input(@"MacBook Air Microphone", builtIn, @"").device
                              menuBarIconForCategory:APBOutputCategoryNone],
                          @"mic");
    XCTAssertEqualObjects([Output(@"MacBook Air Speakers", builtIn, APBOutputCategorySpeaker, @"").device
                              menuBarIconForCategory:APBOutputCategorySpeaker],
                          APBAudioDevice.genericSpeakerIcon);
}

@end
