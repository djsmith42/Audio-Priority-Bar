#import "StatusItemRouting.h"

static const NSTimeInterval SuppressionLifetime = 2;

@implementation APBClickRouting

+ (APBStatusItemClickAction)actionForEventType:(NSEventType)eventType modifiers:(NSEventModifierFlags)modifiers {
    if (eventType == NSEventTypeRightMouseUp
        || (eventType == NSEventTypeLeftMouseUp && (modifiers & NSEventModifierFlagControl))) {
        return APBStatusItemClickActionShowMenu;
    }
    if (eventType == NSEventTypeLeftMouseUp && (modifiers & NSEventModifierFlagOption)) {
        return APBStatusItemClickActionToggleMute;
    }
    return APBStatusItemClickActionTogglePanel;
}

+ (BOOL)shouldSuppressOpenSuppressedAt:(NSNumber *)suppressedAt now:(NSTimeInterval)now {
    if (!suppressedAt) return NO;
    return now - suppressedAt.doubleValue < SuppressionLifetime;
}

@end

@implementation APBPanelPlacement

+ (NSPoint)originForButtonRect:(NSRect)buttonRect size:(NSSize)size visibleFrame:(NSRect)visible {
    CGFloat maxX = MAX(NSMaxX(visible) - size.width - 4, NSMinX(visible) + 4);
    CGFloat x = MIN(MAX(NSMidX(buttonRect) - size.width / 2, NSMinX(visible) + 4), maxX);
    CGFloat y = MAX(NSMinY(buttonRect) - size.height - 4, NSMinY(visible) + 4);
    return NSMakePoint(x, y);
}

@end

@implementation APBSettingsPlacement

+ (NSValue *)originForWindow:(NSRect)frame screenFrame:(NSRect)screenFrame visibleFrame:(NSRect)visibleFrame {
    NSPoint center = NSMakePoint(NSMidX(frame), NSMidY(frame));
    if (NSPointInRect(center, screenFrame)) return nil;
    return [NSValue valueWithPoint:NSMakePoint(NSMidX(visibleFrame) - frame.size.width / 2,
                                               NSMidY(visibleFrame) - frame.size.height / 2)];
}

@end
