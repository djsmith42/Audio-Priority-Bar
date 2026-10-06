#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, APBStatusItemClickAction) {
    APBStatusItemClickActionTogglePanel,
    APBStatusItemClickActionShowMenu,
    APBStatusItemClickActionToggleMute,
};

@interface APBClickRouting : NSObject

+ (APBStatusItemClickAction)actionForEventType:(NSEventType)eventType modifiers:(NSEventModifierFlags)modifiers;
/// `suppressedAt` of nil never suppresses.
+ (BOOL)shouldSuppressOpenSuppressedAt:(nullable NSNumber *)suppressedAt now:(NSTimeInterval)now;

@end

@interface APBPanelPlacement : NSObject

/// Centers a window under the status item, kept 4 points inside the visible
/// part of the screen.
+ (NSPoint)originForButtonRect:(NSRect)buttonRect size:(NSSize)size visibleFrame:(NSRect)visible;

@end

@interface APBSettingsPlacement : NSObject

/// Where to move a window so it lands centered on a screen, or nil when it is
/// already on that screen and whatever the user did with it should be left
/// alone. Wraps an `NSPoint`.
+ (nullable NSValue *)originForWindow:(NSRect)frame screenFrame:(NSRect)screenFrame visibleFrame:(NSRect)visibleFrame;

@end

NS_ASSUME_NONNULL_END
