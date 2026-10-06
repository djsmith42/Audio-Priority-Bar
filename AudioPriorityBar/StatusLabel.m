#import "StatusLabel.h"
#import "DeviceIcon.h"
#import "UIHelpers.h"

/// The 13-point menu bar font draws glyphs smaller than the system's own menu
/// extras, such as Sound and Wi-Fi.
static const CGFloat GlyphSize = 14;
static const CGFloat Spacing = 2;

/// One item in the row: its size and how to draw it centered in a rect.
@interface APBLabelSlot : NSObject
@property (nonatomic) NSSize size;
@property (nonatomic, copy) void (^draw)(NSRect rect);
@end

@implementation APBLabelSlot
@end

static NSImage *Glyph(NSString *name, NSNumber *variableValue) {
    NSImage *image = variableValue
        ? [NSImage imageWithSystemSymbolName:name variableValue:variableValue.doubleValue accessibilityDescription:nil]
        : [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:GlyphSize
                                                                                                weight:NSFontWeightRegular];
    return [image imageWithSymbolConfiguration:configuration];
}

static NSSize MaximumSize(NSArray<NSString *> *names) {
    NSSize size = NSZeroSize;
    for (NSString *name in names) {
        NSSize glyph = Glyph(name, nil).size;
        size = NSMakeSize(MAX(size.width, glyph.width), MAX(size.height, glyph.height));
    }
    return size;
}

static NSRect Centered(NSSize size, NSRect rect) {
    return NSMakeRect(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2, size.width, size.height);
}

/// A glyph, centered in room reserved for the widest of `reserved`, so the
/// item keeps its width instead of resizing as the device changes. A nil
/// name reserves the room and draws nothing.
static APBLabelSlot *GlyphSlot(NSString *name, NSNumber *variableValue, CGFloat opacity, NSArray<NSString *> *reserved) {
    NSImage *image = name ? Glyph(name, variableValue) : nil;
    APBLabelSlot *slot = [[APBLabelSlot alloc] init];
    NSSize size = reserved ? MaximumSize(reserved) : NSZeroSize;
    if (image) size = NSMakeSize(MAX(size.width, image.size.width), MAX(size.height, image.size.height));
    slot.size = size;
    slot.draw = ^(NSRect rect) {
        [image drawInRect:Centered(image.size, rect) fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver fraction:opacity];
    };
    return slot;
}

/// Text with the 4-point leading padding the labeled icon gives it.
static APBLabelSlot *TextSlot(NSString *text) {
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:GlyphSize],
        NSForegroundColorAttributeName: NSColor.blackColor,
    }];
    NSSize textSize = string.size;
    APBLabelSlot *slot = [[APBLabelSlot alloc] init];
    slot.size = NSMakeSize(ceil(textSize.width) + 4, ceil(textSize.height));
    slot.draw = ^(NSRect rect) {
        NSRect text = NSMakeRect(NSMinX(rect) + 4, NSMidY(rect) - textSize.height / 2, textSize.width, textSize.height);
        [string drawInRect:text];
    };
    return slot;
}

@implementation APBStatusLabel

+ (NSArray<NSString *> *)reservedInputIcons {
    NSMutableArray *icons = [NSMutableArray array];
    for (NSString *name in [APBAudioDevice.hardwareIcons arrayByAddingObject:@"mic.slash"]) {
        [icons addObject:APBFilledSymbolName(name)];
    }
    return icons;
}

+ (NSArray<NSString *> *)reservedOutputIcons {
    NSMutableArray *icons = [NSMutableArray array];
    NSArray *names = [APBAudioDevice.hardwareIcons arrayByAddingObjectsFromArray:@[@"speaker.wave.3", @"speaker.slash"]];
    for (NSString *name in names) [icons addObject:APBFilledSymbolName(name)];
    return icons;
}

/// The current output's hardware icon, or nil for a generic speaker, which
/// shows the volume level instead. Falls back to the category while no
/// output is known.
+ (NSString *)hardwareIconForModel:(APBAppModel *)model {
    APBAudioDevice *output = model.currentOutputDevice;
    NSString *icon = output
        ? [output menuBarIconForCategory:model.activeOutputCategory]
        : (model.activeOutputCategory == APBOutputCategoryHeadphone ? @"headphones" : nil);
    return [icon isEqualToString:APBAudioDevice.genericSpeakerIcon] ? nil : icon;
}

+ (NSImage *)imageForModel:(APBAppModel *)model {
    BOOL reduceMotion = APBReduceMotion();
    CGFloat mutedOpacity = reduceMotion || model.micFlashState ? 1 : 0.45;
    BOOL isLabeled = model.menuBarDevices == APBMenuBarDevicesBothLabeled;
    NSString *hardwareIcon = [self hardwareIconForModel:model];
    NSMutableArray<APBLabelSlot *> *slots = [NSMutableArray array];

    if (model.menuBarDevices != APBMenuBarDevicesOutputOnly) {
        if (isLabeled) [slots addObject:TextSlot(@"in:")];
        NSString *inputIcon = [model.currentInputDevice menuBarIconForCategory:APBOutputCategoryNone] ?: @"mic";
        [slots addObject:model.isActiveInputMuted
            ? GlyphSlot(@"mic.slash.fill", nil, mutedOpacity, self.reservedInputIcons)
            : GlyphSlot(APBFilledSymbolName(inputIcon), nil, 1, self.reservedInputIcons)];
        if (isLabeled) [slots addObject:TextSlot(@"out:")];
    } else if (model.isActiveInputMuted) {
        [slots addObject:GlyphSlot(@"mic.slash.fill", nil, mutedOpacity, nil)];
    }

    NSString *output = nil;
    NSNumber *level = nil;
    if (model.isActiveOutputMuted) {
        output = @"speaker.slash.fill";
    } else if (hardwareIcon) {
        output = APBFilledSymbolName(hardwareIcon);
    } else {
        output = @"speaker.wave.3.fill";
        if (model.isVolumeControllable) level = @(model.volume);
    }
    [slots addObject:GlyphSlot(output, level, 1, self.reservedOutputIcons)];

    // Only beside hardware glyphs, which have no waves of their own. Kept
    // while muted so muting does not change the width.
    if (model.showsMenuBarVolume && hardwareIcon) {
        BOOL showsLevel = !model.isActiveOutputMuted && model.isVolumeControllable;
        [slots addObject:GlyphSlot(showsLevel ? @"wave.3.right" : nil, showsLevel ? @(model.volume) : nil, 1,
                                   @[@"wave.3.right"])];
    }

    // Beside the audio glyph rather than replacing it: that glyph still
    // identifies the app and the active category, while this one flags the
    // exceptional state. Monochrome like the rest, since colored menu bar
    // icons fight light and dark contrast.
    if (model.isActiveOutputLinkDown) {
        [slots addObject:GlyphSlot(@"exclamationmark.triangle.fill", nil, 1, nil)];
    }

    CGFloat contentWidth = 0, contentHeight = 0;
    for (APBLabelSlot *slot in slots) {
        contentWidth += slot.size.width;
        contentHeight = MAX(contentHeight, slot.size.height);
    }
    contentWidth += Spacing * (CGFloat)MAX((NSInteger)slots.count - 1, 0);
    BOOL outlined = model.outlinesMenuBarIcon;
    CGFloat horizontalPadding = outlined ? 4 : 0, verticalPadding = outlined ? 2 : 0;
    // Whole points only: a fractional width lands on half pixels and draws
    // some edges softer than others.
    NSSize outline = NSMakeSize(ceil(contentWidth + horizontalPadding * 2), ceil(contentHeight + verticalPadding * 2));
    NSSize size = NSMakeSize(outline.width + 2, outline.height);

    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        CGFloat x = 1 + (outline.width - contentWidth) / 2;
        for (APBLabelSlot *slot in slots) {
            slot.draw(NSMakeRect(x, (bounds.size.height - contentHeight) / 2, slot.size.width, contentHeight));
            x += slot.size.width + Spacing;
        }
        if (outlined) {
            NSRect border = NSInsetRect(NSMakeRect(1, 0, outline.width, outline.height), 0.5, 0.5);
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:border xRadius:3.5 yRadius:3.5];
            path.lineWidth = 1;
            [NSColor.blackColor setStroke];
            [path stroke];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

@end
