#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "LaunchAtLoginController.h"
#import "UpdateChecker.h"

@interface AppIdentityTests : XCTestCase
@end

@implementation AppIdentityTests

- (void)testApplicationIdentityIsStable {
    XCTAssertEqualObjects(NSBundle.mainBundle.bundleIdentifier, @"app.audioprioritybar");
    XCTAssertEqualObjects(APBAppDisplayName, @"Audio Priority Bar");
}

- (void)testLaunchAtLoginShowsApprovalAndRegistrationErrors {
    APBLaunchAtLoginController *approval = [[APBLaunchAtLoginController alloc]
        initWithStatus:^SMAppServiceStatus { return SMAppServiceStatusRequiresApproval; }
              register:^BOOL(NSError **error) { return YES; }
            unregister:^BOOL(NSError **error) { return YES; }];
    XCTAssertTrue(approval.isEnabled);
    XCTAssertTrue(approval.requiresApproval);
    [approval setEnabled:NO];
    XCTAssertFalse(approval.isEnabled);
    XCTAssertFalse(approval.requiresApproval);

    __block BOOL registered = NO;
    APBLaunchAtLoginController *failure = [[APBLaunchAtLoginController alloc]
        initWithStatus:^SMAppServiceStatus {
            return registered ? SMAppServiceStatusEnabled : SMAppServiceStatusNotRegistered;
        }
              register:^BOOL(NSError **error) {
                  if (error) *error = [NSError errorWithDomain:@"TestError" code:1 userInfo:nil];
                  return NO;
              }
            unregister:^BOOL(NSError **error) { return YES; }];
    [failure setEnabled:YES];
    XCTAssertNotNil(failure.errorMessage);

    registered = YES;
    [failure refresh];
    XCTAssertNil(failure.errorMessage);
}

- (void)testADownloadedUpdateWaitsUntilTheMicrophoneIsIdle {
    __block BOOL idle = NO;
    __block NSInteger installs = 0;
    APBUpdateChecker *updates = [[APBUpdateChecker alloc] initWithIsIdle:^BOOL { return idle; }];
    [updates installWhenIdle:^{ installs += 1; }];

    [updates installPendingUpdateIfIdle];
    XCTAssertEqual(installs, 0);

    idle = YES;
    [updates installPendingUpdateIfIdle];
    [updates installPendingUpdateIfIdle];
    XCTAssertEqual(installs, 1);
}

@end
