#import "APBTestSupport.h"
#import <QuartzCore/QuartzCore.h>
#import "APBDeviceRowView.h"
#import "APBPanelView.h"

/// Drives a real drag through the panel with synthesized mouse events, the
/// way the window delivers them.
@interface APBPanelDragTests : XCTestCase
@end

@implementation APBPanelDragTests {
    APBFakeAudio *_audio;
    APBAppModel *_model;
    APBPanelView *_panel;
    NSWindow *_window;
}

- (void)setUp {
    _audio = [[APBFakeAudio alloc] init];
    _audio.catalog = @[
        APBOutput(1, @"speaker", @"PowerConf"),
        APBInput(2, @"scarlett", @"Scarlett 2i2 USB"),
        APBInput(3, @"powerconf", @"PowerConf"),
        APBInput(4, @"builtin", @"MacBook Air Microphone"),
        APBInput(5, @"iphone", @"Dave's iPhone 16 Pro Microphone"),
    ];
    _model = APBTestModel(_audio, APBIsolatedDefaults(), nil, nil, nil);
    [_model start];
    _panel = [[APBPanelView alloc] initWithModel:_model];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, APBPanelWidth, 600)
                                          styleMask:NSWindowStyleMaskBorderless
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _panel;
    // Layer-backed like the real panel, whose glass background backs it.
    _panel.wantsLayer = YES;
    [_panel refresh];
    [_panel layoutSubtreeIfNeeded];
}

- (void)tearDown {
    [_window close];
}

- (APBDeviceRowView *)rowFor:(NSString *)uid {
    NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:_panel];
    while (queue.count) {
        NSView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:APBDeviceRowView.class] && [((APBDeviceRowView *)view).device.uid isEqualToString:uid]) {
            return (APBDeviceRowView *)view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)windowPoint {
    return [NSEvent mouseEventWithType:type
                              location:windowPoint
                         modifierFlags:0
                             timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:_window.windowNumber
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1];
}

/// The center of a row in window coordinates.
- (NSPoint)centerOf:(NSView *)view {
    return [view convertPoint:NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView:nil];
}

- (void)testTheLiftedRowStaysUnderThePointerAndDropsWhereItWasShown {
    APBDeviceRowView *row = [self rowFor:@"scarlett"];
    XCTAssertNotNil(row);
    NSRect restingFrame = row.frame;
    NSPoint start = [self centerOf:row];

    [row mouseDown:[self mouse:NSEventTypeLeftMouseDown at:start]];
    // Two rows down, in window coordinates, which grow upward.
    NSPoint point = start;
    for (int step = 1; step <= 10; step++) {
        // A little past two rows, clear of the boundary between two gaps.
        point = NSMakePoint(start.x, start.y - step * (APBRowPitch * 2 + 6) / 10);
        [row mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:point]];
    }
    APBWaitUntil(0.5, ^BOOL { return NO; });

    // The lifted row stays within the panel horizontally, never shifted half
    // a width to the left, and still has the row's width.
    // Where the layer draws, which a layer transform or anchor point can move
    // away from the view's frame.
    CALayer *layer = row.layer;
    CGRect drawn = layer ? [layer convertRect:layer.bounds toLayer:_window.contentView.layer] : NSRectToCGRect(row.frame);
    NSRect lifted = NSRectFromCGRect(drawn);
    XCTAssertGreaterThanOrEqual(NSMinX(lifted), -1);
    XCTAssertLessThanOrEqual(NSMaxX(lifted), APBPanelWidth + 1);
    XCTAssertEqualWithAccuracy(NSWidth(lifted), NSWidth(restingFrame), NSWidth(restingFrame) * 0.03);
    // AppKit positions a view's layer by its anchor point, so the lift must
    // not use a layer transform: one about the center drew the row half its
    // width to the left.
    XCTAssertNotNil(row.layer);
    XCTAssertTrue(CATransform3DIsIdentity(row.layer.transform), @"the row must not be moved by a layer transform");

    [row mouseUp:[self mouse:NSEventTypeLeftMouseUp at:point]];
    APBWaitUntil(0.5, ^BOOL { return NO; });

    // Dropped into the gap after PowerConf and the MacBook microphone, where
    // the preview showed it.
    XCTAssertEqualObjects([_model.inputDevices valueForKey:@"uid"],
                          (@[ @"powerconf", @"builtin", @"scarlett", @"iphone" ]));
    // Back at the panel's left edge once settled.
    APBDeviceRowView *settled = [self rowFor:@"scarlett"];
    XCTAssertEqualWithAccuracy(NSMinX(settled.frame), NSMinX(restingFrame), 0.5);
    XCTAssertEqualWithAccuracy(NSWidth(settled.frame), NSWidth(restingFrame), 0.5);
}

@end
