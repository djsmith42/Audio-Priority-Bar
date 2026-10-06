#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// An SF Symbol at a point size and weight, or nil when the system lacks it.
FOUNDATION_EXPORT NSImage *_Nullable APBSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight);
/// The ".fill" variant when the system has one. The menu bar uses filled
/// glyphs; not every hardware symbol has one.
FOUNDATION_EXPORT NSString *APBFilledSymbolName(NSString *name);
/// The label color at an opacity, like SwiftUI's `Color.primary.opacity(_:)`.
FOUNDATION_EXPORT NSColor *APBPrimary(CGFloat opacity);
/// Whether the user asked for less motion.
FOUNDATION_EXPORT BOOL APBReduceMotion(void);
/// A one-line label that truncates at its end.
FOUNDATION_EXPORT NSTextField *APBLabel(NSString *text, NSFont *font, NSColor *color);
/// Runs `changes` animated with an ease-in-out curve, or at once when the
/// user asked for less motion.
FOUNDATION_EXPORT void APBAnimate(NSTimeInterval duration, void (^changes)(void));

/// Adds `view` to a vertical stack at a fixed width. A width on the view
/// itself survives the stack detaching it while hidden, which constraints
/// to the stack would not.
FOUNDATION_EXPORT void APBAddArranged(NSStackView *stack, NSView *view, CGFloat width);

/// The macOS system font sizes SwiftUI's text styles use.
FOUNDATION_EXPORT const CGFloat APBCaptionSize;
FOUNDATION_EXPORT const CGFloat APBCalloutSize;
FOUNDATION_EXPORT const CGFloat APBBodySize;

/// Hosts content on the menu bar's own background: Liquid Glass on macOS 26
/// and later, and the menu material blurred over whatever is behind the
/// window before that, clipped to rounded corners.
@interface APBPanelBackgroundView : NSView

@property (class, nonatomic, readonly) CGFloat cornerRadius;

- (instancetype)initWithContent:(NSView *)content;

@end

/// A rounded rectangle filled with a dynamic color, redrawn when the
/// appearance changes.
@interface APBFillView : NSView

@property (nonatomic, nullable) NSColor *fillColor;
@property (nonatomic, nullable) NSColor *strokeColor;
@property (nonatomic) CGFloat cornerRadius;
/// A capsule, whatever the height.
@property (nonatomic) BOOL isCapsule;

@end

/// A full-width row that highlights while the pointer is over it and runs
/// `action` when clicked anywhere a subview does not handle.
@interface APBHoverRowView : APBFillView

@property (nonatomic, copy, nullable) void (^action)(void);
@property (nonatomic, readonly) BOOL isHovering;

@end

/// A thin horizontal line in the separator color.
@interface APBSeparatorView : NSView
@end

/// Calls a block when the pointer enters or leaves, for views that track
/// hover without subclassing.
@interface APBTrackingView : NSView

@property (nonatomic, copy, nullable) void (^onHover)(BOOL hovering);
@property (nonatomic, readonly) BOOL isHovering;

@end

NS_ASSUME_NONNULL_END
