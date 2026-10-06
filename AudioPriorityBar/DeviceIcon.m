#import "DeviceIcon.h"
#import <CoreAudio/CoreAudio.h>

/// Checked in order, so "macbook" wins before any shorter Mac name.
static NSArray<NSArray<NSString *> *> *MacIcons(void) {
    return @[
        @[@"macbook", @"laptopcomputer"],
        @[@"imac", @"desktopcomputer"],
        @[@"mac mini", @"macmini"],
        @[@"mac studio", @"macstudio"],
        @[@"mac pro", @"macpro.gen3"],
    ];
}

static NSArray<NSString *> *CameraKeywords(void) {
    return @[@"camera", @"webcam", @"brio", @"c920", @"c922", @"kiyo", @"facecam", @"opal"];
}

/// Keywords for displays that use USB. `isDisplayOutput` covers HDMI and
/// DisplayPort. This list does not include "monitor" because studio monitors
/// are speakers.
static NSArray<NSString *> *DisplayKeywords(void) {
    return @[@"display", @"lg ultrafine"];
}

static BOOL ContainsAny(NSString *name, NSArray<NSString *> *keywords) {
    for (NSString *keyword in keywords) {
        if ([name containsString:keyword]) return YES;
    }
    return NO;
}

@implementation APBAudioDevice (DeviceIcon)

- (NSString *)hardwareIconForCategory:(APBOutputCategory)category {
    NSString *name = self.name.lowercaseString;

    if ([name containsString:@"airpods max"]) return @"airpodsmax";
    if ([name containsString:@"airpods pro"]) return @"airpodspro";
    if ([name containsString:@"airpods"]) return @"airpods";
    if (category == APBOutputCategoryHeadphone && [name containsString:@"beats"]) return @"beats.headphones";
    if ([name containsString:@"iphone"]) return @"iphone";
    if ([name containsString:@"ipad"]) return @"ipad";
    if (ContainsAny(name, CameraKeywords())) return @"web.camera";
    if (self.isDisplayOutput || ContainsAny(name, DisplayKeywords())) return @"display";

    if (category == APBOutputCategoryHeadphone) return @"headphones";

    switch (self.transportType) {
        case kAudioDeviceTransportTypeAirPlay:
            return @"airplayaudio";
        case kAudioDeviceTransportTypeContinuityCaptureWired:
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            return @"iphone";
        case kAudioDeviceTransportTypeVirtual:
        case kAudioDeviceTransportTypeAggregate:
        case kAudioDeviceTransportTypeAutoAggregate:
            return @"waveform";
        case kAudioDeviceTransportTypeBuiltIn:
            // macOS names the Mac's own mic and speakers after the model, like
            // "MacBook Air Microphone". A headphone jack device is also built
            // in but named "External", so it falls through to the role.
            for (NSArray<NSString *> *mac in MacIcons()) {
                if ([name containsString:mac[0]]) return mac[1];
            }
            return self.role == APBDeviceRoleInput ? @"mic" : APBAudioDevice.genericSpeakerIcon;
        default:
            break;
    }

    if (self.role == APBDeviceRoleInput) return @"mic";
    if (self.isBluetooth) return @"hifispeaker";
    return APBAudioDevice.genericSpeakerIcon;
}

- (BOOL)isBluetooth {
    return self.transportType == kAudioDeviceTransportTypeBluetooth
        || self.transportType == kAudioDeviceTransportTypeBluetoothLE;
}

- (NSString *)menuBarIconForCategory:(APBOutputCategory)category {
    NSString *icon = [self hardwareIconForCategory:category];
    for (NSArray<NSString *> *mac in MacIcons()) {
        if ([mac[1] isEqualToString:icon]) {
            return self.role == APBDeviceRoleInput ? @"mic" : APBAudioDevice.genericSpeakerIcon;
        }
    }
    return icon;
}

+ (NSString *)genericSpeakerIcon {
    return @"speaker.wave.2";
}

+ (NSArray<NSString *> *)hardwareIcons {
    return @[
        @"airpodsmax", @"airpodspro", @"airpods", @"beats.headphones", @"iphone",
        @"ipad", @"web.camera", @"display", @"airplayaudio", @"waveform", @"mic",
        @"headphones", @"hifispeaker", self.genericSpeakerIcon,
    ];
}

@end
