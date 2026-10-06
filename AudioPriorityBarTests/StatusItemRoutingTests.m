#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TestSupport.h"
#import "AppRuntime.h"
#import "KeyboardShortcuts.h"
#import "NoticeContent.h"
#import "StatusItemRouting.h"

@interface StatusItemRoutingTests : XCTestCase
@end

@implementation StatusItemRoutingTests

- (void)testTheDefaultMuteShortcutReadsOptionShiftMOnTheCurrentLayout {
    XCTAssertEqualObjects(APBShortcut.optionShiftM.displayString, @"⌥⇧M");
}

- (void)testStatusItemRoutesMouseAndAccessibilityEvents {
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeLeftMouseUp modifiers:0],
                   APBStatusItemClickActionTogglePanel);
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeRightMouseUp modifiers:0],
                   APBStatusItemClickActionShowMenu);
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeLeftMouseUp
                                             modifiers:NSEventModifierFlagControl],
                   APBStatusItemClickActionShowMenu);
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeLeftMouseDown modifiers:0],
                   APBStatusItemClickActionTogglePanel);
}

- (void)testOptionClickTogglesMute {
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeLeftMouseUp
                                             modifiers:NSEventModifierFlagOption],
                   APBStatusItemClickActionToggleMute);
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeLeftMouseUp
                                             modifiers:NSEventModifierFlagOption | NSEventModifierFlagControl],
                   APBStatusItemClickActionShowMenu);
    XCTAssertEqual([APBClickRouting actionForEventType:NSEventTypeRightMouseUp
                                             modifiers:NSEventModifierFlagOption],
                   APBStatusItemClickActionShowMenu);
}

- (void)testStatusItemSuppressionIsConsumeOnceAndExpires {
    XCTAssertTrue([APBClickRouting shouldSuppressOpenSuppressedAt:@10 now:10.5]);
    XCTAssertFalse([APBClickRouting shouldSuppressOpenSuppressedAt:@10 now:12]);
    XCTAssertFalse([APBClickRouting shouldSuppressOpenSuppressedAt:nil now:10]);
}

- (void)testNoticesAndThePanelSitCenteredUnderTheStatusItemInsideTheScreen {
    NSRect visible = NSMakeRect(0, 0, 1000, 800);
    NSSize size = NSMakeSize(200, 40);
    NSPoint centered = [APBPanelPlacement originForButtonRect:NSMakeRect(500, 800, 20, 24)
                                                         size:size
                                                 visibleFrame:visible];
    XCTAssertTrue(NSEqualPoints(centered, NSMakePoint(410, 756)), @"%@", NSStringFromPoint(centered));
    // Near the right edge the window stays 4 points inside the screen.
    XCTAssertEqual([APBPanelPlacement originForButtonRect:NSMakeRect(980, 800, 20, 24)
                                                     size:size
                                             visibleFrame:visible].x,
                   796);
}

- (void)testAHeadsetSwitchingBothHalvesReadsAsOneDevice {
    APBAudioDevice *jabraOut = APBOutput(1, @"jabra:1", @"Jabra Link 380");
    APBAudioDevice *jabraIn = APBInput(2, @"jabra:2", @"Jabra Link 380");
    APBAudioDevice *mic = APBInput(3, @"builtin", @"MacBook Pro Microphone");
    APBNoticeContent *(^notice)(NSArray<APBAudioDevice *> *) = ^(NSArray<APBAudioDevice *> *devices) {
        return [APBNoticeContent switchedTo:devices icon:^NSString *(APBAudioDevice *device) {
            return device.role == APBDeviceRoleInput ? @"mic" : @"headphones";
        }];
    };
    XCTAssertEqualObjects(notice(@[jabraOut]), [[APBNoticeContent alloc]
        initWithLines:@[[APBNoticeLine lineWithIcon:@"headphones" text:@"Jabra Link 380"]]
         announcement:@"Output: Jabra Link 380"]);
    XCTAssertEqualObjects((notice(@[jabraOut, jabraIn])), [[APBNoticeContent alloc]
        initWithLines:@[[APBNoticeLine lineWithIcon:@"headphones" text:@"Jabra Link 380"]]
         announcement:@"Output and microphone: Jabra Link 380"]);
    // The icons carry the role on screen; VoiceOver still hears it spoken.
    XCTAssertEqualObjects((notice(@[jabraOut, mic])), ([[APBNoticeContent alloc]
        initWithLines:@[
            [APBNoticeLine lineWithIcon:@"headphones" text:@"Jabra Link 380"],
            [APBNoticeLine lineWithIcon:@"mic" text:@"MacBook Pro Microphone"],
        ]
         announcement:@"Output: Jabra Link 380, Microphone: MacBook Pro Microphone"]));
}

- (void)testADeviceIsBeingPickedOnlyWhileControlCenterOrSystemSettingsIsInUse {
    NSDictionary<NSString *, id> *(^window)(pid_t, NSInteger) = ^(pid_t pid, NSInteger layer) {
        return @{(__bridge NSString *)kCGWindowOwnerPID: @(pid), (__bridge NSString *)kCGWindowLayer: @(layer)};
    };
    // Observed on macOS 26: Control Center's menu bar items sit at the status
    // layer, 25, and the open Sound menu adds a 458x1067 window at layer 23.
    // An app using the microphone, even in full screen, adds nothing.
    NSArray *menuBar = @[window(400, 25), window(400, 25)];
    NSDictionary *soundMenu = window(400, 23);
    NSDictionary *otherApp = window(900, 23);
    BOOL (^picking)(NSArray *, NSString *) = ^BOOL(NSArray *windows, NSString *frontmost) {
        return [APBSystemSoundPicker isInUseWithWindows:windows
                                      controlCenterPIDs:[NSSet setWithObject:@400]
                                      frontmostBundleID:frontmost];
    };
    NSString *cursor = @"com.todesktop.cursor";
    XCTAssertFalse(picking([menuBar arrayByAddingObject:otherApp], cursor));
    XCTAssertTrue(picking([menuBar arrayByAddingObject:soundMenu], cursor));
    XCTAssertTrue(picking(menuBar, @"com.apple.systempreferences"));
}

- (void)testADismissedMutedReminderStaysHiddenUntilItStopsApplying {
    APBMutedReminderState *reminder = [[APBMutedReminderState alloc] init];
    NSMutableArray<NSNumber *> *shows = [NSMutableArray array];
    [shows addObject:@([reminder updateApplies:YES])];
    [reminder dismiss];
    [shows addObject:@([reminder updateApplies:YES])];
    // Unmuting or the recording ending clears the dismissal.
    [shows addObject:@([reminder updateApplies:NO])];
    [shows addObject:@([reminder updateApplies:YES])];
    XCTAssertEqualObjects(shows, (@[@YES, @NO, @NO, @YES]));
}

- (void)testASwitchNoticeOutranksTheMutedReminderButNeverCoversThePanel {
    APBNoticeContent *notice = [[APBNoticeContent alloc]
        initWithLines:@[[APBNoticeLine lineWithIcon:@"airpodspro" text:@"AirPods Pro"]]
         announcement:@"Output: AirPods Pro"];
    XCTAssertEqualObjects([APBNoticeContent currentWithSwitchNotice:notice showsMutedReminder:YES isSuppressed:NO],
                          notice);
    XCTAssertEqualObjects([APBNoticeContent currentWithSwitchNotice:nil showsMutedReminder:YES isSuppressed:NO],
                          APBNoticeContent.mutedWhileRecording);
    XCTAssertNil([APBNoticeContent currentWithSwitchNotice:notice showsMutedReminder:YES isSuppressed:YES]);
}

@end
