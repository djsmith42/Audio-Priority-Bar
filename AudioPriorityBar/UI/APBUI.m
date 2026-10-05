#import "APBUI.h"

NSImage *APBSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

NSImage *APBVariableSymbol(NSString *name, double value, CGFloat pointSize, NSFontWeight weight) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name variableValue:value accessibilityDescription:nil];
    return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

NSImage *APBColoredSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight, NSColor *color) {
    NSImageSymbolConfiguration *configuration = [[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[ color ]]];
    return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:configuration];
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

NSTextField *APBWrappingLabel(NSString *text, NSFont *font, NSColor *color, NSInteger maximumLines) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = font;
    label.textColor = color;
    label.maximumNumberOfLines = maximumLines;
    label.cell.truncatesLastVisibleLine = YES;
    label.selectable = NO;
    return label;
}

NSColor *APBPrimary(CGFloat opacity) {
    return [NSColor.textColor colorWithAlphaComponent:opacity];
}

BOOL APBReduceMotion(void) {
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

@implementation APBFillView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) self.wantsLayer = YES;
    return self;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    // Resolved against this view's appearance, so dynamic colors follow
    // light and dark mode.
    __block CGColorRef fill = NULL, border = NULL;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        fill = self->_fillColor.CGColor;
        border = self->_borderColor.CGColor;
    }];
    self.layer.backgroundColor = fill;
    self.layer.borderColor = border;
    self.layer.borderWidth = _borderColor ? _borderWidth : 0;
    self.layer.cornerRadius = _isCapsule ? MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2 : _cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (_isCapsule) self.needsDisplay = YES;
}

- (void)layout {
    [super layout];
    // Auto Layout sizes the view after its colors are set, so the capsule's
    // radius is only known now.
    if (_isCapsule) [self updateLayer];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)setFillColor:(NSColor *)fillColor {
    if (fillColor == _fillColor || [fillColor isEqual:_fillColor]) return;
    _fillColor = [fillColor copy];
    self.needsDisplay = YES;
}

- (void)setBorderColor:(NSColor *)borderColor {
    _borderColor = [borderColor copy];
    self.needsDisplay = YES;
}

- (void)setBorderWidth:(CGFloat)borderWidth {
    _borderWidth = borderWidth;
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

@end

@implementation APBHoverView {
    NSTrackingArea *_trackingArea;
    BOOL _isPressed;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
    // A view moved under a resting pointer gets no entered event.
    if (self.window) {
        NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
        [self setHovering:NSPointInRect(point, self.bounds) && !self.isHiddenOrHasHiddenAncestor];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) [self setHovering:NO];
}

- (void)mouseEntered:(NSEvent *)event {
    [self setHovering:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHovering:NO];
}

- (void)setHovering:(BOOL)hovering {
    if (hovering == _isHovering) return;
    _isHovering = hovering;
    if (_onHover) _onHover(hovering);
}

- (void)mouseDown:(NSEvent *)event {
    if (!_onClick) {
        [super mouseDown:event];
        return;
    }
    _isPressed = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (!_onClick) {
        [super mouseUp:event];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_isPressed && NSPointInRect(point, self.bounds)) _onClick();
    _isPressed = NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

@end

@implementation APBSeparator

+ (instancetype)separator {
    APBSeparator *separator = [[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 1)];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    return separator;
}

@end

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

@implementation APBMaterialView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        self.material = NSVisualEffectMaterialPopover;
        // The app stays inactive while its nonactivating panels show, so
        // following the window state would render the material as inactive.
        self.state = NSVisualEffectStateActive;
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self updateMask];
}

- (void)setIsCapsule:(BOOL)isCapsule {
    _isCapsule = isCapsule;
    [self updateMask];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (_isCapsule) [self updateMask];
}

- (void)updateMask {
    CGFloat radius = _isCapsule ? floor(MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2) : _cornerRadius;
    self.maskImage = radius > 0 ? RoundedMask(radius) : nil;
}

@end

static const CGFloat PanelCornerRadius = 12;

@implementation APBPanelBackgroundView

- (instancetype)initWithContent:(NSView *)content {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        content.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *container;
        if (@available(macOS 26, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] init];
            glass.cornerRadius = PanelCornerRadius;
            glass.style = NSGlassEffectViewStyleRegular;
            glass.contentView = content;
            container = glass;
        } else {
            APBMaterialView *material = [[APBMaterialView alloc] init];
            material.material = NSVisualEffectMaterialMenu;
            material.cornerRadius = PanelCornerRadius;
            [material addSubview:content];
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:material.leadingAnchor],
                [content.trailingAnchor constraintEqualToAnchor:material.trailingAnchor],
                [content.topAnchor constraintEqualToAnchor:material.topAnchor],
                [content.bottomAnchor constraintEqualToAnchor:material.bottomAnchor],
            ]];
            APBFillView *stroke = [[APBFillView alloc] init];
            stroke.translatesAutoresizingMaskIntoConstraints = NO;
            stroke.borderColor = APBPrimary(0.12);
            stroke.borderWidth = 1;
            stroke.cornerRadius = PanelCornerRadius;
            [material addSubview:stroke];
            [NSLayoutConstraint activateConstraints:@[
                [stroke.leadingAnchor constraintEqualToAnchor:material.leadingAnchor],
                [stroke.trailingAnchor constraintEqualToAnchor:material.trailingAnchor],
                [stroke.topAnchor constraintEqualToAnchor:material.topAnchor],
                [stroke.bottomAnchor constraintEqualToAnchor:material.bottomAnchor],
            ]];
            container = material;
        }
        container.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:container];
        [NSLayoutConstraint activateConstraints:@[
            [container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [container.topAnchor constraintEqualToAnchor:self.topAnchor],
            [container.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        // Liquid Glass leaves the window square to the shadow, which draws a
        // rectangle around the rounded panel.
        self.wantsLayer = YES;
        self.layer.cornerRadius = PanelCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
    }
    return self;
}

@end

@implementation APBLevelBar

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:120],
            [self.heightAnchor constraintEqualToConstant:4],
        ]];
    }
    return self;
}

- (void)setLevel:(float)level {
    _level = level;
    self.needsDisplay = YES;
}

- (void)setIsMuted:(BOOL)isMuted {
    _isMuted = isMuted;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat radius = NSHeight(bounds) / 2;
    CGFloat opacity = _isMuted ? 0.5 : 1;
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    [APBPrimary(0.1 * opacity) setFill];
    [track fill];
    [NSGraphicsContext saveGraphicsState];
    [track addClip];
    NSRect fill = bounds;
    fill.size.width = NSWidth(bounds) * MAX(0, MIN(1, _level));
    [APBPrimary(opacity) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:radius yRadius:radius] fill];
    [NSGraphicsContext restoreGraphicsState];
}

@end
