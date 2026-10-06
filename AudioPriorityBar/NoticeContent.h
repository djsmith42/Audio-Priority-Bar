#import <Foundation/Foundation.h>
#import "AudioPriorityCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBNoticeLine : NSObject

@property (nonatomic, readonly, copy) NSString *icon;
@property (nonatomic, readonly, copy) NSString *text;

+ (instancetype)lineWithIcon:(NSString *)icon text:(NSString *)text;

@end

/// What the floating notice under the menu bar icon shows.
@interface APBNoticeContent : NSObject

@property (nonatomic, readonly, copy) NSArray<APBNoticeLine *> *lines;
/// What VoiceOver reads, which names each device's role since the icons only
/// show it visually.
@property (nonatomic, readonly, copy) NSString *announcement;

- (instancetype)initWithLines:(NSArray<APBNoticeLine *> *)lines announcement:(NSString *)announcement;

@property (class, nonatomic, readonly) APBNoticeContent *mutedWhileRecording;

/// A switch notice wins for its moment, then the muted reminder returns if
/// it still applies. Nothing shows over the open panel.
+ (nullable APBNoticeContent *)currentWithSwitchNotice:(nullable APBNoticeContent *)switchNotice
                                    showsMutedReminder:(BOOL)showsMutedReminder
                                          isSuppressed:(BOOL)isSuppressed;

/// Describes one automatic switch, one line per device: its icon and name.
/// Both halves of a USB headset switching together read as one device rather
/// than two separate changes.
+ (APBNoticeContent *)switchedTo:(NSArray<APBAudioDevice *> *)devices
                            icon:(NSString *(^)(APBAudioDevice *device))icon;

@end

/// Whether the muted reminder shows. Dismissing it hides it until it stops
/// applying, so the next recording while muted brings it back.
@interface APBMutedReminderState : NSObject

@property (nonatomic, readonly) BOOL isDismissed;

- (BOOL)updateApplies:(BOOL)applies;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
