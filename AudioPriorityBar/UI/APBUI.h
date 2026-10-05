#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

/// An SF Symbol at a point size and weight, or nil when the system lacks it.
FOUNDATION_EXPORT NSImage *_Nullable APBSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight);
/// A variable SF Symbol, such as a speaker whose waves fill with the volume.
FOUNDATION_EXPORT NSImage *_Nullable APBVariableSymbol(NSString *name, double value, CGFloat pointSize, NSFontWeight weight);
/// A symbol drawn in one color, for text attachments and layers that cannot
/// tint.
FOUNDATION_EXPORT NSImage *_Nullable APBColoredSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight, NSColor *color);

/// A non-editable, non-selectable, single-line label.
FOUNDATION_EXPORT NSTextField *APBLabel(NSString *text, NSFont *font, NSColor *color);
/// A label that wraps to as many lines as `maximumLines` allows, zero for any.
FOUNDATION_EXPORT NSTextField *APBWrappingLabel(NSString *text, NSFont *font, NSColor *color, NSInteger maximumLines);

/// The text color at an opacity, like SwiftUI's `Color.primary.opacity`.
FOUNDATION_EXPORT NSColor *APBPrimary(CGFloat opacity);

FOUNDATION_EXPORT BOOL APBReduceMotion(void);

/// A view that fills a rounded shape, resolving dynamic colors for its own
/// appearance so light and dark mode both stay right.
@interface APBFillView : NSView
@property (nonatomic, copy, nullable) NSColor *fillColor;
@property (nonatomic, copy, nullable) NSColor *borderColor;
@property (nonatomic) CGFloat borderWidth;
@property (nonatomic) CGFloat cornerRadius;
/// Rounds to half the shorter side, whatever the size.
@property (nonatomic) BOOL isCapsule;
@end

/// Reports the pointer entering and leaving, even while the app is inactive,
/// as a nonactivating panel always leaves it.
@interface APBHoverView : APBFillView
@property (nonatomic, readonly) BOOL isHovering;
@property (nonatomic, copy, nullable) void (^onHover)(BOOL hovering);
/// Called for a click that ends inside the view.
@property (nonatomic, copy, nullable) dispatch_block_t onClick;
@end

/// A thin horizontal line, like SwiftUI's `Divider`.
@interface APBSeparator : NSBox
+ (instancetype)separator;
@end

/// Matches the menu bar's own menus: Liquid Glass on macOS 26 and later, and
/// the menu material blurred over whatever is behind the panel before that.
/// Holds the panel's content and sizes to it.
@interface APBPanelBackgroundView : NSView
- (instancetype)initWithContent:(NSView *)content;
@end

/// A read-only volume meter, dimmed while muted like the panel's slider.
/// Drawn in the text color with no thumb or value, so it does not read as a
/// slider to drag.
@interface APBLevelBar : NSView
@property (nonatomic) float level;
@property (nonatomic) BOOL isMuted;
@end

/// A behind-window blur clipped to a capsule or rounded rectangle.
@interface APBMaterialView : NSVisualEffectView
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL isCapsule;
@end

NS_ASSUME_NONNULL_END
