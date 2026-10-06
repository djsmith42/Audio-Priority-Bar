#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

/// Forwards CoreAudio's device, default and mute or volume changes to the
/// main thread.
@interface APBCoreAudioObserver : NSObject

@property (nonatomic, copy, nullable) void (^onDevicesChanged)(void);
@property (nonatomic, copy, nullable) void (^onDefaultChanged)(APBDeviceRole role);
@property (nonatomic, copy, nullable) void (^onMuteOrVolumeChanged)(void);

- (BOOL)startListening;
- (void)stopListening;

@end

NS_ASSUME_NONNULL_END
