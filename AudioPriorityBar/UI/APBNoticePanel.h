#import <AppKit/AppKit.h>
#import "APBAppModel.h"

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

- (instancetype)initWithLines:(NSArray<APBNoticeLine *> *)lines announcement:(NSString *)announcement NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (class, nonatomic, readonly) APBNoticeContent *mutedWhileRecording;

/// A switch notice wins for its moment, then the muted reminder returns if it
/// still applies. Nothing shows over the open panel.
+ (nullable APBNoticeContent *)currentWithSwitchNotice:(nullable APBNoticeContent *)switchNotice
                                    showsMutedReminder:(BOOL)showsMutedReminder
                                          isSuppressed:(BOOL)isSuppressed;

/// Describes one automatic switch, one line per device: its icon and name.
/// Both halves of a USB headset switching together read as one device rather
/// than two separate changes.
+ (APBNoticeContent *)switchedTo:(NSArray<APBAudioDevice *> *)devices icon:(NSString *(^)(APBAudioDevice *device))icon;

@end

/// Whether the muted reminder shows. Dismissing it hides it until it stops
/// applying, so the next recording while muted brings it back.
@interface APBMutedReminderState : NSObject
@property (nonatomic, readonly) BOOL isDismissed;
- (BOOL)updateApplies:(BOOL)applies;
- (void)dismiss;
@end

/// A borderless window below the menu bar icon, used for the automatic switch
/// notice and the muted reminder. It is click-through except while showing
/// the reminder, which a click dismisses.
@interface APBNoticePanel : NSObject

@property (nonatomic, copy, nullable) dispatch_block_t onDismissMutedReminder;
@property (nonatomic) BOOL showsMutedReminder;
/// YES while the panel is open, which already shows everything.
@property (nonatomic) BOOL isSuppressed;

- (instancetype)initWithPlacement:(NSValue *_Nullable (^)(NSSize size))placement;
- (void)showSwitch:(APBNoticeContent *)content;

@end

/// A click-through window below the menu bar icon, shown while the pointer
/// rests on it, naming the current microphone and output.
@interface APBHoverPreviewPanel : NSObject
@property (nonatomic, readonly) BOOL isVisible;
- (instancetype)initWithModel:(APBAppModel *)model placement:(NSValue *_Nullable (^)(NSSize size))placement;
- (void)show;
- (void)hide;
/// Follows the content, such as a device being renamed or muted while the
/// preview is up.
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
