#import <AppKit/AppKit.h>
#import "APBAppModel.h"
#import "APBHotKey.h"
#import "APBServices.h"

NS_ASSUME_NONNULL_BEGIN

/// Owns the model and everything that feeds it.
@interface APBAppRuntime : NSObject
@property (nonatomic, readonly) APBAppModel *model;
@property (nonatomic, readonly) APBUpdateChecker *updates;
/// Starts as Option-Shift-M, which no call app uses for its own mute.
@property (nonatomic, readonly) APBHotKey *muteHotKey;
/// NO when audio changes cannot be monitored.
- (BOOL)start;
- (void)stop;
@end

@interface APBAppDelegate : NSObject <NSApplicationDelegate>
@end

NS_ASSUME_NONNULL_END
