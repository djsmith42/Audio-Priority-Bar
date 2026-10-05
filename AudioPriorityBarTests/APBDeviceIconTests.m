#import <CoreAudio/CoreAudio.h>
#import "APBTestSupport.h"
#import "APBDeviceIcon.h"

@interface APBIconCase : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) APBDeviceRole role;
@property (nonatomic) UInt32 transport;
@property (nonatomic) BOOL isDisplayOutput;
/// `None` for no category.
@property (nonatomic) APBOutputCategory category;
@property (nonatomic, copy) NSString *expected;
@property (nonatomic, readonly) APBAudioDevice *device;
@end

@implementation APBIconCase

+ (instancetype)output:(NSString *)name
             transport:(UInt32)transport
              category:(APBOutputCategory)category
       isDisplayOutput:(BOOL)isDisplayOutput
              expected:(NSString *)expected {
    APBIconCase *icon = [[APBIconCase alloc] init];
    icon.name = name;
    icon.role = APBDeviceRoleOutput;
    icon.transport = transport;
    icon.isDisplayOutput = isDisplayOutput;
    icon.category = category;
    icon.expected = expected;
    return icon;
}

+ (instancetype)input:(NSString *)name transport:(UInt32)transport expected:(NSString *)expected {
    APBIconCase *icon = [[APBIconCase alloc] init];
    icon.name = name;
    icon.role = APBDeviceRoleInput;
    icon.transport = transport;
    icon.category = APBOutputCategoryNone;
    icon.expected = expected;
    return icon;
}

- (NSString *)description {
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

static APBIconCase *Output(NSString *name, UInt32 transport, APBOutputCategory category, NSString *expected) {
    return [APBIconCase output:name transport:transport category:category isDisplayOutput:NO expected:expected];
}

static APBIconCase *DisplayOutput(NSString *name, UInt32 transport, APBOutputCategory category, NSString *expected) {
    return [APBIconCase output:name transport:transport category:category isDisplayOutput:YES expected:expected];
}

static APBIconCase *Input(NSString *name, UInt32 transport, NSString *expected) {
    return [APBIconCase input:name transport:transport expected:expected];
}

static const UInt32 usb = kAudioDeviceTransportTypeUSB;
static const UInt32 bluetooth = kAudioDeviceTransportTypeBluetooth;
static const UInt32 builtIn = kAudioDeviceTransportTypeBuiltIn;
static const APBOutputCategory speaker = APBOutputCategorySpeaker;
static const APBOutputCategory headphone = APBOutputCategoryHeadphone;
static const APBOutputCategory none = APBOutputCategoryNone;

/// Devices seen on a real Mac, with the transport each one reports.
static NSArray<APBIconCase *> *RealDevices(void) {
    return @[
        Input(@"Razer Kiyo", usb, @"web.camera"),
        DisplayOutput(@"DELL U3419W", kAudioDeviceTransportTypeHDMI, speaker, @"display"),
        DisplayOutput(@"DECIMATOR", kAudioDeviceTransportTypeDisplayPort, speaker, @"display"),
        Output(@"AirPods Pro", bluetooth, headphone, @"airpodspro"),
        // Some AirPods report a lowercase "p", so matching must ignore case.
        Input(@"Airpods Pro", bluetooth, @"airpodspro"),
        Input(@"iPhone 16 Pro Microphone", kAudioDeviceTransportTypeContinuityCaptureWireless, @"iphone"),
        Output(@"PowerConf", usb, speaker, @"speaker.wave.2"),
        Output(@"Scarlett 2i2 USB", usb, speaker, @"speaker.wave.2"),
        Output(@"Microsoft Teams Audio", kAudioDeviceTransportTypeVirtual, speaker, @"waveform"),
        Input(@"MacBook Air Microphone", builtIn, @"laptopcomputer"),
        Output(@"MacBook Air Speakers", builtIn, speaker, @"laptopcomputer"),
    ];
}

/// One case for each remaining branch of `hardwareIconForCategory:`.
static NSArray<APBIconCase *> *Branches(void) {
    return @[
        Output(@"AirPods Max", bluetooth, headphone, @"airpodsmax"),
        Output(@"AirPods", bluetooth, headphone, @"airpods"),
        Output(@"Beats Studio Pro", bluetooth, headphone, @"beats.headphones"),
        // Beats makes speakers too, so only the Headphones section gets the logo.
        Output(@"Beats Pill", bluetooth, speaker, @"hifispeaker"),
        Output(@"iPad", 0, speaker, @"ipad"),
        Output(@"Studio Display Speakers", usb, speaker, @"display"),
        Output(@"Living Room", kAudioDeviceTransportTypeAirPlay, speaker, @"airplayaudio"),
        Input(@"Desk Mic", kAudioDeviceTransportTypeContinuityCaptureWired, @"iphone"),
        Output(@"Multi-Output Device", kAudioDeviceTransportTypeAggregate, speaker, @"waveform"),
        Output(@"Auto Aggregate", kAudioDeviceTransportTypeAutoAggregate, speaker, @"waveform"),
        Input(@"USB Audio Device", usb, @"mic"),
        // The section is the user's choice, so a headset brand's name decides nothing.
        Output(@"Jabra Speak 510 USB", usb, speaker, @"speaker.wave.2"),
        Output(@"Jabra Evolve2 65", usb, none, @"speaker.wave.2"),
        Output(@"Jabra Evolve2 65", usb, headphone, @"headphones"),
        // Studio monitors are speakers, not displays.
        Output(@"KRK Studio Monitor", usb, speaker, @"speaker.wave.2"),
        Output(@"SoundLink Flex", kAudioDeviceTransportTypeBluetoothLE, speaker, @"hifispeaker"),
        // The Headphones section decides over the transport too.
        Output(@"External Headphones", builtIn, headphone, @"headphones"),
        Output(@"krisp speaker", kAudioDeviceTransportTypeVirtual, headphone, @"headphones"),
        Output(@"MacBook Pro Speakers", builtIn, speaker, @"laptopcomputer"),
        Input(@"iMac Microphone", builtIn, @"desktopcomputer"),
        Output(@"Mac mini Speakers", builtIn, speaker, @"macmini"),
        Output(@"Mac Studio Speakers", builtIn, speaker, @"macstudio"),
        Output(@"Mac Pro Speakers", builtIn, speaker, @"macpro.gen3"),
        // The headphone jack is built in too, but it is not the Mac itself.
        Input(@"External Microphone", builtIn, @"mic"),
        // Only the Mac's own hardware gets its icon, not a device named after it.
        Output(@"MacBook Pro Speakers", kAudioDeviceTransportTypeVirtual, speaker, @"waveform"),
    ];
}

static NSArray<APBIconCase *> *AllCases(void) {
    return [RealDevices() arrayByAddingObjectsFromArray:Branches()];
}

@interface APBDeviceIconTests : XCTestCase
@end

@implementation APBDeviceIconTests

- (void)testHardwareIconMatchesTheDevice {
    for (APBIconCase *icon in AllCases()) {
        XCTAssertEqualObjects([icon.device hardwareIconForCategory:icon.category], icon.expected, @"%@", icon);
    }
}

- (void)testHardwareIconsListsEveryIconTheMenuBarMayShow {
    for (APBIconCase *icon in AllCases()) {
        XCTAssertTrue([APBAudioDevice.hardwareIcons containsObject:[icon.device menuBarIconForCategory:icon.category]],
                      @"%@", icon);
    }
}

- (void)testTheMenuBarShowsTheMacsOwnDevicesByRole {
    XCTAssertEqualObjects([Input(@"MacBook Air Microphone", builtIn, @"").device
                              menuBarIconForCategory:APBOutputCategoryNone],
                          @"mic");
    XCTAssertEqualObjects([Output(@"MacBook Air Speakers", builtIn, speaker, @"").device
                              menuBarIconForCategory:APBOutputCategorySpeaker],
                          APBGenericSpeakerIcon);
}

@end
