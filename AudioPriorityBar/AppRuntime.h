#import <Foundation/Foundation.h>
#import "AppModel.h"
#import "UpdateChecker.h"

NS_ASSUME_NONNULL_BEGIN

/// Whether someone is picking a device in Control Center or System Settings
/// right now. CoreAudio never says who changed a default, but Control Center
/// shows a window outside the menu bar's layer only while one of its menus is
/// open. Window owners and layers need no permission to read.
@interface APBSystemSoundPicker : NSObject

+ (BOOL)isInUse;
+ (BOOL)isInUseWithWindows:(NSArray<NSDictionary<NSString *, id> *> *)windows
         controlCenterPIDs:(NSSet<NSNumber *> *)controlCenterPIDs
         frontmostBundleID:(nullable NSString *)frontmostBundleID;

@end

/// Wires the model to CoreAudio, the Jabra monitor, updates and the mute
/// shortcut.
@interface APBAppRuntime : NSObject

@property (nonatomic, readonly) APBAppModel *model;
@property (nonatomic, readonly) APBUpdateChecker *updates;

/// NO when CoreAudio refused the listeners, so changes go unnoticed.
- (BOOL)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
