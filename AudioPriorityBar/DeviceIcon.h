#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBAudioDevice (DeviceIcon)

/// The SF Symbol for the kind of hardware, like the macOS Sound menu shows.
/// Names are checked before the transport type, since a webcam or display
/// usually connects over USB. `category` is the user's choice, so it decides
/// headphones over any guess from the name or transport.
- (NSString *)hardwareIconForCategory:(APBOutputCategory)category;

@property (nonatomic, readonly) BOOL isBluetooth;

/// The menu bar shows the Mac's own mic and speakers by role, so the two stay
/// apart when both are shown and the speaker keeps its volume level.
- (NSString *)menuBarIconForCategory:(APBOutputCategory)category;

/// Returned for an output with nothing more specific to show, so the volume
/// control can swap in its level-based speaker instead.
@property (class, nonatomic, readonly) NSString *genericSpeakerIcon;

/// Every symbol `menuBarIconForCategory:` can return, so the menu bar can
/// reserve room for the widest one.
@property (class, nonatomic, readonly) NSArray<NSString *> *hardwareIcons;

@end

NS_ASSUME_NONNULL_END
