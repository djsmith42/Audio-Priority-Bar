#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "TestSupport.h"
#import "DeviceDrag.h"
#import "StatusItemRouting.h"

static NSArray<NSArray<NSNumber *> *> *Sections(NSArray<NSNumber *> *counts) {
    NSArray<NSNumber *> *sections = @[
        @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone), @(APBDeviceSectionInput),
    ];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i < counts.count; i++) [pairs addObject:@[sections[i], counts[i]]];
    return pairs;
}

static APBDeviceDrag *Drag(APBAudioDevice *device, APBDeviceSection section, NSInteger index,
                           APBDropTarget *target) {
    APBDeviceDrag *drag = [[APBDeviceDrag alloc] initWithDevice:device section:section index:index];
    drag.target = target;
    return drag;
}

@interface DeviceInteractionTests : XCTestCase
@end

@implementation DeviceInteractionTests

- (void)testDropReordersSpeakersAndMicrophonesWithinTheirLists {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *firstSpeaker = APBOutput(1, @"speaker-1", nil);
    APBAudioDevice *secondSpeaker = APBOutput(2, @"speaker-2", nil);
    APBAudioDevice *thirdSpeaker = APBOutput(3, @"speaker-3", nil);
    APBAudioDevice *firstMic = APBInput(4, @"mic-1", nil);
    APBAudioDevice *secondMic = APBInput(5, @"mic-2", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[firstSpeaker, secondSpeaker, thirdSpeaker, firstMic, secondMic];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertTrue([model dropDevice:firstSpeaker.identifier into:APBOutputCategorySpeaker at:3]);
    XCTAssertTrue([model dropDevice:secondMic.identifier into:APBOutputCategoryNone at:0]);
    XCTAssertEqualObjects(model.speakerDevices, (@[secondSpeaker, thirdSpeaker, firstSpeaker]));
    XCTAssertEqualObjects(model.inputDevices, (@[secondMic, firstMic]));
}

- (void)testStaleMoveActionsLeaveRefreshedListsUnchanged {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *microphone = APBInput(2, @"microphone", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, microphone];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model moveOutputIn:APBOutputCategorySpeaker from:[NSIndexSet indexSetWithIndex:2] to:3];
    [model moveInputFrom:[NSIndexSet indexSetWithIndex:2] to:3];

    XCTAssertEqualObjects(model.speakerDevices, @[speaker]);
    XCTAssertEqualObjects(model.inputDevices, @[microphone]);
}

- (void)testDropMovesOutputBetweenListsAtRequestedPosition {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *firstHeadphone = APBOutput(2, @"headphone-1", @"AirPods Pro");
    APBAudioDevice *secondHeadphone = APBOutput(3, @"headphone-2", @"USB Headphones");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, firstHeadphone, secondHeadphone];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertTrue([model dropDevice:speaker.identifier into:APBOutputCategoryHeadphone at:1]);
    XCTAssertEqualObjects(model.headphoneDevices, (@[firstHeadphone, speaker, secondHeadphone]));
    XCTAssertEqual([model.store categoryForDevice:speaker], APBOutputCategoryHeadphone);
    XCTAssertEqualObjects(([model.store sorted:@[firstHeadphone, secondHeadphone, speaker]
                                      category:APBOutputCategoryHeadphone]),
                          (@[firstHeadphone, speaker, secondHeadphone]));

    XCTAssertTrue([model dropDevice:speaker.identifier into:APBOutputCategorySpeaker at:0]);
    XCTAssertEqualObjects(model.speakerDevices, @[speaker]);
    XCTAssertEqual([model.store categoryForDevice:speaker], APBOutputCategorySpeaker);
}

- (void)testCrossListDropUsesStableIdentityAfterDeviceRefresh {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[APBOutput(3, @"speaker", nil), headphones];

    XCTAssertTrue([model dropDevice:speaker.identifier into:APBOutputCategoryHeadphone at:1]);
    XCTAssertEqualObjects([model.headphoneDevices valueForKey:@"identifier"],
                          (@[headphones.identifier, speaker.identifier]));
    XCTAssertEqual(model.headphoneDevices[1].platformID, 3u);
}

- (void)testInsertionIndexPicksTheNearestGap {
    CGFloat top = APBDeviceSectionHeaderHeight + APBDeviceRowSpacing;
    CGFloat pitch = APBDeviceRowPitch;

    XCTAssertEqual([APBPanelLayout insertionIndexForY:top rowCount:3], 0);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:top + pitch * 0.4 rowCount:3], 0);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:top + pitch * 0.6 rowCount:3], 1);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:top + pitch * 3 rowCount:3], 3);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:0 rowCount:3], 0);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:10000 rowCount:3], 3);
    XCTAssertEqual([APBPanelLayout insertionIndexForY:10000 rowCount:0], 0);
}

- (void)testLayoutResolvesRawTargetSection {
    APBPanelLayout *layout = [[APBPanelLayout alloc] initWithSections:Sections(@[@2, @1, @2])];
    CGFloat speakerTop = APBPanelLayout.topPadding;
    CGFloat headphoneTop = speakerTop
        + APBDeviceSectionHeaderHeight + 2 * APBDeviceRowPitch
        + APBPanelLayout.sectionGap;

    CGPoint inSpeakers = CGPointMake(10, speakerTop + 20);
    APBDropTarget *speakerTarget = [layout targetAt:inSpeakers];
    XCTAssertNotNil(speakerTarget);
    XCTAssertEqual(speakerTarget.section, APBDeviceSectionSpeaker);

    CGPoint inHeadphones = CGPointMake(10, headphoneTop + 20);
    APBDropTarget *headphoneTarget = [layout targetAt:inHeadphones];
    XCTAssertNotNil(headphoneTarget);
    XCTAssertEqual(headphoneTarget.section, APBDeviceSectionHeadphone);

    CGPoint farDown = CGPointMake(10, layout.contentHeight - 10);
    APBDropTarget *inputTarget = [layout targetAt:farDown];
    XCTAssertNotNil(inputTarget);
    XCTAssertEqual(inputTarget.section, APBDeviceSectionInput);
    XCTAssertEqualObjects([layout targetAt:CGPointMake(10, -1)],
                          [APBDropTarget targetWithSection:APBDeviceSectionSpeaker index:0]);
    XCTAssertNil([layout targetAt:CGPointMake(10, layout.contentHeight + APBPanelLayout.sectionGap)]);
}

- (void)testRoleMismatchesAreForbiddenUntilTheDragReentersAValidSection {
    APBPanelLayout *layout = [[APBPanelLayout alloc] initWithSections:Sections(@[@1, @1, @1])];
    CGSize translation = CGSizeMake(12, 80);
    for (NSNumber *sectionValue in @[@(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone)]) {
        APBDeviceSection section = sectionValue.integerValue;
        APBDeviceDrag *microphoneDrag = [[APBDeviceDrag alloc] initWithDevice:APBInput(1, @"microphone", nil)
                                                                      section:APBDeviceSectionInput
                                                                        index:0];

        [microphoneDrag updateHovered:[APBDropTarget targetWithSection:section index:0]
                          translation:translation];

        XCTAssertTrue(microphoneDrag.isForbidden, @"section %ld", (long)section);
        XCTAssertNil(microphoneDrag.target, @"section %ld", (long)section);
        XCTAssertTrue(CGSizeEqualToSize(microphoneDrag.translation, translation), @"section %ld", (long)section);
        XCTAssertTrue(CGSizeEqualToSize([layout liftedOffsetFor:microphoneDrag],
                                        CGSizeMake(0, translation.height)),
                      @"section %ld", (long)section);
    }

    APBDeviceDrag *outputDrag = [[APBDeviceDrag alloc] initWithDevice:APBOutput(2, @"output", nil)
                                                              section:APBDeviceSectionSpeaker
                                                                index:0];
    [outputDrag updateHovered:[APBDropTarget targetWithSection:APBDeviceSectionInput index:0]
                  translation:translation];
    XCTAssertTrue(outputDrag.isForbidden);
    XCTAssertNil(outputDrag.target);

    [outputDrag updateHovered:nil translation:translation];
    XCTAssertFalse(outputDrag.isForbidden);
    XCTAssertNil(outputDrag.target);
    XCTAssertTrue(CGSizeEqualToSize([layout liftedOffsetFor:outputDrag], CGSizeMake(0, translation.height)));

    APBDropTarget *validTarget = [APBDropTarget targetWithSection:APBDeviceSectionHeadphone index:1];
    [outputDrag updateHovered:validTarget translation:translation];
    XCTAssertFalse(outputDrag.isForbidden);
    XCTAssertEqualObjects(outputDrag.target, validTarget);
}

- (void)testCrossSectionDragShiftsOnlySectionsBetweenSourceAndTarget {
    APBPanelLayout *downLayout = [[APBPanelLayout alloc] initWithSections:Sections(@[@2, @1, @1])];
    APBAudioDevice *device = APBOutput(1, @"speaker", nil);
    APBDeviceDrag *down = Drag(device, APBDeviceSectionSpeaker, 0,
                               [APBDropTarget targetWithSection:APBDeviceSectionHeadphone index:1]);

    XCTAssertEqual([downLayout sectionOffsetFor:APBDeviceSectionSpeaker drag:down], 0);
    XCTAssertEqual([downLayout sectionOffsetFor:APBDeviceSectionHeadphone drag:down], -APBDeviceRowPitch);
    XCTAssertEqual([downLayout sectionOffsetFor:APBDeviceSectionInput drag:down], 0);

    APBPanelLayout *upLayout = [[APBPanelLayout alloc] initWithSections:Sections(@[@1, @2, @1])];
    APBDeviceDrag *up = Drag(device, APBDeviceSectionHeadphone, 0,
                             [APBDropTarget targetWithSection:APBDeviceSectionSpeaker index:0]);

    XCTAssertEqual([upLayout sectionOffsetFor:APBDeviceSectionSpeaker drag:up], 0);
    XCTAssertEqual([upLayout sectionOffsetFor:APBDeviceSectionHeadphone drag:up], APBDeviceRowPitch);
    XCTAssertEqual([upLayout sectionOffsetFor:APBDeviceSectionInput drag:up], 0);
}

- (void)testCrossSectionOffsetsMatchPostDropLayoutAtPlaceholderBoundaries {
    // before, after, source, target
    NSArray<NSArray *> *scenarios = @[
        @[@[@1, @1, @1], @[@0, @2, @1], @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone)],
        @[@[@2, @0, @1], @[@1, @1, @1], @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone)],
        @[@[@1, @0, @1], @[@0, @1, @1], @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone)],
        @[@[@1, @1, @1], @[@2, @0, @1], @(APBDeviceSectionHeadphone), @(APBDeviceSectionSpeaker)],
        @[@[@0, @2, @1], @[@1, @1, @1], @(APBDeviceSectionHeadphone), @(APBDeviceSectionSpeaker)],
        @[@[@3, @2, @1], @[@2, @3, @1], @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone)],
    ];
    NSArray<NSNumber *> *sections = @[
        @(APBDeviceSectionSpeaker), @(APBDeviceSectionHeadphone), @(APBDeviceSectionInput),
    ];

    for (NSArray *scenario in scenarios) {
        APBPanelLayout *before = [[APBPanelLayout alloc] initWithSections:Sections(scenario[0])];
        APBPanelLayout *after = [[APBPanelLayout alloc] initWithSections:Sections(scenario[1])];
        APBDeviceDrag *drag = Drag(APBOutput(1, @"device", nil), [scenario[2] integerValue], 0,
                                   [APBDropTarget targetWithSection:[scenario[3] integerValue] index:0]);

        for (NSNumber *sectionValue in sections) {
            APBDeviceSection section = sectionValue.integerValue;
            CGFloat beforeTop = [before sectionTopOf:section];
            XCTAssertFalse(isnan(beforeTop), @"%@ section %ld", scenario, (long)section);
            if (isnan(beforeTop)) return;
            CGFloat predicted = beforeTop + [before sectionOffsetFor:section drag:drag];
            XCTAssertEqual(predicted, [after sectionTopOf:section], @"%@ section %ld", scenario, (long)section);
        }

        // The panel sizes its scroll view from this, so a preview that is
        // taller than the frame clips its bottom row.
        XCTAssertEqual(before.contentHeight + [before heightDeltaFor:drag], after.contentHeight, @"%@", scenario);
    }
}

- (void)testLiftedRowSnapsBelowTargetHeaderWithoutOverlappingNextSection {
    APBPanelLayout *layout = [[APBPanelLayout alloc] initWithSections:Sections(@[@4, @4, @3])];
    NSInteger sourceIndex = 2;
    NSInteger targetIndex = 3;
    APBDeviceDrag *drag = Drag(APBOutput(1, @"speaker", nil), APBDeviceSectionSpeaker, sourceIndex,
                               [APBDropTarget targetWithSection:APBDeviceSectionHeadphone index:targetIndex]);
    CGFloat speakerContentTop = [layout contentTopOf:APBDeviceSectionSpeaker];
    CGFloat headphoneContentTop = [layout contentTopOf:APBDeviceSectionHeadphone];
    CGFloat inputSectionTop = [layout sectionTopOf:APBDeviceSectionInput];
    XCTAssertFalse(isnan(speakerContentTop));
    XCTAssertFalse(isnan(headphoneContentTop));
    XCTAssertFalse(isnan(inputSectionTop));
    if (isnan(speakerContentTop) || isnan(headphoneContentTop) || isnan(inputSectionTop)) return;
    CGFloat sourceTop = speakerContentTop;
    CGFloat targetTop = headphoneContentTop + [layout sectionOffsetFor:APBDeviceSectionHeadphone drag:drag];
    CGFloat nextHeaderTop = inputSectionTop + [layout sectionOffsetFor:APBDeviceSectionInput drag:drag];
    CGFloat liftedTop = sourceTop
        + (CGFloat)sourceIndex * APBDeviceRowPitch
        + [layout sectionOffsetFor:APBDeviceSectionSpeaker drag:drag]
        + [layout liftedOffsetFor:drag].height;

    XCTAssertEqual(liftedTop, targetTop + (CGFloat)targetIndex * APBDeviceRowPitch);
    XCTAssertLessThanOrEqual(liftedTop + APBDeviceRowHeight, nextHeaderTop);
}

- (void)testLiftedRowHandlesSameSectionEmptyTargetAndInvalidTarget {
    APBAudioDevice *device = APBOutput(1, @"speaker", nil);
    APBPanelLayout *sameSection = [[APBPanelLayout alloc] initWithSections:Sections(@[@3, @0, @1])];
    APBDeviceDrag *moveToEnd = Drag(device, APBDeviceSectionSpeaker, 0,
                                    [APBDropTarget targetWithSection:APBDeviceSectionSpeaker index:3]);
    XCTAssertEqual([sameSection liftedOffsetFor:moveToEnd].height, APBDeviceRowPitch * 2);
    XCTAssertEqual([sameSection sectionOffsetFor:APBDeviceSectionSpeaker drag:moveToEnd], 0);

    APBPanelLayout *emptyTarget = [[APBPanelLayout alloc] initWithSections:Sections(@[@1, @0, @1])];
    APBDeviceDrag *moveToEmpty = Drag(device, APBDeviceSectionSpeaker, 0,
                                      [APBDropTarget targetWithSection:APBDeviceSectionHeadphone index:0]);
    XCTAssertEqual([emptyTarget liftedOffsetFor:moveToEmpty].height,
                   APBDeviceSectionHeaderHeight + APBDeviceRowPitch + APBPanelLayout.sectionGap);

    APBDeviceDrag *invalid = Drag(device, APBDeviceSectionSpeaker, 0, nil);
    XCTAssertTrue(CGSizeEqualToSize([sameSection liftedOffsetFor:invalid], CGSizeZero));
    XCTAssertEqual([sameSection sectionOffsetFor:APBDeviceSectionHeadphone drag:invalid], 0);
    XCTAssertEqual([sameSection rowOffsetAt:1 in:APBDeviceSectionSpeaker drag:invalid], 0);
}

- (void)testChangingCategoryKeepsAHiddenDeviceHidden {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model hide:speaker];
    XCTAssertEqual(model.speakerDevices.count, 0u);

    [model setCategory:APBOutputCategoryHeadphone forDevice:speaker];

    XCTAssertEqual(model.headphoneDevices.count, 0u);
    XCTAssertEqualObjects(model.hiddenHeadphoneDevices, @[speaker]);
}

- (void)testChangingCategoryKeepsAVisibleDeviceVisible {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    [model setCategory:APBOutputCategoryHeadphone forDevice:speaker];

    XCTAssertEqualObjects(model.headphoneDevices, @[speaker]);
    XCTAssertEqual(model.hiddenHeadphoneDevices.count, 0u);
}

- (void)testSettingsFollowTheScreenBeingUsedWithoutNudgingTheWindow {
    NSRect left = NSMakeRect(0, 0, 1920, 1080);
    NSRect right = NSMakeRect(1920, 0, 1440, 900);
    // Menu bar and Dock removed, so centering must use the visible area.
    NSRect rightVisible = NSMakeRect(1920, 80, 1440, 780);
    NSRect window = NSMakeRect(100, 200, 420, 480);

    // Left behind on the other screen, so it comes to this one, centered.
    NSValue *moved = [APBSettingsPlacement originForWindow:window screenFrame:right visibleFrame:rightVisible];
    XCTAssertNotNil(moved);
    XCTAssertTrue(NSEqualPoints(moved.pointValue, NSMakePoint(1920 + 720 - 210, 80 + 390 - 240)),
                  @"%@", NSStringFromPoint(moved.pointValue));

    // Already here, so wherever the user dragged it is respected.
    XCTAssertNil([APBSettingsPlacement originForWindow:window screenFrame:left visibleFrame:left]);

    // Straddling two screens counts as being on the one holding its centre.
    NSRect straddling = NSMakeRect(1800, 200, 420, 480);
    XCTAssertNil([APBSettingsPlacement originForWindow:straddling screenFrame:right visibleFrame:rightVisible]);
}

- (void)testANewDisplayOutputArrivesHidden {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *dell = [[APBAudioDevice alloc] initWithPlatformID:2
                                                                  uid:@"dell"
                                                                 name:@"DELL U2518D"
                                                                 role:APBDeviceRoleOutput
                                                          isConnected:YES
                                                            isVirtual:NO
                                                     declaredCategory:APBOutputCategoryNone
                                                      isDisplayOutput:YES
                                                        transportType:0];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, dell];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    // Hiding is applied while remembering, which happens inside the same
    // refresh that splits the lists, so one pass has to be enough.
    XCTAssertEqualObjects(model.speakerDevices, @[speaker]);
    XCTAssertEqualObjects(model.hiddenSpeakerDevices, @[dell]);
}

- (void)testTheActiveOutputStaysListedEvenWhenHidden {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *dell = [[APBAudioDevice alloc] initWithPlatformID:1
                                                                  uid:@"dell"
                                                                 name:@"DELL U2518D"
                                                                 role:APBDeviceRoleOutput
                                                          isConnected:YES
                                                            isVirtual:NO
                                                     declaredCategory:APBOutputCategoryNone
                                                      isDisplayOutput:YES
                                                        transportType:0];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[dell];
    audio.defaults[@(APBDeviceRoleOutput)] = @(dell.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    // Hidden, but still shown, because hiding the row would leave no way to
    // see where the sound is going.
    XCTAssertTrue([model isHidden:dell]);
    XCTAssertEqualObjects(model.speakerDevices, @[dell]);
    XCTAssertEqual(model.hiddenSpeakerDevices.count, 0u);
}

- (void)testTheActiveMicrophoneStaysListedEvenWhenHidden {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *mic = APBInput(1, @"mic", nil);
    [store hide:mic];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[mic];
    audio.defaults[@(APBDeviceRoleInput)] = @(mic.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);

    [model start];

    // Hidden, but still shown, because hiding the row would leave no way to
    // see which microphone is in use.
    XCTAssertTrue([model isHidden:mic]);
    XCTAssertEqualObjects(model.inputDevices, @[mic]);

    // Automatic selection still refuses a hidden microphone: with the only
    // candidate hidden, nothing gets selected.
    [model setManualMode:NO];
    XCTAssertEqual(audio.selections.count, 0u);
}

- (void)testDropRejectsDevicesFromAnotherRole {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *mic = APBInput(2, @"mic", nil);
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, mic];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertFalse([model dropDevice:mic.identifier into:APBOutputCategorySpeaker at:0]);
    XCTAssertFalse([model dropDevice:speaker.identifier into:APBOutputCategoryNone at:0]);
    XCTAssertEqualObjects(model.speakerDevices, @[speaker]);
    XCTAssertEqualObjects(model.inputDevices, @[mic]);
}

- (void)testOutputDropReappliesAutomaticSelectionOnce {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    XCTAssertTrue([model dropDevice:headphones.identifier into:APBOutputCategorySpeaker at:1]);
    XCTAssertEqualObjects(audio.selectedIDs, @[@(speaker.platformID)]);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

- (void)testCrossListDropDoesNotSelectBeforeFinalOrderIsSaved {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];
    [audio.selections removeAllObjects];

    XCTAssertTrue([model dropDevice:headphones.identifier into:APBOutputCategorySpeaker at:0]);
    XCTAssertEqual(audio.selections.count, 0u);
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
}

- (void)testOutputDropKeepsManualSelectionActive {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    store.isManualMode = YES;
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[speaker, headphones];
    audio.defaults[@(APBDeviceRoleOutput)] = @(headphones.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    XCTAssertTrue([model dropDevice:headphones.identifier into:APBOutputCategorySpeaker at:1]);
    XCTAssertEqual(audio.selections.count, 0u);
    XCTAssertEqualObjects(model.currentOutputID, @(headphones.platformID));
}

- (void)testDualRoleDisconnectKeepsAutomaticForBothRoles {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *headsetOutput = APBOutput(1, @"headset", @"AirPods Pro");
    APBAudioDevice *headsetInput = APBInput(1, @"headset", @"AirPods Pro");
    APBAudioDevice *speaker = APBOutput(2, @"speaker", nil);
    APBAudioDevice *builtin = APBInput(3, @"builtin", nil);
    APBAudioDevice *webcam = APBInput(4, @"webcam", @"Webcam");
    [store savePriorities:@[headsetInput, webcam, builtin] role:APBDeviceRoleInput];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[headsetOutput, headsetInput, speaker, builtin, webcam];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[speaker, builtin, webcam];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    audio.defaults[@(APBDeviceRoleInput)] = @(builtin.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];
    [model handleDefaultChanged:APBDeviceRoleInput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
    XCTAssertEqualObjects(model.currentInputID, @(webcam.platformID));
}

- (void)testNoAutomaticTargetDoesNotSilentlyEnableManual {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBPriorityStore *store = [[APBPriorityStore alloc] initWithDefaults:defaults];
    APBAudioDevice *first = APBOutput(1, @"first", nil);
    APBAudioDevice *second = APBOutput(2, @"second", nil);
    [store setNeverUse:first value:YES];
    [store setNeverUse:second value:YES];
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    audio.catalog = @[first, second];
    audio.defaults[@(APBDeviceRoleOutput)] = @(first.platformID);
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, nil);
    [model start];

    audio.catalog = @[second];
    audio.defaults[@(APBDeviceRoleOutput)] = @(second.platformID);
    [model handleDevicesChanged];
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(second.platformID));
}

- (void)testUnrelatedConnectionDoesNotMaskSoundSettingsChoice {
    NSUserDefaults *defaults = APBIsolatedDefaults();
    APBFakeAudio *audio = [[APBFakeAudio alloc] init];
    APBAudioDevice *speaker = APBOutput(1, @"speaker", nil);
    APBAudioDevice *headphones = APBOutput(2, @"headphones", @"AirPods Pro");
    APBAudioDevice *display = APBOutput(3, @"display", @"HDMI");
    audio.catalog = @[speaker, headphones];
    APBAppModel *model = APBTestModel(audio, defaults, nil, nil, ^BOOL { return YES; });
    [model start];

    audio.catalog = [audio.catalog arrayByAddingObject:display];
    audio.defaults[@(APBDeviceRoleOutput)] = @(speaker.platformID);
    [model handleDefaultChanged:APBDeviceRoleOutput];

    XCTAssertFalse(model.isManualMode);
    XCTAssertEqualObjects(model.currentOutputID, @(speaker.platformID));
}

@end
