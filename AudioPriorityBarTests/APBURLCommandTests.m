#import <XCTest/XCTest.h>
#import "APBPriorityStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface APBURLCommandTests : XCTestCase
@end

@implementation APBURLCommandTests

static APBURLCommand command(NSString *string) {
    NSURL *url = [NSURL URLWithString:string];
    return url == nil ? APBURLCommandNone : APBURLCommandFromURL(url);
}

- (void)testTheThreeMicrophoneURLsAreRecognised {
    XCTAssertEqual(command(@"audioprioritybar://toggle-mic-mute"), APBURLCommandToggleMicMute);
    XCTAssertEqual(command(@"audioprioritybar://mute-mic"), APBURLCommandMuteMic);
    XCTAssertEqual(command(@"audioprioritybar://unmute-mic"), APBURLCommandUnmuteMic);
    XCTAssertEqual(command(@"AudioPriorityBar://Toggle-Mic-Mute"), APBURLCommandToggleMicMute);
}

- (void)testAnythingBeyondTheExactFormIsRejected {
    for (NSString *rejected in @[
        @"https://toggle-mic-mute",
        @"audioprioritybar://",
        @"audioprioritybar://toggle-mic",
        @"audioprioritybar://toggle-mic-mute/",
        @"audioprioritybar://toggle-mic-mute/extra",
        @"audioprioritybar://toggle-mic-mute?on=1",
        @"audioprioritybar://toggle-mic-mute#now",
        @"audioprioritybar://user@toggle-mic-mute",
        @"audioprioritybar://toggle-mic-mute:8080",
        @"audioprioritybar:toggle-mic-mute",
    ]) {
        XCTAssertEqual(command(rejected), APBURLCommandNone, @"%@", rejected);
    }
}

@end

NS_ASSUME_NONNULL_END
