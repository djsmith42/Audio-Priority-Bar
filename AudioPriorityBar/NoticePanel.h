#import <AppKit/AppKit.h>
#import "AppModel.h"
#import "NoticeContent.h"

NS_ASSUME_NONNULL_BEGIN

/// Where to put a window of a given size, or nil when there is nowhere.
typedef NSValue *_Nullable (^APBPlacement)(NSSize size);

/// A borderless window below the menu bar icon, used for the automatic switch
/// notice and the muted reminder. It is click-through except while showing
/// the reminder, which a click dismisses.
@interface APBNoticePanel : NSObject

@property (nonatomic, copy, nullable) void (^onDismissMutedReminder)(void);
@property (nonatomic) BOOL showsMutedReminder;
/// True while the panel is open, which already shows everything.
@property (nonatomic) BOOL isSuppressed;

- (instancetype)initWithPlacement:(APBPlacement)placement;
- (void)showSwitch:(APBNoticeContent *)content;

@end

/// A click-through window below the menu bar icon, shown while the pointer
/// rests on it, naming the current microphone and output.
@interface APBHoverPreviewPanel : NSObject

@property (nonatomic, readonly) BOOL isVisible;

- (instancetype)initWithModel:(APBAppModel *)model placement:(APBPlacement)placement;
- (void)show;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
