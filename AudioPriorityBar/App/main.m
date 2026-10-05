#import <AppKit/AppKit.h>
#import "APBAppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        APBAppDelegate *delegate = [[APBAppDelegate alloc] init];
        app.delegate = delegate;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        [app run];
        // The application holds its delegate weakly.
        (void)delegate;
    }
    return 0;
}
