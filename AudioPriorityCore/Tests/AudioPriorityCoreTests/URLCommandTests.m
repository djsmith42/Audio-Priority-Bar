#import <XCTest/XCTest.h>
#import "AudioPriorityCore.h"

static APBURLCommand Command(NSString *string) {
    NSURL *url = [NSURL URLWithString:string];
    return url ? APBURLCommandFromURL(url) : APBURLCommandNone;
}

@interface URLCommandTests : XCTestCase
@end

@implementation URLCommandTests

- (void)testTheThreeMicrophoneURLsAreRecognised {
    XCTAssertEqual(Command(@"audioprioritybar://toggle-mic-mute"), APBURLCommandToggleMicMute);
    XCTAssertEqual(Command(@"audioprioritybar://mute-mic"), APBURLCommandMuteMic);
    XCTAssertEqual(Command(@"audioprioritybar://unmute-mic"), APBURLCommandUnmuteMic);
    XCTAssertEqual(Command(@"AudioPriorityBar://Toggle-Mic-Mute"), APBURLCommandToggleMicMute);
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
        XCTAssertEqual(Command(rejected), APBURLCommandNone, @"%@", rejected);
    }
}

@end
