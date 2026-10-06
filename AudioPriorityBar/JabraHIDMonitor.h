#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Tracks whether a headset is actually connected to each attached Jabra
/// dongle.
///
/// The dongle's telephony link bit cannot carry this on its own: about 1.8s
/// after USB enumeration the dongle asserts a false "linked", identically
/// whether a headset is on or off, and never corrects it. The authoritative
/// answer comes from asking the dongle over its GNP management channel. The
/// legacy bit is kept for two narrower jobs: a fallback for devices that do
/// not answer GNP, and a cheap trigger telling us a real transition happened
/// and it is worth re-querying.
@interface APBJabraHIDMonitor : NSObject

@property (nonatomic, copy, nullable) void (^onLinkChange)(void);
@property (nonatomic, copy, nullable) void (^onBatteryChange)(void);

- (void)start;
/// Stops every producer before returning, so no callback, timeout or
/// debounce can fire afterwards.
- (void)stop;

- (APBLinkState)linkStateForDevice:(APBAudioDevice *)device;
- (BOOL)isUsable:(APBAudioDevice *)device;
/// `APBLinkStateNone` for a device no dongle monitors.
- (APBLinkState)monitoredStateForDevice:(APBAudioDevice *)device;
- (nullable NSNumber *)batteryLevelForDevice:(APBAudioDevice *)device;

@end

NS_ASSUME_NONNULL_END
