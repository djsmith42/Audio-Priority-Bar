#import <Foundation/Foundation.h>
#import "APBModels.h"

NS_ASSUME_NONNULL_BEGIN

/// No level reported for one part, as for a pod sitting in a closed case.
FOUNDATION_EXPORT const NSInteger APBBatteryLevelNone;

/// Battery percentages one Bluetooth device reports.
@interface APBBatteryLevels : NSObject

@property (nonatomic, readonly) NSInteger left;
@property (nonatomic, readonly) NSInteger right;
@property (nonatomic, readonly) NSInteger caseLevel;
/// Headphones with one battery, such as AirPods Max.
@property (nonatomic, readonly) NSInteger main;
@property (nonatomic, readonly) BOOL isEmpty;

/// Pass `APBBatteryLevelNone` for anything not reported.
- (instancetype)initWithLeft:(NSInteger)left
                       right:(NSInteger)right
                   caseLevel:(NSInteger)caseLevel
                        main:(NSInteger)main NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// One battery shown on a device row: the earbuds, the case, or a single
/// battery.
@interface APBBatteryBadge : NSObject

/// At or below this level a badge is flagged as low.
@property (class, nonatomic, readonly) NSInteger lowLevel;

@property (nonatomic, readonly, copy) NSString *icon;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *spokenText;
@property (nonatomic, readonly) BOOL isLow;

- (instancetype)initWithIcon:(NSString *)icon
                        text:(NSString *)text
                  spokenText:(NSString *)spokenText
                       level:(NSInteger)level NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface APBBatteryLevels (Badges)
/// Earbuds first, then the case, each only while it reports a level. The
/// earbuds share a badge, one number when they match and named by side
/// otherwise, flagged low when either is.
@property (nonatomic, readonly) NSArray<APBBatteryBadge *> *badges;
@end

@interface APBBluetoothBatteryReport : NSObject

/// Keyed by address, uppercased hex digits with separators removed.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, APBBatteryLevels *> *byAddress;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, APBBatteryLevels *> *byName;

- (instancetype)initWithByAddress:(NSDictionary<NSString *, APBBatteryLevels *> *)byAddress
                           byName:(NSDictionary<NSString *, APBBatteryLevels *> *)byName NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

/// Levels for an audio device. CoreAudio gives a Bluetooth device a UID built
/// from its address, such as `70-AE-2A-5E-21-CD:output`; the name is a
/// fallback for a UID in some other shape.
- (nullable APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device;

@end

@interface APBBluetoothBattery : NSObject
+ (NSString *)normalizedAddress:(NSString *)text;
/// Parses `system_profiler -json SPBluetoothDataType`, keeping connected Apple
/// headphones that report at least one level.
+ (APBBluetoothBatteryReport *)parse:(NSData *)data;
@end

typedef void (^APBBatteryReadCompletion)(NSData *_Nullable data);
typedef void (^APBBatteryRead)(APBBatteryReadCompletion completion);

FOUNDATION_EXPORT NSNotificationName const APBBluetoothBatteryDidChangeNotification;

/// Reads AirPods battery levels from `system_profiler`, which needs no
/// Bluetooth permission. Each read takes a few hundred milliseconds, so it runs
/// off the main thread and only when asked. Posts
/// `APBBluetoothBatteryDidChangeNotification` when the report changes.
@interface APBBluetoothBatteryMonitor : NSObject

@property (nonatomic, readonly) APBBluetoothBatteryReport *report;

/// Reads with `system_profiler`.
- (instancetype)init;
/// `read` calls its completion on any thread.
- (instancetype)initWithRead:(APBBatteryRead)read NS_DESIGNATED_INITIALIZER;

- (nullable APBBatteryLevels *)levelsForDevice:(APBAudioDevice *)device;
/// Starts a read, or queues one more if a read is already running so a change
/// made during it is not missed.
- (void)refresh;

+ (APBBatteryRead)systemProfiler;

@end

NS_ASSUME_NONNULL_END
