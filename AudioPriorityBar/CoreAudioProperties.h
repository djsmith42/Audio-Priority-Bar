#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBCoreAudioProperties : NSObject

+ (NSArray<APBAudioDevice *> *)devices;
+ (NSArray<NSNumber *> *)deviceIDs;
/// Zero when there is none.
+ (AudioObjectID)defaultDevice:(APBDeviceRole)role;
+ (BOOL)setDefault:(AudioObjectID)deviceID role:(APBDeviceRole)role;
/// Nil when the current output has no volume.
+ (nullable NSNumber *)outputVolume;
+ (BOOL)setOutputVolume:(float)value;
+ (float)deviceVolume:(AudioObjectID)deviceID;
+ (BOOL)isMuted:(AudioObjectID)deviceID role:(APBDeviceRole)role;
/// Sets the mute property, trying the main element before channel 1. NO
/// when the device has no settable mute, so the caller can fall back to zero
/// input volume.
+ (BOOL)setMute:(AudioObjectID)deviceID role:(APBDeviceRole)role muted:(BOOL)muted;
+ (nullable NSNumber *)inputVolume:(AudioObjectID)deviceID;
+ (BOOL)setInputVolume:(AudioObjectID)deviceID value:(float)value;
/// Whether the mute property can be set, on the main element or channel 1,
/// matching where `setMute` writes it.
+ (BOOL)canSetMute:(AudioObjectID)deviceID role:(APBDeviceRole)role;
/// Whether any process is using the device, which for a microphone means
/// some app is recording from it.
+ (BOOL)isRunningSomewhere:(AudioObjectID)deviceID;

/// macOS gives a Bluetooth output a headphones terminal even when it is a
/// speaker, such as an Echo, so from Bluetooth that claim is no evidence.
+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals transport:(UInt32)transport;
/// Resolves what a device's streams collectively claim. Streams that
/// disagree are no evidence at all, since preferring one by position would
/// only make stream order look meaningful.
+ (APBOutputCategory)categoryForTerminals:(NSArray<NSNumber *> *)terminals;
/// Maps an audio terminal to a category.
///
/// Two value spaces appear in practice. USB and Bluetooth devices arrive
/// translated into the CoreAudio constants, while built-in devices report the
/// raw code from the USB Audio Terminal Types specification, so both are
/// accepted. Anything unrecognised, including `Unknown`, line level and
/// digital interfaces, declares nothing.
+ (APBOutputCategory)categoryForTerminal:(UInt32)terminal;

/// Sound reaching a monitor or TV over the video cable. The transport says so
/// outright, which a product name cannot: both of the attached Dell panels
/// report HDMI, including the one behind a USB-C hub.
+ (BOOL)isDisplayTransport:(UInt32)transport;

@end

NS_ASSUME_NONNULL_END
