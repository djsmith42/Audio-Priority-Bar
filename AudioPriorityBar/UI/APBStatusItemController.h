#import <AppKit/AppKit.h>
#import "APBAppModel.h"
#import "APBServices.h"

NS_ASSUME_NONNULL_BEGIN

@class APBSettingsWindowController;

typedef NS_ENUM(NSInteger, APBStatusItemClickAction) {
    APBStatusItemClickActionTogglePanel,
    APBStatusItemClickActionShowMenu,
    APBStatusItemClickActionToggleMute,
};

@interface APBClickRouting : NSObject
+ (APBStatusItemClickAction)actionForEventType:(NSEventType)type modifiers:(NSEventModifierFlags)modifiers;
/// `suppressedAt` is negative for none.
+ (BOOL)shouldSuppressOpenSuppressedAt:(NSTimeInterval)suppressedAt now:(NSTimeInterval)now;
@end

@interface APBPanelPlacement : NSObject
/// Centers a window under the status item, kept 4 points inside the visible
/// part of the screen.
+ (NSPoint)originForButtonRect:(NSRect)buttonRect size:(NSSize)size visibleFrame:(NSRect)visible;
@end

/// Draws the menu bar icon, for the status item and the Settings preview.
@interface APBStatusLabel : NSObject
/// A template image for the menu bar, drawn at the screens' highest scale.
+ (NSImage *)imageForModel:(APBAppModel *)model;
@end

@interface APBStatusItemController : NSObject <NSWindowDelegate>
- (instancetype)initWithModel:(APBAppModel *)model
                     settings:(APBSettingsWindowController *)settings
                      updates:(APBUpdateChecker *)updates;
@end

NS_ASSUME_NONNULL_END
