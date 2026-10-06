#import "UIHelpers.h"
#import <QuartzCore/QuartzCore.h>

const CGFloat APBCaptionSize = 10;
const CGFloat APBCalloutSize = 12;
const CGFloat APBBodySize = 13;

NSImage *APBSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                                                weight:weight];
    return [image imageWithSymbolConfiguration:configuration];
}

NSString *APBFilledSymbolName(NSString *name) {
    NSString *fill = [name stringByAppendingString:@".fill"];
    return [NSImage imageWithSystemSymbolName:fill accessibilityDescription:nil] ? fill : name;
}

NSColor *APBPrimary(CGFloat opacity) {
    return [NSColor.labelColor colorWithAlphaComponent:opacity];
}

BOOL APBReduceMotion(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

NSTextField *APBLabel(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    label.cell.truncatesLastVisibleLine = YES;
    return label;
}

void APBAnimate(NSTimeInterval duration, void (^changes)(void)) {
    if (APBReduceMotion()) {
        changes();
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        context.allowsImplicitAnimation = YES;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        changes();
    }];
}

void APBAddArranged(NSStackView *stack, NSView *view, CGFloat width) {
    [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
}

/// A clip shape alone leaves the behind-window blur square at the corners.
static NSImage *RoundedMask(CGFloat radius) {
    CGFloat edge = radius * 2 + 1;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    image.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

@implementation APBPanelBackgroundView

+ (CGFloat)cornerRadius {
    return 12;
}

- (instancetype)initWithContent:(NSView *)content {
    if ((self = [super initWithFrame:NSZeroRect])) {
        CGFloat radius = APBPanelBackgroundView.cornerRadius;
        self.wantsLayer = YES;
        self.layer.cornerRadius = radius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        content.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *background = nil;
        if (@available(macOS 26, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] init];
            glass.cornerRadius = radius;
            glass.contentView = content;
            background = glass;
        } else {
            NSVisualEffectView *material = [[NSVisualEffectView alloc] init];
            material.material = NSVisualEffectMaterialMenu;
            material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            // The app remains inactive when this nonactivating panel becomes
            // key, so following the window state would render the material
            // as inactive.
            material.state = NSVisualEffectStateActive;
            material.maskImage = RoundedMask(radius);
            [material addSubview:content];
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:material.leadingAnchor],
                [content.trailingAnchor constraintEqualToAnchor:material.trailingAnchor],
                [content.topAnchor constraintEqualToAnchor:material.topAnchor],
                [content.bottomAnchor constraintEqualToAnchor:material.bottomAnchor],
            ]];
            APBFillView *stroke = [[APBFillView alloc] init];
            stroke.strokeColor = APBPrimary(0.12);
            stroke.cornerRadius = radius;
            stroke.translatesAutoresizingMaskIntoConstraints = NO;
            [material addSubview:stroke positioned:NSWindowAbove relativeTo:content];
            [NSLayoutConstraint activateConstraints:@[
                [stroke.leadingAnchor constraintEqualToAnchor:material.leadingAnchor],
                [stroke.trailingAnchor constraintEqualToAnchor:material.trailingAnchor],
                [stroke.topAnchor constraintEqualToAnchor:material.topAnchor],
                [stroke.bottomAnchor constraintEqualToAnchor:material.bottomAnchor],
            ]];
            background = material;
        }
        background.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:background];
        [NSLayoutConstraint activateConstraints:@[
            [background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [background.topAnchor constraintEqualToAnchor:self.topAnchor],
            [background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

@end

@implementation APBFillView

- (void)setFillColor:(NSColor *)fillColor {
    _fillColor = fillColor;
    self.needsDisplay = YES;
}

- (void)setStrokeColor:(NSColor *)strokeColor {
    _strokeColor = strokeColor;
    self.needsDisplay = YES;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.needsDisplay = YES;
}

- (void)setIsCapsule:(BOOL)isCapsule {
    _isCapsule = isCapsule;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat radius = _isCapsule ? NSHeight(self.bounds) / 2 : _cornerRadius;
    if (_fillColor) {
        [_fillColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
    }
    if (_strokeColor) {
        NSRect inset = NSInsetRect(self.bounds, 0.5, 0.5);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:inset xRadius:radius - 0.5 yRadius:radius - 0.5];
        path.lineWidth = 1;
        [_strokeColor setStroke];
        [path stroke];
    }
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    // A pure decoration passes clicks through to whatever is underneath.
    return hit == self && self.class == APBFillView.class ? nil : hit;
}

@end

@implementation APBHoverRowView {
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.cornerRadius = 6;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setHovering:(BOOL)hovering {
    if (_isHovering == hovering) return;
    _isHovering = hovering;
    APBAnimate(0.12, ^{
        self.fillColor = hovering ? APBPrimary(0.1) : nil;
    });
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self setHovering:NO];
}

- (void)mouseDown:(NSEvent *)event {
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, self.bounds) && _action) _action();
}

@end

@implementation APBSeparatorView

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, 1);
}

- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.separatorColor setFill];
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    NSRectFill(NSMakeRect(0, 0, NSWidth(self.bounds), 1 / scale));
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

@end

@implementation APBTrackingView {
    NSTrackingArea *_trackingArea;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setHovering:(BOOL)hovering {
    if (_isHovering == hovering) return;
    _isHovering = hovering;
    if (_onHover) _onHover(hovering);
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self setHovering:NO];
}

@end
